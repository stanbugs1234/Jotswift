# Notely

Handwritten notes, a daily planner, calendar and to-do lists for iOS and Android phones and tablets, with a web app for viewing and typing. The look comes from swappable **skins**.

See [PLAN.md](PLAN.md) for the product plan and roadmap, and [docs/skins.md](docs/skins.md) to make a new skin.

## Status

| Phase | State |
|---|---|
| 0. Setup: app shell, sign-in, Firebase | iOS and Android use Firebase sign-in; web waits on its Firebase config |
| 1. Skins | Skin engine, 4 free skins + 1 sample paid skin, skin picker with previews |
| 2–5 | Not started |

The Notebooks, Planner, Calendar and To-do tabs show **sample pages** so skins can be seen everywhere. Real editing comes in later phases.

**Sign-in:** iOS and Android use real Firebase accounts (project `notely-b1aec`). Platforms without a Firebase config (currently the web) fall back to a stand-in sign-in: any email with a 6+ character password works, and nothing is saved between launches.

The chosen skin is saved on the device and in the account (`users/{uid}.activeSkinId`), so it follows the user to other devices.

## Running it

Requires Flutter 3.47 or later.

```sh
flutter pub get
flutter run                 # pick an iOS/Android device or simulator
flutter run -d chrome       # web
```

## Checks

```sh
flutter analyze
flutter test                                  # all tests, including screenshot (golden) tests
flutter test --tags golden --update-goldens   # regenerate screenshots after an intended visual change
```

Firestore security rules (`firebase/firestore.rules`) have their own tests, which run in the Firebase emulator and need Node.js and Java:

```sh
cd firebase/rules-tests && npm install && npm test
```

Golden screenshots are generated on Linux (as in CI). They may differ slightly on macOS.

## Code layout

```
lib/
  app/                 app widget, router, responsive shell (phone / tablet / web)
  core/
    skins/             manifest parser, theme builder, paper painter, providers
    entitlements/      what the user has unlocked (stub until the store is built)
  features/
    auth/              sign-in screen and auth repository
    skins/             skin picker, skin preview, sample pages
    home/              placeholder tabs
    settings/
assets/skins/          skin manifests (one folder per skin)
```
