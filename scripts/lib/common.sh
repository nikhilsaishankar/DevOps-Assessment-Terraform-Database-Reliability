#!/usr/bin/env bash
# Shared helpers for the database scripts.
#
# Sourced, not executed. Everything here is intentionally POSIX-ish bash 3.2
# compatible, because macOS still ships bash 3.2 and these scripts have to run
# unchanged on a developer laptop and on an ubuntu-latest CI runner.

set -euo pipefail

# --- paths --------------------------------------------------------------------

# Resolve the repository root from this file's location, so the scripts work no
# matter which directory they are invoked from.
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_lib_dir}/../.." && pwd)"
export REPO_ROOT

# --- configuration ------------------------------------------------------------

# .env wins over the defaults below, environment variables win over .env.
if [ -f "${REPO_ROOT}/.env" ]; then
  # shellcheck disable=SC1091,SC2046
  set -a
  . "${REPO_ROOT}/.env"
  set +a
fi

POSTGRES_DB="${POSTGRES_DB:-hotels}"
POSTGRES_USER="${POSTGRES_USER:-hotels_admin}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-localdev_only_not_a_real_secret}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-10}"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-db}"

# Absolute, so a script can chdir freely afterwards.
case "${BACKUP_DIR}" in
  /*) BACKUP_PATH="${BACKUP_DIR}" ;;
  *)  BACKUP_PATH="${REPO_ROOT}/${BACKUP_DIR}" ;;
esac

export POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD POSTGRES_PORT
export BACKUP_DIR BACKUP_RETENTION BACKUP_PATH COMPOSE_SERVICE

# --- output -------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET='\033[0m'; C_DIM='\033[2m'; C_RED='\033[31m'
  C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'
else
  C_RESET=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

log()     { printf '%b==>%b %s\n'  "${C_BLUE}"   "${C_RESET}" "$*"; }
ok()      { printf '%b  ok%b %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
warn()    { printf '%bwarn%b %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
err()     { printf '%berr %b %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }
detail()  { printf '%b     %s%b\n' "${C_DIM}"    "$*" "${C_RESET}"; }
die()     { err "$*"; exit 1; }

# --- docker compose -----------------------------------------------------------

# Supports both the `docker compose` plugin and the legacy `docker-compose`
# binary, and fails with an actionable message rather than a stack trace.
COMPOSE_CMD=""
resolve_compose() {
  [ -n "${COMPOSE_CMD}" ] && return 0

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    die "neither 'docker compose' nor 'docker-compose' is available. Install Docker Desktop or the compose plugin, then re-run."
  fi

  if ! docker info >/dev/null 2>&1; then
    die "the Docker daemon is not reachable. Start Docker Desktop (or your engine) and re-run."
  fi
}

compose() {
  resolve_compose
  # shellcheck disable=SC2086
  ( cd "${REPO_ROOT}" && ${COMPOSE_CMD} "$@" )
}

# Run a command inside the database container with no TTY, so stdin/stdout can
# be piped (which is how dumps are streamed in and out).
db_exec() {
  compose exec -T "${COMPOSE_SERVICE}" "$@"
}

# --- database helpers ---------------------------------------------------------

require_db_running() {
  resolve_compose

  local state
  state="$(compose ps --status running --services 2>/dev/null | tr -d '\r' | grep -x "${COMPOSE_SERVICE}" || true)"

  if [ -z "${state}" ]; then
    die "the '${COMPOSE_SERVICE}' service is not running. Start it with: docker compose up -d"
  fi
}

# Block until the container's healthcheck passes, so a script run immediately
# after `docker compose up -d` does not race the first-boot initialisation.
wait_for_db() {
  local timeout="${1:-180}"
  local waited=0

  log "waiting for the database to accept connections"

  while [ "${waited}" -lt "${timeout}" ]; do
    if db_exec pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -q >/dev/null 2>&1; then
      ok "database is ready"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done

  die "database was not ready within ${timeout}s. Check: docker compose logs ${COMPOSE_SERVICE}"
}

# psql against an arbitrary database, failing on the first SQL error rather
# than plowing on and reporting success.
psql_db() {
  local dbname="$1"; shift
  db_exec env PGPASSWORD="${POSTGRES_PASSWORD}" \
    psql -v ON_ERROR_STOP=1 --no-psqlrc -U "${POSTGRES_USER}" -d "${dbname}" "$@"
}

psql_main() {
  psql_db "${POSTGRES_DB}" "$@"
}

# Single scalar value, whitespace stripped - convenient for counts.
psql_scalar() {
  local dbname="$1" sql="$2"
  psql_db "${dbname}" -tAq -c "${sql}" | tr -d '[:space:]'
}

# Maintenance connections go to the 'postgres' database, because you cannot
# drop or create a database while connected to it.
psql_admin() {
  psql_db "postgres" "$@"
}

human_size() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    printf 'missing'
    return
  fi
  # BSD stat (macOS) and GNU stat (Linux) take different flags.
  local bytes
  bytes="$(stat -f%z "${path}" 2>/dev/null || stat -c%s "${path}" 2>/dev/null || echo 0)"
  awk -v b="${bytes}" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
  }'
}

# sha256 is named differently on macOS and Linux.
sha256_of() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
  else
    printf 'unavailable'
  fi
}
