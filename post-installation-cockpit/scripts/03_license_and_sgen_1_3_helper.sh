#!/usr/bin/env bash
# Helper for post-install step 1.3.1 / 1.3.2.
# Fully automatable: show hardware key and install an already downloaded SAP license file.
# Not automatable here: generating/downloading the license key in SAP for Me.
# SGEN setup still requires choosing the generation set in transaction SGEN, but this script documents
# the safer OS-side checks before and after scheduling.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 --sid XXX --pas-nr XX --instance-profile /path/to/profile [--license-file /path/license.txt] [--execute]

Examples:
  Show hardware key, dry run license install:
    $0 --sid XXX --pas-nr XX --instance-profile /usr/sap/XXX/SYS/profile/XXX_D00_XXXXX --license-file /tmp/XXX_license.txt

  Execute license install:
    $0 --sid XXX --pas-nr XX --instance-profile /usr/sap/XXX/SYS/profile/XXX_D00_XXXXX --license-file /tmp/XXX_license.txt --execute
USAGE
}

SID=""
PAS_NR=""
INSTANCE_PROFILE=""
LICENSE_FILE=""
EXECUTE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sid) SID="${2^^}"; shift 2 ;;
    --pas-nr) PAS_NR="$2"; shift 2 ;;
    --instance-profile) INSTANCE_PROFILE="$2"; shift 2 ;;
    --license-file) LICENSE_FILE="$2"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

for required in SID PAS_NR INSTANCE_PROFILE; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument: $required" >&2
    usage
    exit 2
  fi
done

cat <<INFO
Resolved values:
  SID:              ${SID}
  PAS instance no.: ${PAS_NR}
  Instance profile: ${INSTANCE_PROFILE}
  License file:     ${LICENSE_FILE:-<none>}
  Execute mode:     ${EXECUTE}
INFO

if (( EXECUTE == 1 )); then
  [[ -f "$INSTANCE_PROFILE" ]] || { echo "Missing instance profile: $INSTANCE_PROFILE" >&2; exit 1; }
fi

echo "\n1) Hardware key for SAP for Me / SLICENSE:"
if (( EXECUTE == 1 )); then
  saplikey pf="$INSTANCE_PROFILE" -get || saplikey pf="$INSTANCE_PROFILE" -number
else
  echo "Would run: saplikey pf=\"$INSTANCE_PROFILE\" -get"
fi

cat <<SGEN

2) SGEN automation boundary:
   The guide requires transaction SGEN in client 000, selecting all available components,
   then starting the generated background job. This is screen-flow dependent and should be
   initiated in SAP GUI unless your team has a tested SAP GUI scripting/eCATT recording.

   Recommended checks after starting SGEN:
     - Use SM37 to monitor the SGEN background job.
     - Ensure enough DB space before full generation.
SGEN

if [[ -n "$LICENSE_FILE" ]]; then
  echo "\n3) License installation:"
  if (( EXECUTE == 1 )); then
    [[ -f "$LICENSE_FILE" ]] || { echo "Missing license file: $LICENSE_FILE" >&2; exit 1; }
    saplikey pf="$INSTANCE_PROFILE" -install "$LICENSE_FILE"
    echo "\nInstalled license file. Current license list:"
    saplikey pf="$INSTANCE_PROFILE" -show || true
  else
    echo "Would run: saplikey pf=\"$INSTANCE_PROFILE\" -install \"$LICENSE_FILE\""
    echo "Would run: saplikey pf=\"$INSTANCE_PROFILE\" -show"
  fi
else
  echo "\n3) No --license-file given; skipping license installation."
fi
