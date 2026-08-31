#!/usr/bin/env bash
# Deploys the Agent Management feature (Agents tab + Agent_Payout__c) to an org.
#
# Why two stages: the Apex tests query Commission_Line__c.Payout__c under
# WITH USER_MODE, and a newly deployed field carries no FLS in this org -- not
# even for a System Administrator. The FLS comes from the Agent_Management
# permission set, which itself references AgentPayoutController in
# <classAccesses> and the Agent_Management tab in <tabSettings>. That is a
# cycle: the tests need the permission set, the permission set needs the Apex.
#
# Stage 1 breaks it by deploying the declarative layer plus a permission set
# with those two dependent blocks temporarily removed. No Apex is involved, so
# production accepts NoTestRun. The permission set is then assigned to the
# deploying user, which grants the FLS the tests need. Stage 2 deploys
# everything, including the complete permission set, with the tests running.
#
# Nothing is visible to any user until the permission set is assigned, so there
# is no window in which production is half-built for someone.
#
# Usage:  scripts/deploy_agent_management.sh "K2 Insurance PROD" liam.jeong@k2ins.com

set -euo pipefail

ORG="${1:?usage: $0 <org-alias> <username-to-assign>}"
USERNAME="${2:?usage: $0 <org-alias> <username-to-assign>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PERMSET=force-app/main/default/permissionsets/Agent_Management.permissionset-meta.xml
BACKUP="$(mktemp)"
TESTS=(--tests AgentPayoutCalculatorTest --tests AgentPayoutServiceTest --tests AgentPayoutControllerTest)

restore_permset() {
    if [ -s "$BACKUP" ]; then
        cp "$BACKUP" "$PERMSET"
        rm -f "$BACKUP"
    fi
}
trap restore_permset EXIT

echo "==> Stage 1/3: declarative metadata (object, fields, rules, labels, permission set)"
cp "$PERMSET" "$BACKUP"
python3 - "$PERMSET" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = re.sub(r'    <classAccesses>.*?</classAccesses>\n', '', s, flags=re.S)
s = re.sub(r'    <tabSettings>\s*<tab>Agent_Management</tab>.*?</tabSettings>\n', '', s, flags=re.S)
p.write_text(s)
PY

# Production refuses NoTestRun outright, even for a package with no Apex in it.
# Stage 1 carries no Apex, so nothing here needs coverage; naming one small
# existing class satisfies the API without running the whole org's suite.
sf project deploy start -o "$ORG" \
    --manifest manifest/agent-management-stage1.xml \
    --test-level RunSpecifiedTests --tests ExceptionLoggerTest --wait 45

restore_permset

echo "==> Stage 2/3: grant the deploying user the field-level security the tests need"
sf org assign permset -o "$ORG" -n Agent_Management -b "$USERNAME"

echo "==> Stage 3/3: validating the full package (Apex, LWC, tab, app nav)"
sf project deploy start -o "$ORG" \
    --manifest manifest/agent-management-package.xml \
    --dry-run --test-level RunSpecifiedTests "${TESTS[@]}" --wait 60 --verbose

echo
echo "Validation passed. Deploy for real with:"
echo "  sf project deploy start -o \"$ORG\" \\"
echo "      --manifest manifest/agent-management-package.xml \\"
echo "      --test-level RunSpecifiedTests ${TESTS[*]} --wait 60"
echo
echo "Then assign the permission set to Kay to switch the feature on:"
echo "  sf org assign permset -o \"$ORG\" -n Agent_Management -b kaykim.mfg@gmail.com.production"
echo
echo "Verify afterwards (sobject describe is cached and will lie -- use the Tooling API):"
echo "  sf data query -t -o \"$ORG\" -q \"SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Agent_Payout__c'\""
echo "  sf data query -o \"$ORG\" -q \"SELECT Field FROM FieldPermissions WHERE Parent.Name='Agent_Management'\""
