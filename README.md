# Motley

Handwritten notes, a daily planner, calendar and to-do lists for iOS and Android phones and tablets, with a web app for viewing and typing. The look comes from swappable **skins**.

See [PLAN.md](PLAN.md) for the product plan and roadmap, and [docs/skins.md](docs/skins.md) to make a new skin.

## Status

| Phase | State |
|---|---|
| 0. Setup: app shell, sign-in screens | Done, with a stand-in sign-in until Firebase is connected |
| 1. Skins | Skin engine, 4 free skins + 1 sample paid skin, skin picker with previews |
| 2–5 | Not started |

The Notebooks, Planner, Calendar and To-do tabs show **sample pages** so skins can be seen everywhere. Real editing comes in later phases.

**Sign-in is a stand-in for now.** Any email with a 6+ character password works, as do the Apple and Google buttons. Nothing is saved between launches. Real accounts arrive when the Firebase project is connected.

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
