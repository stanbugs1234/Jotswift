#!/usr/bin/env bash
#
# Sends a new build of the iOS app to TestFlight (App Store Connect app
# "Jotswift", bundle id com.notelyapp.notely).
#
# Bumps the build number, runs analyze and the tests, builds a signed
# release archive and uploads it with the App Store Connect API. Run it by
# hand when a build is worth testing; it isn't a CI job.
#
# Requires:
#   - The App Store Connect API key at
#     ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 (never
#     committed).
#   - The Apple Distribution certificate for team UGSW9JFYRB in the
#     keychain. Xcode's automatic signing makes the App Store profile.
#
# Usage, from the repo root with a clean working tree:
#   tool/release_testflight.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ASC_KEY_ID="U2RV8QCQA4"
ASC_ISSUER_ID="b2ed400c-a195-46db-93ac-d188d9bba33a"
ASC_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

if [[ ! -f "$ASC_KEY" ]]; then
  echo "Missing App Store Connect API key at $ASC_KEY" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree isn't clean. Commit or stash your changes first." >&2
  exit 1
fi

current_version=$(grep '^version:' pubspec.yaml | sed 's/version: //')
build_name="${current_version%+*}"
build_number="${current_version##*+}"
next_version="${build_name}+$((build_number + 1))"

echo "==> flutter analyze"
flutter analyze

# Screenshot tests only match on Linux; CI checks them.
echo "==> flutter test"
flutter test --exclude-tags golden

echo "==> Bumping version: ${current_version} -> ${next_version}"
sed -i '' "s/^version: ${current_version}\$/version: ${next_version}/" pubspec.yaml

echo "==> flutter build ipa"
# The API key lets Xcode create or refresh the App Store profile itself.
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist \
  ${REVENUECAT_APPLE_KEY:+--dart-define=REVENUECAT_APPLE_KEY=$REVENUECAT_APPLE_KEY}

ipa_path=$(find build/ios/ipa -maxdepth 1 -name '*.ipa' | head -n1)
if [[ -z "$ipa_path" ]]; then
  echo "No .ipa found in build/ios/ipa after build." >&2
  exit 1
fi

echo "==> Uploading ${ipa_path} to TestFlight"
xcrun altool --upload-app \
  -f "$ipa_path" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo "==> Committing version bump"
git add pubspec.yaml
git commit -m "Build ${next_version} for TestFlight"
git push

echo "==> Done. ${next_version} is processing in App Store Connect."
