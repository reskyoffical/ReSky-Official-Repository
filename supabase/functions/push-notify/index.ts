// Sends APNs push notifications for new messages and incoming calls.
// Triggered by Supabase Database Webhooks (INSERT on public.messages and
// public.calls) with header  x-webhook-secret: <PUSH_WEBHOOK_SECRET>.
// Deploy with --no-verify-jwt.
import { adminClient, env, handle, json } from "../_shared/util.ts";

let cachedJwt: { token: string; at: number } | null = null;

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJwt(): Promise<string> {
  if (cachedJwt && Date.now() - cachedJwt.at < 40 * 60_000) return cachedJwt.token;
  const pem = env("APNS_PRIVATE_KEY").replace(/\\n/g, "\n");
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env("APNS_KEY_ID") }));
  const claims = b64url(JSON.stringify({ iss: env("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  const token = `${header}.${claims}.${b64url(sig)}`;
  cachedJwt = { token, at: Date.now() };
  return token;
}

async function send(deviceToken: string, environment: string | null, payload: unknown, pushType = "alert") {
  const host = environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const res = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJwt()}`,
      "apns-topic": env("APP_BUNDLE_ID"),
      "apns-push-type": pushType,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (res.status === 410 || res.status === 400) {
    // token no longer valid
    await adminClient().from("user_devices").update({ push_token: null }).eq("push_token", deviceToken);
  }
  return res.status;
}

async function tokensFor(userIds: string[]) {
  if (!userIds.length) return [];
  const { data } = await adminClient().from("user_devices").select("user_id, push_token, push_environment")
    .in("user_id", userIds).not("push_token", "is", null);
  return data ?? [];
}

Deno.serve(handle(async (req) => {
  if (req.headers.get("x-webhook-secret") !== env("PUSH_WEBHOOK_SECRET")) return json({ error: "forbidden" }, 403);
  const body = await req.json();
  if (body.type !== "INSERT") return json({ ok: true });
  const admin = adminClient();
  const rec = body.record;

  if (body.table === "messages") {
    if (rec.kind === "system" || !rec.sender_id) return json({ ok: true });
    const { data: sender } = await admin.from("profiles").select("display_name").eq("id", rec.sender_id).single();
    const { data: conv } = await admin.from("conversations").select("is_group, title").eq("id", rec.conversation_id).single();
    const { data: members } = await admin.from("conversation_members").select("user_id, muted")
      .eq("conversation_id", rec.conversation_id).neq("user_id", rec.sender_id);
    const recipients = (members ?? []).filter((m) => !m.muted).map((m) => m.user_id);
    const { data: prefs } = await admin.from("account_private")
      .select("user_id, notify_messages, show_previews, notify_sounds").in("user_id", recipients);
    const pref = new Map((prefs ?? []).map((p) => [p.user_id, p]));
    const previewFor: Record<string, string> = {
      image: "📷 Photo", video: "🎬 Video", audio: "🎵 Audio", file: "📎 File",
    };
    for (const t of await tokensFor(recipients)) {
      const p = pref.get(t.user_id);
      if (p && !p.notify_messages) continue;
      const text = p?.show_previews === false ? "New message" : (rec.kind === "text" ? String(rec.body ?? "").slice(0, 180) : previewFor[rec.kind] ?? "New message");
      await send(t.push_token!, t.push_environment, {
        aps: {
          alert: { title: conv?.is_group ? `${sender?.display_name} in ${conv.title ?? "Group"}` : sender?.display_name ?? "ReSky", body: text },
          sound: p?.notify_sounds === false ? undefined : "resky_message_in.wav",
          "thread-id": rec.conversation_id,
        },
        conversation_id: rec.conversation_id,
      });
    }
  } else if (body.table === "calls") {
    const { data: caller } = await admin.from("profiles").select("display_name").eq("id", rec.caller_id).single();
    const { data: p } = await admin.from("account_private").select("notify_calls").eq("user_id", rec.callee_id).maybeSingle();
    if (p && !p.notify_calls) return json({ ok: true });
    for (const t of await tokensFor([rec.callee_id])) {
      await send(t.push_token!, t.push_environment, {
        aps: {
          alert: { title: caller?.display_name ?? "ReSky", body: rec.kind === "video" ? "Incoming video call" : "Incoming call" },
          sound: "resky_ring_incoming.wav",
          "interruption-level": "time-sensitive",
        },
        call_id: rec.id,
      });
    }
  }
  return json({ ok: true });
}));
