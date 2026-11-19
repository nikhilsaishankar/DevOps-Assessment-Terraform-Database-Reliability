#!/usr/bin/env bash
#
# Restore a dump into a FRESH database and prove the restore worked.
#
#   ./scripts/restore.sh                          # restore the latest dump
#   ./scripts/restore.sh backups/hotels_....dump  # restore a specific dump
#   ./scripts/restore.sh --target hotels_check    # choose the target database
#   ./scripts/restore.sh --into-source --force    # overwrite the source database
#   ./scripts/restore.sh --help
#
# By default the dump is restored into a brand new database next to the source
# (hotels -> hotels_restored) rather than over the top of it. Two reasons:
#
#   1. The brief asks for a restore "into a fresh local database", and a fresh
#      database is the only way to show the dump alone is sufficient - restoring
#      over an existing database cannot distinguish data that came from the dump
#      from data that was already there.
#   2. It is non-destructive, so a restore drill can be run against a live local
#      database without risking the data in it. Overwriting the source requires
#      the explicit --into-source --force combination.
#
# After restoring, the script compares row counts, aggregates and index
# definitions between source and restored database, and exits non-zero if they
# disagree.

set -euo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DUMP_ARG=""
TARGET_DB=""
INTO_SOURCE="false"
FORCE="false"
JOBS="1"

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
  cat <<'USAGE'
Options:
  --target NAME     Database to restore into. Default: <source>_restored.
  --into-source     Restore over the source database instead of a fresh one.
                    Destructive; requires --force.
  --force           Do not prompt before dropping an existing target database.
  --jobs N          Parallel restore workers. Only valid for custom-format
                    dumps read from a file (not from stdin). Default 1.
  -h, --help        Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)      TARGET_DB="${2:?--target needs a value}"; shift 2 ;;
    --into-source) INTO_SOURCE="true"; shift ;;
    --force)       FORCE="true"; shift ;;
    --jobs)        JOBS="${2:?--jobs needs a value}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    -*)            die "unknown option: $1 (try --help)" ;;
    *)             DUMP_ARG="$1"; shift ;;
  esac
done

require_db_running
wait_for_db 120

# --- locate the dump ----------------------------------------------------------

if [ -n "${DUMP_ARG}" ]; then
  DUMP_FILE="${DUMP_ARG}"
  # Accept a path relative to the repository root as well as to $PWD.
  if [ ! -f "${DUMP_FILE}" ] && [ -f "${REPO_ROOT}/${DUMP_ARG}" ]; then
    DUMP_FILE="${REPO_ROOT}/${DUMP_ARG}"
  fi
else
  if   [ -f "${BACKUP_PATH}/latest.dump" ]; then DUMP_FILE="${BACKUP_PATH}/latest.dump"
  elif [ -f "${BACKUP_PATH}/latest.sql" ];  then DUMP_FILE="${BACKUP_PATH}/latest.sql"
  else
    die "no dump given and no latest.dump in ${BACKUP_PATH}. Run ./scripts/backup.sh first."
  fi
fi

[ -f "${DUMP_FILE}" ] || die "dump not found: ${DUMP_FILE}"
[ -s "${DUMP_FILE}" ] || die "dump is empty: ${DUMP_FILE}"

# Resolve the symlink so logs name the real file.
if [ -L "${DUMP_FILE}" ]; then
  DUMP_REAL="${BACKUP_PATH}/$(readlink "${DUMP_FILE}")"
else
  DUMP_REAL="${DUMP_FILE}"
fi

case "${DUMP_REAL}" in
  *.sql) DUMP_FORMAT="plain" ;;
  *)     DUMP_FORMAT="custom" ;;
esac

log "restoring from $(basename "${DUMP_REAL}") (${DUMP_FORMAT} format, $(human_size "${DUMP_REAL}"))"

# --- verify the dump's integrity before touching any database -----------------

if [ -f "${DUMP_REAL}.sha256" ]; then
  EXPECTED="$(awk '{print $1}' < "${DUMP_REAL}.sha256")"
  ACTUAL="$(sha256_of "${DUMP_REAL}")"
  if [ "${ACTUAL}" = "unavailable" ]; then
    warn "no sha256 tool available; skipping checksum verification"
  elif [ "${EXPECTED}" = "${ACTUAL}" ]; then
    ok "checksum matches the one recorded at backup time"
  else
    err "checksum mismatch - the dump has changed since it was written"
    detail "expected: ${EXPECTED}"
    detail "actual  : ${ACTUAL}"
    die "refusing to restore a dump that does not match its checksum"
  fi
else
  warn "no .sha256 file alongside the dump; skipping checksum verification"
fi

if [ "${DUMP_FORMAT}" = "custom" ]; then
  db_exec pg_restore --list < "${DUMP_REAL}" >/dev/null 2>&1 \
    || die "pg_restore cannot read the archive: ${DUMP_REAL}"
  ok "archive table of contents is readable"
fi

# --- choose the target --------------------------------------------------------

if [ "${INTO_SOURCE}" = "true" ]; then
  [ "${FORCE}" = "true" ] || die "--into-source is destructive and requires --force"
  TARGET_DB="${POSTGRES_DB}"
  warn "restoring over the SOURCE database '${TARGET_DB}'. Its current contents will be lost."
else
  TARGET_DB="${TARGET_DB:-${POSTGRES_DB}_restored}"
fi

# --- snapshot the source for comparison ---------------------------------------

SOURCE_COMPARABLE="true"
if [ "${INTO_SOURCE}" = "true" ]; then
  # The source is about to be replaced, so there is nothing to compare against.
  SOURCE_COMPARABLE="false"
else
  SRC_BOOKINGS="$(psql_scalar "${POSTGRES_DB}" 'SELECT COUNT(*) FROM hotel_bookings' || echo "n/a")"
  SRC_EVENTS="$(psql_scalar "${POSTGRES_DB}" 'SELECT COUNT(*) FROM booking_events' || echo "n/a")"
  SRC_AMOUNT="$(psql_scalar "${POSTGRES_DB}" 'SELECT COALESCE(SUM(amount), 0)::text FROM hotel_bookings' || echo "n/a")"
  SRC_INDEXES="$(psql_scalar "${POSTGRES_DB}" "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public'" || echo "n/a")"
fi

# --- drop and recreate the target ---------------------------------------------

TARGET_EXISTS="$(psql_scalar "postgres" "SELECT COUNT(*) FROM pg_database WHERE datname = '${TARGET_DB}'")"

if [ "${TARGET_EXISTS}" != "0" ]; then
  if [ "${FORCE}" != "true" ]; then
    printf 'Database "%s" already exists and will be DROPPED. Continue? [y/N] ' "${TARGET_DB}"
    read -r reply < /dev/tty || reply=""
    case "${reply}" in
      [yY]|[yY][eE][sS]) : ;;
      *) die "aborted by user; nothing was changed" ;;
    esac
  fi

  log "dropping existing database '${TARGET_DB}'"
  # FORCE terminates other sessions connected to it; without it the drop fails
  # whenever anything still holds a connection. Requires PostgreSQL 13+.
  psql_admin -q -c "DROP DATABASE IF EXISTS \"${TARGET_DB}\" WITH (FORCE)"
fi

log "creating fresh database '${TARGET_DB}'"
psql_admin -q -c "CREATE DATABASE \"${TARGET_DB}\" OWNER \"${POSTGRES_USER}\""

# --- restore ------------------------------------------------------------------

log "restoring into '${TARGET_DB}'"

if [ "${DUMP_FORMAT}" = "custom" ]; then
  RESTORE_LOG="$(mktemp)"

  # The archive is streamed in on stdin, which is why --jobs is only honoured
  # when it is 1: parallel restore needs to seek within a real file.
  if [ "${JOBS}" != "1" ]; then
    warn "--jobs ${JOBS} ignored: the archive is streamed on stdin, which parallel restore cannot seek"
  fi

  if ! db_exec env PGPASSWORD="${POSTGRES_PASSWORD}" \
        pg_restore \
          -U "${POSTGRES_USER}" \
          -d "${TARGET_DB}" \
          --no-owner \
          --no-privileges \
          --exit-on-error \
        < "${DUMP_REAL}" > "${RESTORE_LOG}" 2>&1; then
    err "pg_restore failed; last lines of its output:"
    tail -30 "${RESTORE_LOG}" >&2 || true
    rm -f "${RESTORE_LOG}"
    exit 1
  fi
  rm -f "${RESTORE_LOG}"
else
  psql_db "${TARGET_DB}" -q < "${DUMP_REAL}"
fi

ok "restore finished without errors"

# Fresh statistics, so the restored database plans queries the same way the
# source does. A restore that skips this looks slower than the original for
# reasons that have nothing to do with the data.
log "analysing the restored database"
psql_db "${TARGET_DB}" -q -c "ANALYZE"

# --- verify -------------------------------------------------------------------

log "verifying the restored database"

DST_BOOKINGS="$(psql_scalar "${TARGET_DB}" 'SELECT COUNT(*) FROM hotel_bookings')"
DST_EVENTS="$(psql_scalar "${TARGET_DB}" 'SELECT COUNT(*) FROM booking_events')"
DST_AMOUNT="$(psql_scalar "${TARGET_DB}" 'SELECT COALESCE(SUM(amount), 0)::text FROM hotel_bookings')"
DST_INDEXES="$(psql_scalar "${TARGET_DB}" "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public'")"
DST_ORPHANS="$(psql_scalar "${TARGET_DB}" 'SELECT COUNT(*) FROM booking_events e LEFT JOIN hotel_bookings b ON b.id = e.booking_id WHERE b.id IS NULL')"

FAILED=0

printf '\n'
printf '  %-26s %14s %14s %s\n' "check" "source" "restored" "result"
printf '  %-26s %14s %14s %s\n' "--------------------------" "--------------" "--------------" "------"

compare_row() {
  local label="$1" src="$2" dst="$3"
  if [ "${SOURCE_COMPARABLE}" != "true" ]; then
    printf '  %-26s %14s %14s %s\n' "${label}" "n/a" "${dst}" "-"
    return
  fi
  if [ "${src}" = "${dst}" ]; then
    printf '  %-26s %14s %14s %b\n' "${label}" "${src}" "${dst}" "${C_GREEN}match${C_RESET}"
  else
    printf '  %-26s %14s %14s %b\n' "${label}" "${src}" "${dst}" "${C_RED}MISMATCH${C_RESET}"
    FAILED=1
  fi
}

if [ "${SOURCE_COMPARABLE}" = "true" ]; then
  compare_row "hotel_bookings rows"  "${SRC_BOOKINGS}" "${DST_BOOKINGS}"
  compare_row "booking_events rows"  "${SRC_EVENTS}"   "${DST_EVENTS}"
  compare_row "SUM(amount)"          "${SRC_AMOUNT}"   "${DST_AMOUNT}"
  compare_row "indexes in public"    "${SRC_INDEXES}"  "${DST_INDEXES}"
else
  compare_row "hotel_bookings rows"  "n/a" "${DST_BOOKINGS}"
  compare_row "booking_events rows"  "n/a" "${DST_EVENTS}"
  compare_row "SUM(amount)"          "n/a" "${DST_AMOUNT}"
  compare_row "indexes in public"    "n/a" "${DST_INDEXES}"
fi
printf '\n'

# Checks that stand on their own, without needing the source.
if [ "${DST_BOOKINGS}" = "0" ]; then
  err "the restored database contains no bookings"
  FAILED=1
fi

if [ "${DST_ORPHANS}" != "0" ]; then
  err "${DST_ORPHANS} booking_events rows reference a booking that does not exist"
  FAILED=1
else
  ok "referential integrity: no orphan booking_events"
fi

# The covering index is what the query optimisation work depends on. A dump
# that restores rows but loses indexes is a silent performance regression.
if [ "$(psql_scalar "${TARGET_DB}" "SELECT COUNT(*) FROM pg_indexes WHERE schemaname='public' AND indexname='idx_hotel_bookings_city_created_at'")" = "1" ]; then
  ok "covering index idx_hotel_bookings_city_created_at is present"
else
  err "covering index idx_hotel_bookings_city_created_at is missing from the restored database"
  FAILED=1
fi

# And the data is actually queryable, not merely present.
log "running the target query against the restored database"
psql_db "${TARGET_DB}" -c "
SELECT org_id, status, COUNT(*) AS bookings, SUM(amount) AS total
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status
ORDER BY total DESC
LIMIT 5;"

printf '\n'
if [ "${FAILED}" -eq 0 ]; then
  ok "restore verified: '${TARGET_DB}' is consistent with the dump"
  detail "inspect it with: docker compose exec db psql -U ${POSTGRES_USER} -d ${TARGET_DB}"
  exit 0
else
  die "restore verification FAILED - see the mismatches above"
fi
