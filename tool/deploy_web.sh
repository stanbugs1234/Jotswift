#!/bin/sh
# Builds the web app and publishes it to Firebase Hosting:
# https://notely-b1aec.web.app
#
# Usage, from the repo root (after `firebase login`):
#   tool/deploy_web.sh
set -e
cd "$(dirname "$0")/.."
flutter build web --release
firebase deploy --only hosting
