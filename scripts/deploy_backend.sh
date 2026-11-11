#!/usr/bin/env bash
# Sets up the Spendwell backend on your Supabase project in one go:
# database tables + security rules, the Claude key, and both server functions.
#
# Before you run it:
#   1. Install the Supabase CLI: https://supabase.com/docs/guides/cli
#   2. Log in:                   supabase login
#   3. Put your Claude API key in the environment (from https://platform.claude.com):
#        export ANTHROPIC_API_KEY=...
#
# Usage: scripts/deploy_backend.sh <project-ref>
#   (the project ref is the part of your project URL before .supabase.co)
set -euo pipefail

ref="${1:?Usage: scripts/deploy_backend.sh <project-ref>}"
: "${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY first (create one at platform.claude.com)}"
cd "$(dirname "$0")/.."

echo "→ Linking project $ref"
supabase link --project-ref "$ref"

echo "→ Creating tables and security rules"
supabase db push

echo "→ Saving the Claude API key as a server secret"
secrets_file="$(mktemp)"
trap 'rm -f "$secrets_file"' EXIT
printf 'ANTHROPIC_API_KEY=%s\n' "$ANTHROPIC_API_KEY" > "$secrets_file"
supabase secrets set --env-file "$secrets_file"

echo "→ Deploying server functions"
supabase functions deploy ai-coach
supabase functions deploy delete-account

cat <<'DONE'

Backend ready. Two steps left in the Supabase dashboard:
  • Authentication → Email templates → Magic link: include {{ .Token }} so people get a 6-digit code.
  • Settings → API: copy the project URL and the publishable key for the app build.
DONE
