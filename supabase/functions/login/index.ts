// Username-or-email login. Looks up the email server-side so the app never
// learns whether a username exists (protects against account enumeration),
// and rate-limits attempts per identifier and per IP.
import { createClient } from "npm:@supabase/supabase-js@2";
import { adminClient, env, handle, HttpError, json } from "../_shared/util.ts";

const WINDOW_MINUTES = 15;
const MAX_ATTEMPTS = 10;
const GENERIC = "invalid_credentials";

Deno.serve(handle(async (req) => {
  const { identifier, password } = await req.json().catch(() => ({}));
  if (typeof identifier !== "string" || typeof password !== "string" || !identifier || !password) {
    throw new HttpError(400, GENERIC);
  }
  const admin = adminClient();
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
  const id = identifier.trim().toLowerCase();
  const since = new Date(Date.now() - WINDOW_MINUTES * 60_000).toISOString();

  for (const key of [`id:${id}`, `ip:${ip}`]) {
    const { count } = await admin.from("login_attempts").select("id", { count: "exact", head: true })
      .eq("key", key).gte("attempted_at", since);
    if ((count ?? 0) >= MAX_ATTEMPTS * (key.startsWith("ip:") ? 3 : 1)) {
      throw new HttpError(429, "too_many_attempts");
    }
  }

  let email: string | null = null;
  if (id.includes("@")) {
    email = id;
  } else {
    const { data: profile } = await admin.from("profiles").select("id").ilike("username", id).maybeSingle();
    if (profile) {
      const { data: u } = await admin.auth.admin.getUserById(profile.id);
      email = u?.user?.email ?? null;
    }
  }

  const fail = async () => {
    await admin.from("login_attempts").insert([{ key: `id:${id}` }, { key: `ip:${ip}` }]);
    await new Promise((r) => setTimeout(r, 300 + Math.random() * 300));
    throw new HttpError(401, GENERIC);
  };
  if (!email) return await fail();

  const anon = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await anon.auth.signInWithPassword({ email, password });
  if (error || !data.session) {
    if (error?.message?.toLowerCase().includes("email not confirmed")) {
      throw new HttpError(403, "email_not_confirmed");
    }
    return await fail();
  }

  const { data: prof } = await admin.from("profiles").select("suspended_until").eq("id", data.user.id).single();
  const suspended = prof?.suspended_until && new Date(prof.suspended_until) > new Date();

  return json({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    suspended_until: suspended ? prof!.suspended_until : null,
  });
}));
