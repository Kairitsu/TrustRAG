#!/usr/bin/env bash
# Validates TrustRAG Windows cleanup path registry (runs on any OS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PATHS_PS1="$ROOT/scripts/windows/trustrag_paths.ps1"
PATHS_DART="$ROOT/apps/client/lib/core/services/windows_local_data_paths.dart"

required=(
  'XimilalaXiang'
  'com.example'
  'Kairitsu'
  'trustrag'
  'TrustRAG'
)

fail=0
for needle in "${required[@]}"; do
  if ! grep -q "$needle" "$PATHS_PS1"; then
    echo "FAIL: missing in trustrag_paths.ps1: $needle"
    fail=1
  fi
  if ! grep -q "$needle" "$PATHS_DART"; then
    echo "FAIL: missing in windows_local_data_paths.dart: $needle"
    fail=1
  fi
done

if [[ $fail -eq 0 ]]; then
  echo 'PASS: cleanup path registry contains all required entries.'
  exit 0
fi
exit 1