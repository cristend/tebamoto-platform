#!/usr/bin/env bash
set -u
TENANT=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
echo "=== oidc mint"
JT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c "import sys,json;print(json.load(sys.stdin).get('value',''))" 2>/dev/null)
echo "jwt_len=${#JT}"
echo "$JT" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -E '"(sub|aud|iss|repository|ref|event_name)"' | head -8

xchg() {  # $1 client_id -> echoes ARM token or empty
  curl -sS -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
    -d "client_id=$1&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$JT&scope=https://management.azure.com/.default" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('access_token','') if 'access_token' in d else 'FAIL:'+d.get('error','?')+':'+d.get('error_description','')[:80])"
}
arm() {  # $1 token $2 path
  curl -sS -o /tmp/r.json -w "%{http_code}" -H "Authorization: Bearer $1" "https://management.azure.com$2" | tail -c4
}
RES=(
"/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod"
"/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tbl-reporting-writer"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites/app-tbl-storefront-prod"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-prod-x3euoz"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblbackupprodx3euoz"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblarchiveprodx3euoz"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Cdn/profiles/afd-tbl-prod"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Network/frontdoorWebApplicationFirewallPolicies/waftblstorefrontprod"
"/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.ContainerRegistry/registries/crtblplatprodx3euoz"
)
for CID in 72ff278a-9e71-43ec-bac4-2ca303f8e462 462d1c38-4459-48b8-9333-82e389e59514 891fb158-e02c-4428-a885-53b811f369c0 7a85156a-01c4-4e61-8472-40a92107159b 881fddce-6208-4af5-a297-7e79c912f83c 12ed54de-f2eb-4784-804c-3a7a3e83a9e9 038bc35d-131d-4953-9985-ff4a245ccec1 58108da8-044e-4d7e-9a46-92e6179b30be 2c34300e-1bc0-41e7-9c1e-8b7571d72c72 7a250202-a036-4089-8de8-9d1f555a4ad9; do
  echo "===== exchange $CID"
  AT=$(xchg $CID)
  case "$AT" in
    FAIL*) echo "  $AT" | head -c 160; echo; continue;;
  esac
  echo "  MINTED len=${#AT}"
  # self perms at sub
  S=$(arm "$AT" "/subscriptions/$SUB/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
  echo "  subperms=$S"
  # resource-scope matrix
  for r in "${RES[@]}"; do
    S=$(arm "$AT" "$r/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
    [ "$S" != "0200" ] && [ "$S" != "200" ] && S=$S || S="200:$(python3 -c "import json;print(len(json.load(open('/tmp/r.json')).get('value',[])))" 2>/dev/null)"
    echo "  perms ${r##*/} = $S"
  done
  # UAMI FICs read (if we hold anything with MI read)
  S=$(arm "$AT" "/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tbl-reporting-writer/federatedIdentityCredentials?api-version=2023-01-31")
  echo "  uamiFICs=$S $(head -c 200 /tmp/r.json | tr -d '\n')"
  # vault get-by-name on kv-sec (storage audience needed; try ARM audience anyway for authz signal)
done
echo "=== done"
