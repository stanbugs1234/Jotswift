#!/usr/bin/env bash
#
# Runs a debug build with RevenueCat's Test Store: the paywall, purchases,
# Customer Center and Pro all work, with no real payments and no App Store
# products needed.
#
# Requires RevenueCat's Test Store key (test_…) in
# ~/.appstoreconnect/revenuecat_test_key (never committed).
#
# Usage, from the repo root:
#   tool/run_test_store.sh              # the connected device or simulator
#   tool/run_test_store.sh -d <device>  # any `flutter run` options
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

KEY_FILE="$HOME/.appstoreconnect/revenuecat_test_key"
if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing RevenueCat Test Store key at $KEY_FILE" >&2
  exit 1
fi
key=$(tr -d '[:space:]' < "$KEY_FILE")

flutter run --debug \
  --dart-define=REVENUECAT_APPLE_KEY="$key" \
  --dart-define=REVENUECAT_GOOGLE_KEY="$key" \
  "$@"
