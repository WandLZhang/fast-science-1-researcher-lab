#!/usr/bin/env bash
# blueprints/research-delegation/billing/grant-billing-and-verify.sh
#
# Two operations bundled:
#
#   1. grant-billing  — give roles/billing.user on the institution's master
#                       billing account to (a) each team SA and (b) each PI
#                       Google Group, so projects created under team folders
#                       can be linked to the master billing account.
#
#   2. verify         — sanity-check the delegated provisioning end-to-end:
#                       team folder exists, team SA exists with right roles,
#                       PI group has impersonation rights, org policies
#                       inherited, project liens working.
#
# Required env vars (always):
#   PREFIX                 L0 Stage 0 prefix (e.g. "uni")
#   AUTOMATION_PROJECT     L0 automation project (typically <PREFIX>-prod-iac-core-0)
#
# For grant-billing:
#   BILLING_ACCOUNT_ID     Master billing account ID (e.g. 0X0X0X-0X0X0X-0X0X0X)
#   TEAM_KEYS              Comma-separated list of team_folders keys to grant for
#                          (e.g. "engineering,computational-sciences")
#   PI_GROUPS              Comma-separated list of PI group emails
#                          (e.g. "engineering-pis@example.edu,cs-pis@example.edu")
#
# For verify:
#   TEAMS_FOLDER_ID        Numeric folder ID of the "Teams" folder
#   TEAM_KEY               Single team key to verify (e.g. "engineering")
#   PI_GROUP               PI group email to verify (e.g. "engineering-pis@example.edu")
#   TEST_PROJECT_ID        (optional) project ID created during the demo, used
#                          to spot-check inherited org policies and lien
#
# Usage:
#   ./grant-billing-and-verify.sh grant-billing
#   ./grant-billing-and-verify.sh verify
#
set -euo pipefail

cmd="${1:-}"
case "$cmd" in
  grant-billing|verify) ;;
  *) echo "usage: $0 {grant-billing|verify}" >&2; exit 2 ;;
esac

: "${PREFIX:?must be set}"
: "${AUTOMATION_PROJECT:?must be set}"

#------------------------------------------------------------------------------#
# grant-billing                                                                #
#------------------------------------------------------------------------------#
if [[ "$cmd" == "grant-billing" ]]; then
  : "${BILLING_ACCOUNT_ID:?must be set}"
  : "${TEAM_KEYS:?must be set (comma-separated)}"
  : "${PI_GROUPS:?must be set (comma-separated)}"

  IFS=',' read -ra _team_keys  <<<"$TEAM_KEYS"
  IFS=',' read -ra _pi_groups  <<<"$PI_GROUPS"

  echo "Granting roles/billing.user on billingAccounts/${BILLING_ACCOUNT_ID}"
  echo

  # Each team's service account: enables PF / Console / impersonation paths to
  # link new projects to the master billing account.
  for key in "${_team_keys[@]}"; do
    sa="${PREFIX}-prod-teams-${key}-0@${AUTOMATION_PROJECT}.iam.gserviceaccount.com"
    echo "→ team SA: ${sa}"
    gcloud beta billing accounts add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
      --member="serviceAccount:${sa}" \
      --role="roles/billing.user" \
      --condition=None \
      --quiet
  done

  # Each PI group: enables the Console-first PI flow ("New Project" → pick the
  # master billing account from the dropdown).
  for grp in "${_pi_groups[@]}"; do
    echo "→ PI group: ${grp}"
    gcloud beta billing accounts add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
      --member="group:${grp}" \
      --role="roles/billing.user" \
      --condition=None \
      --quiet
  done

  echo
  echo "Done. To inspect:"
  echo "  gcloud beta billing accounts get-iam-policy ${BILLING_ACCOUNT_ID}"
  exit 0
fi

#------------------------------------------------------------------------------#
# verify                                                                       #
#------------------------------------------------------------------------------#
: "${TEAMS_FOLDER_ID:?must be set}"
: "${TEAM_KEY:?must be set}"
: "${PI_GROUP:?must be set}"

ok=0; fail=0
pass() { echo "  ✓ $1"; ok=$((ok+1)); }
miss() { echo "  ✗ $1"; fail=$((fail+1)); }

team_sa="${PREFIX}-prod-teams-${TEAM_KEY}-0@${AUTOMATION_PROJECT}.iam.gserviceaccount.com"

echo "[1/6] Teams folder exists and contains the team folder"
team_folder_id="$(
  gcloud resource-manager folders list --folder="$TEAMS_FOLDER_ID" \
    --format="value(name)" --filter="displayName~${TEAM_KEY}|displayName:'College'|displayName:'Institute'" \
    | head -1 | sed 's@folders/@@'
)" || true
if [[ -n "$team_folder_id" ]]; then
  pass "team folder under Teams: folders/${team_folder_id}"
else
  miss "no team folder found under folders/${TEAMS_FOLDER_ID} matching key '${TEAM_KEY}'"
fi

echo "[2/6] Team SA exists with FAST-managed roles on the team folder"
if gcloud iam service-accounts describe "$team_sa" --project="$AUTOMATION_PROJECT" >/dev/null 2>&1; then
  pass "team SA exists: ${team_sa}"
  if [[ -n "${team_folder_id:-}" ]]; then
    iam_json="$(gcloud resource-manager folders get-iam-policy "$team_folder_id" --format=json)"
    for role in roles/owner roles/resourcemanager.folderAdmin roles/resourcemanager.projectCreator roles/compute.xpnAdmin; do
      if echo "$iam_json" | grep -q "\"role\": \"${role}\".*serviceAccount:${team_sa}" || \
         echo "$iam_json" | python3 -c "import sys,json; p=json.load(sys.stdin); sys.exit(0 if any(b['role']=='${role}' and 'serviceAccount:${team_sa}' in b.get('members',[]) for b in p.get('bindings',[])) else 1)"; then
        pass "  ${role} bound to team SA on team folder"
      else
        miss "  ${role} NOT bound to team SA on team folder"
      fi
    done
  fi
else
  miss "team SA missing: ${team_sa}"
fi

echo "[3/6] PI group has serviceAccountTokenCreator on team SA (impersonation)"
sa_iam="$(gcloud iam service-accounts get-iam-policy "$team_sa" --project="$AUTOMATION_PROJECT" --format=json 2>/dev/null || echo '{}')"
if echo "$sa_iam" | python3 -c "import sys,json; p=json.load(sys.stdin); sys.exit(0 if any(b['role']=='roles/iam.serviceAccountTokenCreator' and 'group:${PI_GROUP}' in b.get('members',[]) for b in p.get('bindings',[])) else 1)" 2>/dev/null; then
  pass "group:${PI_GROUP} can impersonate team SA"
else
  miss "group:${PI_GROUP} cannot impersonate team SA"
fi

echo "[4/6] PI group has folderViewer + projectCreator on team folder"
if [[ -n "${team_folder_id:-}" ]]; then
  iam_json="$(gcloud resource-manager folders get-iam-policy "$team_folder_id" --format=json)"
  for role in roles/resourcemanager.folderViewer roles/resourcemanager.projectCreator; do
    if echo "$iam_json" | python3 -c "import sys,json; p=json.load(sys.stdin); sys.exit(0 if any(b['role']=='${role}' and 'group:${PI_GROUP}' in b.get('members',[]) for b in p.get('bindings',[])) else 1)" 2>/dev/null; then
      pass "  ${role} bound to PI group"
    else
      miss "  ${role} NOT bound to PI group"
    fi
  done
fi

echo "[5/6] Org policies inherited at the Teams folder level"
expected_policies=(
  iam.managed.disableServiceAccountKeyCreation
  iam.managed.disableServiceAccountKeyUpload
  iam.automaticIamGrantsForDefaultServiceAccounts
  iam.managed.allowedPolicyMembers
  essentialcontacts.managed.allowedContactDomains
  gcp.resourceLocations
  compute.requireOsLogin
  compute.vmExternalIpAccess
  compute.skipDefaultNetworkCreation
  compute.disableSerialPortAccess
  storage.uniformBucketLevelAccess
  gcp.restrictServiceUsage
  vertexai.allowedPartnerModelFeatures
)
applied="$(gcloud org-policies list --folder="$TEAMS_FOLDER_ID" --format='value(name)' 2>/dev/null || true)"
for p in "${expected_policies[@]}"; do
  if echo "$applied" | grep -q "/policies/${p}$"; then
    pass "  ${p}"
  else
    miss "  ${p} not set on Teams folder"
  fi
done

echo "[6/6] Test project (if provided) shows inheritance + lien"
if [[ -n "${TEST_PROJECT_ID:-}" ]]; then
  if gcloud projects describe "$TEST_PROJECT_ID" >/dev/null 2>&1; then
    pass "test project exists: ${TEST_PROJECT_ID}"
    eff="$(gcloud org-policies describe compute.requireOsLogin --project="$TEST_PROJECT_ID" --effective --format='value(spec.rules[0].enforce)' 2>/dev/null || echo '')"
    [[ "$eff" == "True" ]] && pass "  compute.requireOsLogin inherited and enforced" || miss "  compute.requireOsLogin not effective on test project"

    liens="$(gcloud alpha resource-manager liens list --project="$TEST_PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$liens" -ge 1 ]] && pass "  lien attached (count=${liens})" || miss "  no lien on test project — auto-lien CF may not be deployed"

    billing="$(gcloud beta billing projects describe "$TEST_PROJECT_ID" --format='value(billingAccountName)' 2>/dev/null || echo '')"
    [[ -n "$billing" ]] && pass "  linked to billing: ${billing}" || miss "  not linked to a billing account"
  else
    miss "test project not found: ${TEST_PROJECT_ID}"
  fi
else
  echo "  (skipped — set TEST_PROJECT_ID to run end-to-end project checks)"
fi

echo
echo "Verification complete: ${ok} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
