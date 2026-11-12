#!/usr/bin/env bash
# ReSky — one-time Founder account bootstrap.
#
# Creates the "resky_founder" account through the Supabase Admin API using your
# SERVICE ROLE key. The role is set via app_metadata, which ordinary sign-ups
# cannot set, and the database trigger refuses to create a second founder.
#
# The password is typed by you at the prompt. It is never written to disk or
# placed in the app or the repo.
#
# Usage:
#   SUPABASE_URL=https://xxxx.supabase.co SUPABASE_SERVICE_ROLE_KEY=... ./scripts/bootstrap_founder.sh
set -euo pipefail

: "${SUPABASE_URL:?Set SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY (Project Settings > API)}"

USERNAME="${FOUNDER_USERNAME:-resky_founder}"
read -r -p "Founder email address: " EMAIL
read -r -p "Founder display name [ReSky Founder]: " DISPLAY
DISPLAY="${DISPLAY:-ReSky Founder}"
while true; do
  read -r -s -p "Choose founder password (min 12 chars): " PASS; echo
  read -r -s -p "Repeat password: " PASS2; echo
  [[ "$PASS" == "$PASS2" ]] || { echo "Passwords do not match."; continue; }
  [[ ${#PASS} -ge 12 ]] || { echo "Use at least 12 characters."; continue; }
  break
done

BODY=$(python3 - "$EMAIL" "$PASS" "$USERNAME" "$DISPLAY" <<'PY'
import json, sys
email, pw, user, disp = sys.argv[1:5]
print(json.dumps({
  "email": email, "password": pw, "email_confirm": True,
  "user_metadata": {"username": user, "display_name": disp},
  "app_metadata": {"bootstrap_role": "founder"}
}))
PY
)

RESP=$(curl -sS -w "\n%{http_code}" -X POST "$SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data-binary @- <<<"$BODY")
CODE=$(tail -n1 <<<"$RESP")
unset PASS PASS2 BODY

if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
  echo "✅ Founder account created."
  echo "   Sign in to ReSky with username: $USERNAME  (or the email you entered)"
  echo "   Then open Profile > Founder Settings to enable two-factor authentication."
else
  echo "❌ Failed (HTTP $CODE):"
  head -n -1 <<<"$RESP"
  echo "If it says 'founder_already_exists', a founder account already exists."
  exit 1
fi
