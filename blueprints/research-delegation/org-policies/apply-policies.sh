#!/usr/bin/env bash
# blueprints/research-delegation/org-policies/apply-policies.sh
#
# Apply (or dry-run) the org policies in this directory at the Teams folder so
# every department subfolder + project inherits them.
#
# Required env vars:
#   TEAMS_FOLDER_ID    Numeric folder ID of the "Teams" folder created by
#                      Stage 1 with fast_features.teams = true. Find it with:
#                        gcloud resource-manager folders list \
#                          --folder=$STELLAR_ENGINE_FOLDER_ID --format='value(name,displayName)'
#                      and pick the one named "Teams".
#   CUSTOMER_ID        Workspace / Cloud Identity customer ID. Find with:
#                        gcloud organizations list --format='value(directoryCustomerId)'
#   UNIVERSITY_DOMAIN  Your primary domain (e.g. example.edu). No leading "@".
#
# Optional flags:
#   --dry-run   Apply with dryRunSpec instead of spec, so violations log to
#               Cloud Audit Logs without blocking. Recommended for first apply.
#   --enforce   Apply with spec (default). Promotes from dry-run to enforced.
#
# Usage:
#   export TEAMS_FOLDER_ID=123456789012
#   export CUSTOMER_ID=C01abcdef
#   export UNIVERSITY_DOMAIN=example.edu
#   ./apply-policies.sh --dry-run     # first
#   # ... wait, check Policy Analyzer for violations on existing projects ...
#   ./apply-policies.sh --enforce     # promote
#
set -euo pipefail

MODE="enforce"
case "${1:-}" in
  --dry-run) MODE="dryrun" ;;
  --enforce|"") MODE="enforce" ;;
  *) echo "unknown flag: $1 (use --dry-run or --enforce)" >&2; exit 2 ;;
esac

: "${TEAMS_FOLDER_ID:?must be set}"
: "${CUSTOMER_ID:?must be set}"
: "${UNIVERSITY_DOMAIN:?must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

shopt -s nullglob
yamls=("$SCRIPT_DIR"/[0-9]*.yaml)
if [[ ${#yamls[@]} -eq 0 ]]; then
  echo "no policy YAMLs found in $SCRIPT_DIR" >&2
  exit 1
fi

echo "Applying ${#yamls[@]} org policies to folders/${TEAMS_FOLDER_ID} in ${MODE} mode"
echo

for src in "${yamls[@]}"; do
  base="$(basename "$src")"
  out="$TMPDIR/$base"

  # Substitute placeholders: ${TEAMS_FOLDER_ID}, ${CUSTOMER_ID}, ${UNIVERSITY_DOMAIN}
  TEAMS_FOLDER_ID="$TEAMS_FOLDER_ID" \
  CUSTOMER_ID="$CUSTOMER_ID" \
  UNIVERSITY_DOMAIN="$UNIVERSITY_DOMAIN" \
  envsubst '${TEAMS_FOLDER_ID} ${CUSTOMER_ID} ${UNIVERSITY_DOMAIN}' < "$src" > "$out"

  # In dry-run mode, swap the top-level `spec:` key for `dryRunSpec:`.
  # Org Policy v2 supports both simultaneously, but for a clean first-pass we
  # only set dryRunSpec; the `--enforce` pass replaces it with spec.
  if [[ "$MODE" == "dryrun" ]]; then
    sed -i 's/^spec:/dryRunSpec:/' "$out"
  fi

  echo "→ $base"
  gcloud org-policies set-policy "$out"
  echo
done

echo "Done. To inspect what's been applied:"
echo "  gcloud org-policies list --folder=${TEAMS_FOLDER_ID}"
