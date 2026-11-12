// Issues a short-lived LiveKit token for a call the caller is part of.
import { AccessToken } from "npm:livekit-server-sdk@2";
import { adminClient, env, handle, HttpError, json, requireUser } from "../_shared/util.ts";

Deno.serve(handle(async (req) => {
  const user = await requireUser(req);
  const { call_id } = await req.json().catch(() => ({}));
  if (typeof call_id !== "string") throw new HttpError(400, "call_id_required");

  const admin = adminClient();
  const { data: call } = await admin.from("calls").select("*").eq("id", call_id).maybeSingle();
  if (!call || ![call.caller_id, call.callee_id].includes(user.id)) throw new HttpError(403, "forbidden");
  if (!["ringing", "active"].includes(call.status)) throw new HttpError(409, "call_finished");

  const { data: profile } = await admin.from("profiles").select("username, display_name").eq("id", user.id).single();
  const at = new AccessToken(env("LIVEKIT_API_KEY"), env("LIVEKIT_API_SECRET"), {
    identity: user.id,
    name: profile?.display_name ?? profile?.username ?? "ReSky user",
    ttl: "2h",
  });
  at.addGrant({ roomJoin: true, room: `call-${call.id}`, canPublish: true, canSubscribe: true });
  return json({ token: await at.toJwt(), url: env("LIVEKIT_URL"), room: `call-${call.id}` });
}));
