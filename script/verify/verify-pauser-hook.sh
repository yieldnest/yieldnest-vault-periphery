#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <deployment-json>"
  exit 1
fi

if [ -z "${ETH_MAINNET_RPC_URL:-}" ]; then
  echo "ETH_MAINNET_RPC_URL is required"
  exit 1
fi

deployment_file="$1"
artifact_file="out/PauserHook.sol/PauserHook.json"

if [ ! -f "$deployment_file" ]; then
  echo "Deployment file not found: $deployment_file"
  exit 1
fi

if [ ! -f "$artifact_file" ]; then
  echo "Contract artifact not found: $artifact_file"
  echo "Run forge build from the repository root, then retry."
  exit 1
fi

pauser_hook="$(jq -r '.pauserHook' "$deployment_file")"
vault="$(jq -r '.vault' "$deployment_file")"
admin="$(jq -r '.admin' "$deployment_file")"
pauser="$(jq -r '.pauser' "$deployment_file")"
unpauser="$(jq -r '.unpauser' "$deployment_file")"

for value_name in pauser_hook vault admin pauser unpauser; do
  value="${!value_name}"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "Missing required deployment field: $value_name"
    exit 1
  fi
done

echo "Checking deployed PauserHook bytecode"
echo "  deployment file: $deployment_file"
echo "  contract:        $pauser_hook"
echo "  vault:           $vault"
echo "  admin:           $admin"
echo "  pauser:          $pauser"
echo "  unpauser:        $unpauser"
echo "  artifact:        $artifact_file"
echo

padded_vault="$(printf '%064s' "${vault#0x}" | tr ' ' '0' | tr '[:upper:]' '[:lower:]')"

local_runtime="$(jq -r --arg value "$padded_vault" '
  .deployedBytecode.object as $bytecode
  | ([.deployedBytecode.immutableReferences[]?[]?] | sort_by(.start)) as $refs
  | reduce $refs[] as $ref (
      $bytecode;
      .[0:(2 + ($ref.start * 2))]
        + $value
        + .[(2 + (($ref.start + $ref.length) * 2)):]
    )
' "$artifact_file" | tr '[:upper:]' '[:lower:]')"

deployed_runtime="$(cast code "$pauser_hook" --rpc-url "$ETH_MAINNET_RPC_URL" | tr '[:upper:]' '[:lower:]')"

if [ "$deployed_runtime" = "0x" ]; then
  echo "No code found at deployed address: $pauser_hook"
  exit 1
fi

echo "  local runtime hash:    $(cast keccak "$local_runtime")"
echo "  deployed runtime hash: $(cast keccak "$deployed_runtime")"
echo

if [ "$local_runtime" != "$deployed_runtime" ]; then
  echo "Bytecode mismatch"
  exit 1
fi

echo "Bytecode matches"
