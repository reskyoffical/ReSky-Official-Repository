// App Store Server Notifications V2 endpoint (renewals, expiry, refunds, cancellations).
// Set this URL in App Store Connect > App > App Information > App Store Server Notifications.
// Deploy with --no-verify-jwt (Apple does not send a Supabase token).
import { applyTransaction, verifyNotification } from "../_shared/appstore.ts";
import { adminClient, handle, json } from "../_shared/util.ts";

Deno.serve(handle(async (req) => {
  const { signedPayload } = await req.json().catch(() => ({}));
  if (typeof signedPayload !== "string") return json({ ok: false }, 400);

  let verified;
  try { verified = await verifyNotification(signedPayload); }
  catch (_) { return json({ ok: false }, 400); }

  const data = verified.payload.data;
  if (!data?.signedTransactionInfo) return json({ ok: true });
  const tx = await verified.verifier.verifyAndDecodeTransaction(data.signedTransactionInfo);
  let autoRenew: boolean | undefined;
  if (data.signedRenewalInfo) {
    const renewal = await verified.verifier.verifyAndDecodeRenewalInfo(data.signedRenewalInfo);
    autoRenew = renewal.autoRenewStatus === 1;
  }

  const admin = adminClient();
  let userId = tx.appAccountToken?.toLowerCase();
  if (!userId) {
    const { data: ent } = await admin.from("entitlements").select("user_id")
      .eq("original_transaction_id", tx.originalTransactionId!).maybeSingle();
    userId = ent?.user_id;
  }
  if (!userId) return json({ ok: true, note: "unknown account" });

  const env = String(data.environment ?? "").toLowerCase() === "sandbox" ? "sandbox" : "production";
  try { await applyTransaction(userId, tx, env, autoRenew); } catch (e) { console.error(e); }
  return json({ ok: true });
}));
