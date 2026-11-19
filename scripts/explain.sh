#!/usr/bin/env bash
#
# Show the target query's plan with and without the covering index, so the
# effect of the Part 5 index is measured rather than asserted.
#
#   ./scripts/explain.sh
#   ./scripts/explain.sh --no-color
#
# What it does:
#   1. drops idx_hotel_bookings_city_created_at
#   2. ANALYZE, then EXPLAIN (ANALYZE, BUFFERS) the target query  -> "before"
#   3. recreates the index exactly as 0003_indexes.sql defines it
#   4. VACUUM (ANALYZE), then EXPLAIN the same query              -> "after"
#
# Step 4 uses VACUUM, not just ANALYZE, because an index-only scan still has to
# visit the heap for pages the visibility map does not mark all-visible. Without
# it the "after" plan reports non-zero Heap Fetches and understates the win.
#
# The index is left in place when the script finishes, including on failure.

set -euo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

for arg in "$@"; do
  case "${arg}" in
    --no-color) C_RESET=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE='' ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) die "unknown option: ${arg}" ;;
  esac
done

INDEX_NAME="idx_hotel_bookings_city_created_at"

CREATE_INDEX_SQL="CREATE INDEX IF NOT EXISTS ${INDEX_NAME}
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);"

TARGET_QUERY="SELECT org_id, status, COUNT(*) AS bookings, SUM(amount) AS total_amount
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;"

require_db_running
wait_for_db 120

# Whatever happens, put the index back. A benchmark script that can leave the
# database slower than it found it is a trap.
restore_index() {
  local status=$?
  if [ "$(psql_scalar "${POSTGRES_DB}" "SELECT COUNT(*) FROM pg_indexes WHERE schemaname='public' AND indexname='${INDEX_NAME}'")" != "1" ]; then
    warn "recreating ${INDEX_NAME} after an interrupted run"
    psql_main -q -c "${CREATE_INDEX_SQL}" || true
  fi
  exit "${status}"
}
trap restore_index EXIT

ROWS_TOTAL="$(psql_scalar "${POSTGRES_DB}" 'SELECT COUNT(*) FROM hotel_bookings')"
ROWS_MATCHING="$(psql_scalar "${POSTGRES_DB}" "SELECT COUNT(*) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'")"

printf '\n'
log "target query population"
detail "hotel_bookings rows total        : ${ROWS_TOTAL}"
detail "rows matching the WHERE clause   : ${ROWS_MATCHING}"
detail "selectivity                      : $(awk -v a="${ROWS_MATCHING}" -v b="${ROWS_TOTAL}" 'BEGIN{ if (b>0) printf "%.1f%%", 100*a/b; else printf "n/a" }')"
printf '\n'

# --- before -------------------------------------------------------------------

log "dropping ${INDEX_NAME}"
psql_main -q -c "DROP INDEX IF EXISTS ${INDEX_NAME};"
psql_main -q -c "ANALYZE hotel_bookings;"

printf '\n%b----- BEFORE: without the covering index -----%b\n\n' "${C_YELLOW}" "${C_RESET}"
psql_main -c "EXPLAIN (ANALYZE, BUFFERS) ${TARGET_QUERY}"

# --- after --------------------------------------------------------------------

printf '\n'
log "creating ${INDEX_NAME}"
psql_main -q -c "${CREATE_INDEX_SQL}"

# Outside a transaction, so VACUUM is allowed.
psql_main -q -c "VACUUM (ANALYZE) hotel_bookings;"

printf '\n%b----- AFTER: with (city, created_at DESC) INCLUDE (org_id, status, amount) -----%b\n\n' "${C_GREEN}" "${C_RESET}"
psql_main -c "EXPLAIN (ANALYZE, BUFFERS) ${TARGET_QUERY}"

printf '\n'
log "index inventory"
psql_main -f /queries/03_index_inventory.sql

printf '\n'
ok "${INDEX_NAME} is in place"
detail "read the plans above: look for 'Index Only Scan' and 'Heap Fetches: 0' in the AFTER section."
detail "at this table size both plans are fast in absolute terms; what the index changes is the"
detail "access pattern - shared buffer hits and rows discarded - which is what scales."
