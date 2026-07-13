#!/usr/bin/env bash
set -euo pipefail

forge fmt --check
forge build --sizes
forge test

previous_profile="${FOUNDRY_PROFILE:-}"
export FOUNDRY_PROFILE=ci
forge test
export FOUNDRY_PROFILE="$previous_profile"
