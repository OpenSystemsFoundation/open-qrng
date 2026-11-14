#!/bin/bash
# Seed a scratch org with demo QuantumFair data (mocked IBM results run through
# the real processing pipeline). See scripts/apex/seed-demo-data.apex.
# Usage: scripts/seed-demo-data.sh [target-org-alias]
set -euo pipefail
ORG="${1:-${SF_SCRATCH_ALIAS:-qrng-dev}}"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Step 0: the seeder writes internal Quantum_Job__c fields that no shipped
# permission set grants (the app writes them in system mode). Grant them to the
# running user through a demo-only permission set that exists only in this org.
FIELDS=""
for f in "$DIR"/../force-app/main/default/objects/Quantum_Job__c/fields/*.field-meta.xml; do
    grep -q "<required>true</required>\|<formula>\|<type>MasterDetail</type>" "$f" && continue
    name="$(basename "$f" .field-meta.xml)"
    FIELDS="$FIELDS'Quantum_Job__c.$name',"
done
cat > "$TMP/perm.apex" <<APEX
List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'QF_Demo_Seeder'];
if (ps.isEmpty()) {
    PermissionSet p = new PermissionSet(Name = 'QF_Demo_Seeder', Label = 'QuantumFair Demo Seeder (scratch only)');
    insert p;
    List<FieldPermissions> fps = new List<FieldPermissions>();
    for (String f : new List<String>{ ${FIELDS%,} }) {
        fps.add(new FieldPermissions(ParentId = p.Id, SobjectType = 'Quantum_Job__c', Field = f, PermissionsRead = true, PermissionsEdit = true));
    }
    Database.insert(fps, false);
    insert new PermissionSetAssignment(PermissionSetId = p.Id, AssigneeId = UserInfo.getUserId());
}
APEX
echo "── Granting seeder field access"
sf apex run --target-org "$ORG" --file "$TMP/perm.apex" | grep -E "Error|error|Executed" || true

for i in 0 1 2 3 4; do
    sed "s/^Integer SCENARIO = 0;/Integer SCENARIO = $i;/" "$DIR/apex/seed-demo-data.apex" > "$TMP/seed.apex"
    echo "── Scenario $i"
    sf apex run --target-org "$ORG" --file "$TMP/seed.apex" | grep -E "USER_DEBUG|Error|error|Compiled|Executed" || true
done
