#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# blueprints/research-delegation/org-policies/apply-policies.sh
#
# Apply (or dry-run) the org policies in this directory on each department
# folder, so the department's Development and Production folders and every
# project in them inherit the baseline.
#
# Required env vars:
#   DEPARTMENT_FOLDER_IDS  Comma-separated department folder IDs (numeric or
#                          folders/NNN). 1-resman lists them:
#                            cd fast/stages-aw/1-resman
#                            terraform output -json departments | python3 -c \
#                              'import json,sys; print(",".join(v["folder"] for v in json.load(sys.stdin).values()))'
#   ORG_ID                 Numeric organization ID. Find it with:
#                            gcloud organizations list
#   UNIVERSITY_DOMAIN      Your primary domain (e.g. example.edu). No leading "@".
#
# Optional flags:
#   --dry-run   Write dryRunSpec instead of spec, so violations log to
#               Cloud Audit Logs without blocking. Recommended for first apply.
#   --enforce   Write spec (default). Promotes from dry-run to enforced.
#
# Each mode updates only its own field (--update-mask), so a later --dry-run
# never clears an enforced spec.
#
# Usage:
#   export DEPARTMENT_FOLDER_IDS=NNNNNNNNNNNN,NNNNNNNNNNNN
#   export ORG_ID=NNNNNNNNNNNN
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

: "${DEPARTMENT_FOLDER_IDS:?must be set (comma-separated)}"
: "${ORG_ID:?must be set}"
: "${UNIVERSITY_DOMAIN:?must be set}"

folders=()
IFS=',' read -ra _raw_folders <<<"$DEPARTMENT_FOLDER_IDS"
for f in "${_raw_folders[@]}"; do
  f="${f// /}"
  f="${f#folders/}"
  [[ -n "$f" ]] && folders+=("$f")
done
if [[ ${#folders[@]} -eq 0 ]]; then
  echo "DEPARTMENT_FOLDER_IDS has no folder IDs" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

shopt -s nullglob
yamls=("$SCRIPT_DIR"/[0-9]*.yaml)
if [[ ${#yamls[@]} -eq 0 ]]; then
  echo "no policy YAMLs found in $SCRIPT_DIR" >&2
  exit 1
fi

if [[ "$MODE" == "dryrun" ]]; then
  mask="dryRunSpec"
else
  mask="spec"
fi

for folder in "${folders[@]}"; do
  echo "Applying ${#yamls[@]} org policies to folders/${folder} in ${MODE} mode"
  echo

  for src in "${yamls[@]}"; do
    base="$(basename "$src")"
    out="$TMPDIR/${folder}-${base}"

    # Substitute placeholders: ${DEPARTMENT_FOLDER_ID}, ${ORG_ID}, ${UNIVERSITY_DOMAIN}
    DEPARTMENT_FOLDER_ID="$folder" \
    ORG_ID="$ORG_ID" \
    UNIVERSITY_DOMAIN="$UNIVERSITY_DOMAIN" \
    envsubst '${DEPARTMENT_FOLDER_ID} ${ORG_ID} ${UNIVERSITY_DOMAIN}' < "$src" > "$out"

    # In dry-run mode, swap the top-level `spec:` key for `dryRunSpec:`.
    if [[ "$MODE" == "dryrun" ]]; then
      sed -i 's/^spec:/dryRunSpec:/' "$out"
    fi

    echo "→ $base"
    cat "$out"
    gcloud org-policies set-policy "$out" --update-mask="$mask"
    echo
  done
done

echo "Done. To inspect what's been applied:"
for folder in "${folders[@]}"; do
  echo "  gcloud org-policies list --folder=${folder}"
done
