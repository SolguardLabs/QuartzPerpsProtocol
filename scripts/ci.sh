#!/usr/bin/env bash
set -euo pipefail

forge fmt --check
forge build --sizes
bash scripts/tests.sh

previous_profile="${FOUNDRY_PROFILE:-}"
export FOUNDRY_PROFILE=ci
bash scripts/tests.sh
export FOUNDRY_PROFILE="$previous_profile"
