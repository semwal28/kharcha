#!/usr/bin/env bash
# Sets up the Spendwell backend on your Supabase project in one go:
# database tables + security rules, the AI key, and both server functions.
#
# Before you run it:
#   1. Install the Supabase CLI: https://supabase.com/docs/guides/cli
#   2. Log in:                   supabase login
#   3. Optional, for the AI coach, put ONE key in the environment:
#        export AI_API_KEY=...         free, from https://console.groq.com/keys
#        export ANTHROPIC_API_KEY=...  Claude, from https://platform.claude.com
#      With neither, the app answers on the device instead.
#
# Usage: scripts/deploy_backend.sh <project-ref>
#   (the project ref is the part of your project URL before .supabase.co)
set -euo pipefail

ref="${1:?Usage: scripts/deploy_backend.sh <project-ref>}"
cd "$(dirname "$0")/.."

echo "→ Linking project $ref"
supabase link --project-ref "$ref"

echo "→ Creating tables and security rules"
supabase db push

secrets_file="$(mktemp)"
trap 'rm -f "$secrets_file"' EXIT
for name in AI_API_KEY AI_BASE_URL AI_MODEL ANTHROPIC_API_KEY CLAUDE_MODEL; do
  if [ -n "${!name:-}" ]; then printf '%s=%s\n' "$name" "${!name}" >> "$secrets_file"; fi
done
if [ -s "$secrets_file" ]; then
  echo "→ Saving the AI key as a server secret"
  supabase secrets set --env-file "$secrets_file"
else
  echo "→ No AI key set: the app will answer on the device"
fi

echo "→ Deploying server functions"
supabase functions deploy ai-coach
supabase functions deploy delete-account

cat <<'DONE'

Backend ready. Two steps left in the Supabase dashboard:
  • Authentication → Email templates → Magic link: include {{ .Token }} so people get a 6-digit code.
  • Settings → API: copy the project URL and the publishable key for the app build.
DONE
