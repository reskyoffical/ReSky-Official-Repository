// Called by the app after a StoreKit 2 purchase / restore with the signed
// transaction (JWS). The signature is verified against Apple's root CA.
import { applyTransaction, verifyTransaction } from "../_shared/appstore.ts";
import { adminClient, handle, HttpError, json, requireUser } from "../_shared/util.ts";

Deno.serve(handle(async (req) => {
  const user = await requireUser(req);
  const { signed_transaction } = await req.json().catch(() => ({}));
  if (typeof signed_transaction !== "string") throw new HttpError(400, "signed_transaction_required");

  let verified;
  try { verified = await verifyTransaction(signed_transaction); }
  catch (_) { throw new HttpError(400, "invalid_transaction"); }

  const token = verified.tx.appAccountToken?.toLowerCase();
  if (token && token !== user.id.toLowerCase()) throw new HttpError(403, "transaction_for_other_account");

  try { await applyTransaction(user.id, verified.tx, verified.environment); }
  catch (e) { throw new HttpError(409, (e as Error).message); }

  const { data } = await adminClient().rpc("has_plus", { uid: user.id });
  return json({ is_plus: !!data });
}));
