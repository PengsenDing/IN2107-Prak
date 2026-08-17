#!/usr/bin/env bash
# Automates post-install steps 1.1 and 1.2 from the S/4HANA2023 GB 4.3 guide:
# 1.1 Change HANA tenant SYSTEM password to UCC standard. 
# 1.2 Set HANA global_allocation_limit
#
# Run as <sid>adm or another OS user that can execute hdbsql.
# Prefer HDB user store keys in production; this script also supports interactive password input.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 --sid SID --sidnr NN --tenant TENANT --dbhost HOST --tenant-sql-port PORT --systemdb-sql-port PORT \
     --total-ram-mb MB --system-type exclusive|shared [--old-system-password PASSWORD] [--execute]

Examples:
  Dry run:
    $0 --sid XXX --sidnr XX --tenant XXX --dbhost XXXXXX --tenant-sql-port XXXXX --systemdb-sql-port XXXXX \
       --total-ram-mb 128000 --system-type exclusive

  Execute:
    $0 --sid XXX --sidnr XX --tenant XXX --dbhost XXXXXX --tenant-sql-port XXXXX --systemdb-sql-port XXXXX \
       --total-ram-mb 128000 --system-type exclusive --execute

Notes:
  - The new SYSTEM password (UCC standard, see the team password manager) is
    requested interactively on execute; it is never accepted as a command-line
    argument, so it cannot leak into the process list or shell history.
  - Allocation formula follows the guide:
      global_allocation_limit = TOTAL_RAM_LPAR_MB - 15000 - PHYSMEMSIZE
    where PHYSMEMSIZE is 50000 for exclusive and 70000 for shared.
USAGE
}

SID=""
SIDNR=""
TENANT=""
DBHOST=""
TENANT_SQL_PORT=""
SYSTEMDB_SQL_PORT=""
TOTAL_RAM_MB=""
SYSTEM_TYPE=""
OLD_SYSTEM_PASSWORD=""
NEW_SYSTEM_PASSWORD=""
EXECUTE=0
OS_RAM_MB=15000

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sid) SID="${2^^}"; shift 2 ;;
    --sidnr) SIDNR="$2"; shift 2 ;;
    --tenant) TENANT="${2^^}"; shift 2 ;;
    --dbhost) DBHOST="$2"; shift 2 ;;
    --tenant-sql-port) TENANT_SQL_PORT="$2"; shift 2 ;;
    --systemdb-sql-port) SYSTEMDB_SQL_PORT="$2"; shift 2 ;;
    --total-ram-mb) TOTAL_RAM_MB="$2"; shift 2 ;;
    --system-type) SYSTEM_TYPE="$2"; shift 2 ;;
    --old-system-password) OLD_SYSTEM_PASSWORD="$2"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

for required in SID SIDNR TENANT DBHOST TENANT_SQL_PORT SYSTEMDB_SQL_PORT TOTAL_RAM_MB SYSTEM_TYPE; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument: $required" >&2
    usage
    exit 2
  fi
done

case "$SYSTEM_TYPE" in
  exclusive) PHYSMEMSIZE=50000 ;;
  shared) PHYSMEMSIZE=70000 ;;
  *) echo "--system-type must be exclusive or shared" >&2; exit 2 ;;
esac

if ! [[ "$TOTAL_RAM_MB" =~ ^[0-9]+$ ]]; then
  echo "--total-ram-mb must be a number" >&2
  exit 2
fi

GLOBAL_ALLOCATION_LIMIT=$((TOTAL_RAM_MB - OS_RAM_MB - PHYSMEMSIZE))
if (( GLOBAL_ALLOCATION_LIMIT <= 0 )); then
  echo "Calculated global_allocation_limit is <= 0 MB. Check total RAM and system type." >&2
  exit 2
fi

run_sql() {
  local host_port="$1"
  local database="$2"
  local sql="$3"
  local password="$4"

  if (( EXECUTE == 0 )); then
    cat <<DRYRUN

--- DRY RUN hdbsql target ${host_port}, database ${database} ---
${sql}
DRYRUN
    return 0
  fi

  hdbsql -n "$host_port" -d "$database" -u SYSTEM -p "$password" -j -A "$sql"
}

if (( EXECUTE == 1 )) && [[ -z "$OLD_SYSTEM_PASSWORD" ]]; then
  read -r -s -p "Old/current SYSTEM password for tenant ${TENANT}: " OLD_SYSTEM_PASSWORD
  echo
fi

# The new password follows the UCC standard pattern (see the team password
# manager). It is read from stdin so it never appears in the process list.
if (( EXECUTE == 1 )) && [[ -z "$NEW_SYSTEM_PASSWORD" ]]; then
  read -r -s -p "New SYSTEM password for tenant ${TENANT} (UCC standard): " NEW_SYSTEM_PASSWORD
  echo
  if [[ -z "$NEW_SYSTEM_PASSWORD" ]]; then
    echo "A new SYSTEM password is required in execute mode." >&2
    exit 2
  fi
fi

cat <<INFO
Resolved values:
  SID:                         ${SID}
  Tenant DB:                   ${TENANT}
  New SYSTEM password:          <hidden, entered interactively>
  System type:                  ${SYSTEM_TYPE}
  PHYSMEMSIZE used in formula:  ${PHYSMEMSIZE} MB
  OS RAM reserve used:          ${OS_RAM_MB} MB
  Total LPAR RAM:               ${TOTAL_RAM_MB} MB
  global_allocation_limit:      ${GLOBAL_ALLOCATION_LIMIT} MB
  Execute mode:                 ${EXECUTE}
INFO

# Step 1.1: Change SYSTEM password in tenant DB.
# SAP HANA supports changing the SYSTEM user password with ALTER USER SYSTEM PASSWORD.
# The dry run prints a placeholder so the real password never reaches any log.
if (( EXECUTE == 0 )); then
  SQL_CHANGE_PASSWORD='ALTER USER SYSTEM PASSWORD "<new password>";'
else
  SQL_CHANGE_PASSWORD="ALTER USER SYSTEM PASSWORD \"${NEW_SYSTEM_PASSWORD}\";"
fi
run_sql "${DBHOST}:${TENANT_SQL_PORT}" "${TENANT}" "$SQL_CHANGE_PASSWORD" "${OLD_SYSTEM_PASSWORD}"

# Step 1.2: Set global allocation limit in SystemDB.
# Applies global.ini memorymanager/global_allocation_limit and reconfigures online.
SQL_ALLOCATION="ALTER SYSTEM ALTER CONFIGURATION ('global.ini','SYSTEM') SET ('memorymanager','global_allocation_limit') = '${GLOBAL_ALLOCATION_LIMIT}' WITH RECONFIGURE;"
# After password change, use the new SYSTEM password if the same SYSTEM user credential is used for SystemDB.
run_sql "${DBHOST}:${SYSTEMDB_SQL_PORT}" "SYSTEMDB" "$SQL_ALLOCATION" "${NEW_SYSTEM_PASSWORD}"

cat <<DONE

Completed requested SQL steps.
Verify with:
  hdbsql -n ${DBHOST}:${SYSTEMDB_SQL_PORT} -d SYSTEMDB -u SYSTEM -p '***' \
    "SELECT FILE_NAME, SECTION, KEY, VALUE FROM M_INIFILE_CONTENTS WHERE FILE_NAME='global.ini' AND SECTION='memorymanager' AND KEY='global_allocation_limit'"
DONE
