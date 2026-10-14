# Notely

Handwritten notes, a daily planner, calendar and to-do lists for iOS and Android phones and tablets, with a web app for viewing and typing. The look comes from swappable **skins**.

See [PLAN.md](PLAN.md) for the product plan and roadmap, and [docs/skins.md](docs/skins.md) to make a new skin.

## Status

| Phase | State |
|---|---|
| 0. Setup: app shell, sign-in, Firebase | iOS, Android and web use Firebase sign-in |
| 1. Skins | Skin engine, 4 free skins + 1 sample paid skin, skin picker with previews |
| 2. Notebooks and handwriting | Notebooks, sections, pages; ink canvas with pen, highlighter, eraser, undo/redo, zoom, palm rejection. Text boxes and images next |
| 3–5 | Not started |

The Planner, Calendar and To-do tabs still show **sample pages**; they're built in Phase 3. On the web, handwriting is view-only.

**Sign-in:** iOS, Android and the web use real Firebase accounts (project `notely-b1aec`). A platform without a Firebase config would fall back to a stand-in sign-in (any email, 6+ character password, nothing saved).

**Testing on an iPad:** see [docs/testing-on-ipad.md](docs/testing-on-ipad.md).

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
    notebooks/         notebooks, sections, pages (Firestore + in-memory)
    canvas/            ink: strokes, rendering, tools, undo/redo
    skins/             skin picker, skin preview, sample pages
    home/              placeholder tabs
    settings/
assets/skins/          skin manifests (one folder per skin)
```
