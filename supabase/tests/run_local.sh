#!/usr/bin/env bash
# Runs the schema + row-level security tests against a local, throwaway Postgres.
# Usage: supabase/tests/run_local.sh   (needs psql/createdb on PATH and a local server)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="${DB:-kharcha_test}"
dropdb --if-exists "$db" && createdb "$db"
psql -q -v ON_ERROR_STOP=1 -d "$db" < "$here/supabase_stub.sql"
psql -q -v ON_ERROR_STOP=1 -d "$db" < "$here/../migrations/20261109000000_init.sql"
psql -q -v ON_ERROR_STOP=1 -d "$db" < "$here/rls_test.sql"
echo "All database checks passed."
