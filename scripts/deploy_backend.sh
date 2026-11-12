#!/usr/bin/env bash
# Deploys the ReSky database and edge functions to your Supabase project.
# Requires the Supabase CLI (https://supabase.com/docs/guides/cli) and:
#   supabase login && supabase link --project-ref <your-project-ref>
set -euo pipefail
cd "$(dirname "$0")/.."
supabase db push
for fn in login livekit-token verify-purchase appstore-notifications register-profile-asset delete-account push-notify; do
  supabase functions deploy "$fn" --no-verify-jwt   # each function verifies the caller itself
done
echo "Now set secrets: see README section 'Backend secrets'."
