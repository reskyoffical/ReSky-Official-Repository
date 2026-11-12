# ReSky — "The conversations never ended."

A classic-Skype-style messenger for iPhone and iPad: SwiftUI app + Supabase backend + LiveKit calls, built by Codemagic.

```
ReSky/                     iOS app source (SwiftUI, iOS 17+)
  App/ Authentication/ Founder/ Dashboard/ Contacts/ Conversations/
  Messaging/ Calling/ Media/ Profiles/ Customisation/ Subscriptions/
  Moderation/ Notifications/ Settings/ Backend/ Database/ Utilities/
  Assets/Assets.xcassets   app icon + your ReSky logo
  Audio/                   app sounds (Startup/ Messaging/ Notifications/ Calls/ UI/)
  Config/                  build-time backend settings (filled in by Codemagic)
Tests/                     unit tests (username rules, date parsing)
supabase/migrations/       database schema, security rules, moderation, seed data
supabase/functions/        edge functions (login, calls, purchases, push, uploads, account deletion)
scripts/                   deploy_backend.sh, bootstrap_founder.sh
project.yml                XcodeGen spec (Codemagic turns it into ReSky.xcodeproj)
codemagic.yaml             Codemagic workflows
```

---

## What you need (accounts & costs)

| Service | Why | Cost |
|---|---|---|
| Apple Developer Program | Signing, TestFlight, App Store, push, in-app purchase | £79/$99 per year |
| Codemagic | Builds the iOS app in the cloud (no Mac needed) | Free tier: 500 build min/month |
| Supabase | Accounts, database, realtime messaging, file storage | Free tier works to start |
| LiveKit Cloud | Voice/video call servers (WebRTC) | Free tier to start |
| GitHub (or GitLab/Bitbucket) | Codemagic builds from a git repo | Free |
| Supabase CLI *(optional)* | Easiest way to deploy the backend | Free |

---

## 1. Supabase (backend)

1. Create a project at supabase.com. Note **Project URL**, **anon/publishable key**, **service_role key** (Project Settings → API).
2. **Database:** (if you already ran the earlier migrations, also run `20261112000004_themes.sql`) either
   - CLI: `supabase login && supabase init && supabase link --project-ref <ref> && ./scripts/deploy_backend.sh`, or
   - Dashboard → SQL Editor: paste and run the 3 files in `supabase/migrations/` **in order**.
3. **Auth settings** (Authentication → Sign In / Providers → Email):
   - Enable **Confirm email**.
   - Minimum password length 8. Turn on **leaked password protection** if available on your plan.
   - URL Configuration → add redirect URL **`resky://auth-callback`**.
   - Customise the email templates with the ReSky name if you like.
4. **Edge functions:** `./scripts/deploy_backend.sh` deploys all of them (or `supabase functions deploy <name> --no-verify-jwt` one by one — each function checks the caller itself).
5. **Backend secrets** (Edge Functions → Secrets, or `supabase secrets set KEY=value`):

| Secret | Value |
|---|---|
| `LIVEKIT_URL` | `wss://<your-project>.livekit.cloud` |
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | from LiveKit Cloud → Settings → Keys |
| `APP_BUNDLE_ID` | `com.oopsware.resky` |
| `APP_APPLE_ID` | numeric Apple ID of the app in App Store Connect |
| `APPLE_ROOT_CA_G3_B64` | `curl -sO https://www.apple.com/certificateauthority/AppleRootCA-G3.cer && base64 -i AppleRootCA-G3.cer` |
| `PLUS_PRODUCT_IDS` | `com.oopsware.resky.plus.monthly` |
| `APNS_KEY_ID` / `APNS_TEAM_ID` | from your APNs key (step 4) |
| `APNS_PRIVATE_KEY` | full contents of the `.p8` file |
| `PUSH_WEBHOOK_SECRET` | any long random string |

(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are provided to functions automatically.)

6. **Push webhooks:** Database → Webhooks → create two webhooks: INSERT on `public.messages` and INSERT on `public.calls`, type *Supabase Edge Function* → `push-notify`, with HTTP header `x-webhook-secret: <PUSH_WEBHOOK_SECRET>`.

---

## 2. Founder account (your creator login)

The Founder account is **not** hardcoded anywhere. You create it once, from your own computer, with your service-role key:

```bash
SUPABASE_URL=https://<ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<service_role key> \
./scripts/bootstrap_founder.sh
```

It asks for your email and a password (typed privately, never saved). Then sign in to ReSky with:

- **Username:** `resky_founder` (or your email)
- **Password:** the one you just chose

How it is protected:
- The founder role is set through Supabase `app_metadata`, which normal sign-ups cannot write. The database refuses to create a second founder.
- Founder status is a `role` column keyed to your **user id**. All premium checks (`has_plus`) and admin checks (`is_founder`, `is_staff`) run in the database. They never compare usernames, so renaming yourself in Founder Settings keeps every privilege.
- Reserved names (`admin`, `founder`, `resky`, `support`, `official`…) are blocked for everyone except the founder.
- Once you turn on 2FA (Founder Settings → Two-factor authentication), admin actions require a 2FA-verified session.
- Never put the service-role key in the app or in Codemagic. It only belongs in your terminal and in Supabase.

---

## 3. LiveKit (calls)

Create a project at cloud.livekit.io. Copy the WebSocket URL, API key and secret into the Supabase secrets above. The app asks the `livekit-token` function for a short-lived token, and only the caller or callee of that specific call can get one.

---

## 4. Apple Developer / App Store Connect

1. **Identifiers:** register App ID `com.oopsware.resky` with **Push Notifications** enabled. If you change the bundle id, update `project.yml`, `codemagic.yaml` and `APP_BUNDLE_ID`.
2. **Keys:** create an **APNs key** (.p8) and put its id, your team id and contents in the Supabase secrets. Create an **App Store Connect API key** (Users and Access → Integrations) for Codemagic.
3. **App Store Connect → My Apps → +** create "ReSky". Copy its Apple ID number (into `codemagic.yaml` → `APP_STORE_APPLE_ID` and the `APP_APPLE_ID` secret).
4. **Subscription:** Monetisation → Subscriptions → create group "ReSky Plus" → auto-renewable subscription, product id **`com.oopsware.resky.plus.monthly`**, 1 month, price £2.99. Add a review screenshot and description.
5. **App Store Server Notifications V2** (App Information): set Production and Sandbox URL to
   `https://<ref>.supabase.co/functions/v1/appstore-notifications`
6. Publish real **Terms** and **Privacy Policy** pages and update the two URLs in `ReSky/App/AppConfig.swift` (App Review requires them for subscriptions).

---

## 5. Codemagic

1. Push this folder to a new GitHub repo and add it in Codemagic (choose **codemagic.yaml** configuration).
2. **Environment variables** → create group **`resky_config`**:
   - `SUPABASE_HOST` = `<ref>.supabase.co` (host only)
   - `SUPABASE_ANON_KEY` = your anon/publishable key (this one is meant to be public; security comes from the database rules)
3. Run **`resky-check`** first. It compiles for the Simulator with no signing, so you can catch build errors without an Apple account. **It does not produce an .ipa.**
3b. To get an installable file without an Apple Developer account, run **`resky-unsigned-ipa`**. Download `ReSky-unsigned.ipa` from the build's **Artifacts** and install it with Sideloadly or AltStore (they sign it with your free Apple ID; it expires after 7 days and must be refreshed). Push notifications and in-app purchases won't work in a sideloaded build, but everything else does.
4. For TestFlight: Team settings → Integrations → **Developer Portal** → add your App Store Connect API key named **`ReSky ASC`**. Then Code signing identities → generate/upload an **iOS Distribution** certificate. Set `APP_STORE_APPLE_ID` in `codemagic.yaml` and run **`resky-release`**. The build uploads to TestFlight.

---

## Feature status — what works and what doesn't

**Implemented in code:**
- **Accounts:** sign-in by username or email (enumeration-safe, rate-limited), sign-up with live username check, password rules, DOB (13+), email verification, password reset, Keychain-persisted sessions, logout, log out other devices, account deletion, TOTP 2FA.
- **Messaging:** 1:1 and group chats, realtime delivery, offline outbox with idempotent retries, local SwiftData cache, typing indicators, read receipts (privacy-respecting), reactions, reply, edit, delete, forward, unread badges, server-side search, push notifications.
- **Media:** photos, videos, documents and audio with upload/download progress, retry, 50 MB limit, private storage with membership-checked access, full-screen viewer, save to Photos.
- **Calls:** 1:1 voice and video over LiveKit WebRTC with incoming/outgoing screens, mute, speaker, camera on/off and flip, duration, missed/declined handling, and call history. Nothing is recorded.
- **Profiles:** avatar, banner and background uploads. Animation is detected **on the server**. Animated art is saved but locked without Plus. 8 app themes with their own artwork (Classic Blue and Dark Mode free; Sunset, Green Nature, Neon, Winter, Minimalist and Retro with ReSky Plus — all unlocked for the founder), plus accent colours, borders, decorations, FOUNDER/MOD/PLUS badges and the gold founder border.
- **ReSky Plus:** StoreKit 2 purchase/restore/renewal status/manage. Transactions are verified server-side against Apple's root CA. App Store Server Notifications handle renewals and refunds. The founder bypasses everything server-side.
- **Moderation:** server-side username/display-name filtering (NFKC, accents, leetspeak, Cyrillic look-alikes, repeated letters, reserved names). Also report/block, plus an admin dashboard for reports, suspensions, identity resets, image removal, moderators and cosmetics (including unreleased previews).
- **Polish:** startup chime, original sounds with per-sound toggles and volume channels, haptics, light/dark and iPad split view. (No intro animation — the app opens straight to sign-in.)

**Honest limitations — please read:**
- **Not yet compiled.** This was written without access to Xcode. Run `resky-check` first and send me any build errors; small SDK-version fixes are likely.
- **Calls when the app is fully closed** arrive as a normal push notification ("Incoming call"), not a full-screen ringing call. That needs CallKit + PushKit VoIP pushes (a VoIP certificate and extra code). **Picture-in-picture** for video is not implemented. **Group calls** are not implemented (group *chats* are).
- **Cross-platform:** the backend API is platform-neutral (any Supabase + LiveKit client can use it), but **only the iOS client exists**. Android/Windows/Mac/web apps have not been built.
- **Encryption:** TLS in transit, WebRTC DTLS-SRTP for calls, and provider encryption at rest. It is **not end-to-end encrypted**, and the app says so in Settings → Security & encryption.
- **Username blocklist** is a starter list. Extend `public.banned_terms` before launch.
- **Sounds:** the 12 sounds in `ReSky/Audio/` (messages, calls, contact online/offline, notification, error, click and the startup intro) are the files you supplied, converted to WAV. Make sure you have the right to distribute them before releasing the app.
- **Logo/trademark:** your ReSky logo's white rounded lettering on a blue cloud is very close to Skype's trademarked logo style. App Review (guideline 5.2) or Microsoft could object. Consider a more distinct mark before public release.
