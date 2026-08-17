#!/usr/bin/env bash
# Automates the profile-parameter portion of post-install step 1.3.5.
# It edits OS profile files directly, creates timestamped backups, validates with sappfpar if available,
# and can optionally stop the AS afterward.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 --sid XXX --client XXX --system-type exclusive|shared --pas-nr XX --instance-profile /path/to/profile [--profile-dir DIR] [--execute] [--stop-as]

Examples:
  Dry run:
    $0 --sid XXX --client XXX --system-type exclusive --pas-nr XX \
       --instance-profile /usr/sap/XXX/SYS/profile/XXX_D00_XXXXX

  Execute and stop AS afterward:
    $0 --sid XXX --client XXX --system-type exclusive --pas-nr XX \
       --instance-profile /usr/sap/XXX/SYS/profile/XXX_D00_XXXXX --execute --stop-as
USAGE
}

SID=""
CLIENT=""
SYSTEM_TYPE=""
PAS_NR=""
PROFILE_DIR=""
INSTANCE_PROFILE=""
EXECUTE=0
STOP_AS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sid) SID="${2^^}"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
    --system-type) SYSTEM_TYPE="$2"; shift 2 ;;
    --pas-nr) PAS_NR="$2"; shift 2 ;;
    --profile-dir) PROFILE_DIR="$2"; shift 2 ;;
    --instance-profile) INSTANCE_PROFILE="$2"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    --stop-as) STOP_AS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

for required in SID CLIENT SYSTEM_TYPE PAS_NR INSTANCE_PROFILE; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument: $required" >&2
    usage
    exit 2
  fi
done

case "$SYSTEM_TYPE" in
  exclusive)
    DIA=60; BTC=25; VB=1; VB2=1; SPO=1; SHMOBJ=17555; ICFMAX=250; PHYSMEM=50000 ;;
  shared)
    DIA=80; BTC=40; VB=2; VB2=2; SPO=2; SHMOBJ=24576; ICFMAX=1000; PHYSMEM=70000 ;;
  *) echo "--system-type must be exclusive or shared" >&2; exit 2 ;;
esac

if [[ -z "$PROFILE_DIR" ]]; then
  PROFILE_DIR="/usr/sap/${SID}/SYS/profile"
fi
DEFAULT_PROFILE="${PROFILE_DIR}/DEFAULT.PFL"

if (( EXECUTE == 1 )); then
  [[ -f "$DEFAULT_PROFILE" ]] || { echo "Missing default profile: $DEFAULT_PROFILE" >&2; exit 1; }
  [[ -f "$INSTANCE_PROFILE" ]] || { echo "Missing instance profile: $INSTANCE_PROFILE" >&2; exit 1; }
fi

upsert_param() {
  local file="$1"
  local key="$2"
  local value="$3"

  if (( EXECUTE == 0 )); then
    printf 'Would set %-45s = %s in %s\n' "$key" "$value" "$file"
    return 0
  fi

  if grep -Eq "^[[:space:]]*${key//\//\/}[[:space:]]*=" "$file"; then
    sed -i "s|^[[:space:]]*${key//\//\/}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    printf '\n%s = %s\n' "$key" "$value" >> "$file"
  fi
}

backup_file() {
  local file="$1"
  if (( EXECUTE == 1 )); then
    cp -p "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
  fi
}

cat <<INFO
Resolved values:
  SID:              ${SID}
  Client:           ${CLIENT}
  System type:      ${SYSTEM_TYPE}
  Default profile:  ${DEFAULT_PROFILE}
  Instance profile: ${INSTANCE_PROFILE}
  PAS instance no.: ${PAS_NR}
  Execute mode:     ${EXECUTE}
  Stop AS:          ${STOP_AS}
INFO

backup_file "$DEFAULT_PROFILE"
backup_file "$INSTANCE_PROFILE"

# DEFAULT profile parameters from the guide.
upsert_param "$DEFAULT_PROFILE" "login/min_password_lng" "8"
upsert_param "$DEFAULT_PROFILE" "login/min_password_digits" "0"
upsert_param "$DEFAULT_PROFILE" "login/min_password_letters" "0"
upsert_param "$DEFAULT_PROFILE" "login/min_password_lowercase" "0"
upsert_param "$DEFAULT_PROFILE" "login/min_password_uppercase" "0"
upsert_param "$DEFAULT_PROFILE" "login/min_password_diff" "1"
upsert_param "$DEFAULT_PROFILE" "login/password_history_size" "1"
upsert_param "$DEFAULT_PROFILE" "login/ticket_only_by_https" "0"

# Instance profile parameters from the guide.
upsert_param "$INSTANCE_PROFILE" "login/no_automatic_user_sapstar" "0"
upsert_param "$INSTANCE_PROFILE" "sapgui/user_scripting" "TRUE"
upsert_param "$INSTANCE_PROFILE" "icm/server_port_0" 'PROT=HTTP,PORT=80$$,TIMEOUT=600,PROCTIMEOUT=600'
upsert_param "$INSTANCE_PROFILE" "icm/server_port_1" 'PROT=SMTP,PORT=25$$,TIMEOUT=120,PROCTIMEOUT=120'
upsert_param "$INSTANCE_PROFILE" "icm/server_port_2" 'PROT=HTTPS,PORT=81$$,TIMEOUT=600,PROCTIMEOUT=600'
upsert_param "$INSTANCE_PROFILE" "icm/HTTP/logging_0" 'PREFIX=/,LOGFILE=icmhttph.log,FILTER=SAPSMD,LOGFORMAT=SAPSMD2,MAXSIZEKB=10240,FILEWRAP=on,SWITCHTF=month'
upsert_param "$INSTANCE_PROFILE" "rdisp/tm_max_no" "5000"
upsert_param "$INSTANCE_PROFILE" "login/system_client" "${CLIENT}"
upsert_param "$INSTANCE_PROFILE" "rdisp/wp_no_dia" "${DIA}"
upsert_param "$INSTANCE_PROFILE" "rdisp/wp_no_btc" "${BTC}"
upsert_param "$INSTANCE_PROFILE" "rdisp/wp_no_vb" "${VB}"
upsert_param "$INSTANCE_PROFILE" "rdisp/wp_no_vb2" "${VB2}"
upsert_param "$INSTANCE_PROFILE" "rdisp/wp_no_spo" "${SPO}"
upsert_param "$INSTANCE_PROFILE" "abap/shared_objects_size_MB" "${SHMOBJ}"
upsert_param "$INSTANCE_PROFILE" "enque/table_size" "524288"
upsert_param "$INSTANCE_PROFILE" "em/global_area_MB" "3072"
upsert_param "$INSTANCE_PROFILE" "ztta/roll_extension_nondia" "4000000000"
upsert_param "$INSTANCE_PROFILE" "abap/heap_area_total" '$(max($(PHYS_MEMSIZE)* 1024 * 1024 * 0.1 , 4000000000 ))'
upsert_param "$INSTANCE_PROFILE" "rsdb/cua/buffersize" "50000"
upsert_param "$INSTANCE_PROFILE" "zcsa/presentation_buffer_area" "25000000"
upsert_param "$INSTANCE_PROFILE" "icm/HTTP/server_cache_0/max_entries" "60000"
upsert_param "$INSTANCE_PROFILE" "icm/keep_alive_timeout" "300"
upsert_param "$INSTANCE_PROFILE" "icm/conn_timeout" "50000"
upsert_param "$INSTANCE_PROFILE" "icm/HTTP/max_request_size_KB" "163840"
upsert_param "$INSTANCE_PROFILE" "rdisp/keepalive_timeout" "120"
upsert_param "$INSTANCE_PROFILE" "rdisp/keepalive" "180"
upsert_param "$INSTANCE_PROFILE" "rdisp/PG_SHM" "131072"
upsert_param "$INSTANCE_PROFILE" "rdisp/gui_auto_logout" "7200"
upsert_param "$INSTANCE_PROFILE" "icf/max_handle_key" "${ICFMAX}"
upsert_param "$INSTANCE_PROFILE" "PHYS_MEMSIZE" "${PHYSMEM}"

if (( EXECUTE == 1 )); then
  echo "\nProfile changes written. Backups are next to the profiles."
  if command -v sappfpar >/dev/null 2>&1; then
    echo "\nRunning sappfpar checks..."
    sappfpar check pf="$DEFAULT_PROFILE" || true
    sappfpar check pf="$INSTANCE_PROFILE" || true
  else
    echo "sappfpar not found in PATH; skipping profile syntax check."
  fi
  if (( STOP_AS == 1 )); then
    echo "\nStopping AS instance ${PAS_NR}..."
    sapcontrol -nr "$PAS_NR" -function StopSystem
  fi
else
  echo "\nDry run only. Add --execute to write files."
fi
