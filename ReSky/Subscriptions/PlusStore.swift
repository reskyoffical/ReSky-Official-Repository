import Foundation
import StoreKit
import Supabase
import UIKit

/// ReSky Plus via StoreKit 2. Every purchase is verified by the backend (verify-purchase),
/// which is the only thing allowed to grant premium. The Founder never sees a paywall:
/// the server's has_plus() is always true for the founder role.
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()
    @Published var product: Product?
    @Published var purchasing = false
    @Published var lastError: String?
    @Published var renewalInfo: String?
    @Published var showPaywall = false
    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        do { product = try await Product.products(for: [AppConfig.plusProductID]).first }
        catch { lastError = "The App Store is unavailable right now." }
    }

    /// Call when a premium feature is tapped. Returns true if the user already has Plus.
    func requirePlus() -> Bool {
        if SessionStore.shared.isFounder || SessionStore.shared.hasPlus { return true }
        showPaywall = true
        return false
    }

    func purchase() async {
        guard !SessionStore.shared.isFounder else { return } // founder is never asked to pay
        await loadProduct()
        guard let product, let uid = SessionStore.shared.userId else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase(options: [.appAccountToken(uid)])
            switch result {
            case .success(let verification):
                await handle(verification)
            case .pending:
                lastError = "Your purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { lastError = "Couldn't reach the App Store." }
        for await result in Transaction.currentEntitlements { await handle(result) }
        await SessionStore.shared.loadProfile()
    }

    /// Re-validates current entitlements on launch (handles renewals made while the app was closed).
    func syncOnLaunch() async {
        for await result in Transaction.currentEntitlements { await handle(result) }
        await refreshRenewalInfo()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result, tx.productID == AppConfig.plusProductID else { return }
        do {
            struct Body: Encodable { let signed_transaction: String }
            struct Res: Decodable { let is_plus: Bool }
            let _: Res = try await supabase.functions.invoke("verify-purchase",
                                                             options: FunctionInvokeOptions(body: Body(signed_transaction: result.jwsRepresentation)))
            await tx.finish()
            await SessionStore.shared.loadProfile()
            Haptics.success()
        } catch {
            lastError = ReSkyError.message(error)
        }
    }

    func refreshRenewalInfo() async {
        await loadProduct()
        guard let statuses = try? await product?.subscription?.status, let status = statuses.first else {
            renewalInfo = nil
            return
        }
        var text: String
        switch status.state {
        case .subscribed: text = "Active"
        case .expired: text = "Expired"
        case .inGracePeriod: text = "In billing grace period"
        case .inBillingRetryPeriod: text = "Billing problem — update payment in Settings"
        case .revoked: text = "Revoked"
        default: text = "Unknown"
        }
        if case .verified(let renewal) = status.renewalInfo {
            text += renewal.willAutoRenew ? " · renews automatically" : " · will not renew"
        }
        renewalInfo = text
    }

    func manageSubscription() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshRenewalInfo()
    }
}
