import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
} from "npm:@apple/app-store-server-library@1";
import { adminClient, env } from "./util.ts";

function verifiers(): SignedDataVerifier[] {
  // APPLE_ROOT_CA_G3_B64 = base64 of https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
  const roots = [Buffer.from(env("APPLE_ROOT_CA_G3_B64"), "base64")];
  const bundleId = env("APP_BUNDLE_ID");
  const appAppleId = Number(Deno.env.get("APP_APPLE_ID") ?? "0") || undefined;
  return [
    new SignedDataVerifier(roots, true, Environment.PRODUCTION, bundleId, appAppleId),
    new SignedDataVerifier(roots, true, Environment.SANDBOX, bundleId),
  ];
}

export async function verifyTransaction(jws: string): Promise<{ tx: JWSTransactionDecodedPayload; environment: string }> {
  let lastError: unknown;
  for (const [i, v] of verifiers().entries()) {
    try {
      const tx = await v.verifyAndDecodeTransaction(jws);
      return { tx, environment: i === 0 ? "production" : "sandbox" };
    } catch (e) { lastError = e; }
  }
  throw lastError;
}

export async function verifyNotification(signedPayload: string) {
  let lastError: unknown;
  for (const v of verifiers()) {
    try { return { verifier: v, payload: await v.verifyAndDecodeNotification(signedPayload) }; }
    catch (e) { lastError = e; }
  }
  throw lastError;
}

export const PLUS_PRODUCT_IDS = (Deno.env.get("PLUS_PRODUCT_IDS") ?? "com.oopsware.resky.plus.monthly").split(",");

/** Writes the entitlement row for a verified transaction. */
export async function applyTransaction(
  userId: string, tx: JWSTransactionDecodedPayload, environment: string, autoRenew?: boolean,
) {
  if (!tx.productId || !PLUS_PRODUCT_IDS.includes(tx.productId)) return;
  const admin = adminClient();
  const original = tx.originalTransactionId!;
  // An Apple subscription can only ever unlock ONE ReSky account.
  const { data: existing } = await admin.from("entitlements").select("user_id")
    .eq("original_transaction_id", original).maybeSingle();
  if (existing && existing.user_id !== userId) throw new Error("transaction_bound_to_other_account");

  await admin.from("entitlements").upsert({
    user_id: userId,
    plus_expires_at: tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null,
    product_id: tx.productId,
    original_transaction_id: original,
    environment,
    auto_renew: autoRenew ?? null,
    revoked: !!tx.revocationDate,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
}
