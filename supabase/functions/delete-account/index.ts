// Permanently deletes the caller's account and their uploaded files.
import { adminClient, handle, HttpError, json, requireUser } from "../_shared/util.ts";

Deno.serve(handle(async (req) => {
  const user = await requireUser(req);
  const { confirm } = await req.json().catch(() => ({}));
  if (confirm !== "DELETE") throw new HttpError(400, "confirmation_required");
  const admin = adminClient();

  const { data: files } = await admin.storage.from("profile").list(user.id, { limit: 1000 });
  if (files?.length) await admin.storage.from("profile").remove(files.map((f) => `${user.id}/${f.name}`));

  const { error } = await admin.auth.admin.deleteUser(user.id); // cascades to profiles and all owned rows
  if (error) throw new HttpError(500, "delete_failed");
  return json({ deleted: true });
}));
