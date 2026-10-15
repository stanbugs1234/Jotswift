# Notely

Handwritten notes, a daily planner, calendar and to-do lists for iOS and Android phones and tablets, with a web app at **https://notely-b1aec.web.app**. Notebooks work like Noteshelf: covers, papers, PDF planners and templates, stickers, text boxes and photos.

See [PLAN.md](PLAN.md) for the product plan and roadmap, and [docs/content.md](docs/content.md) to make notebook styles, covers, papers, stickers and templates.

## Status

| Area | State |
|---|---|
| Accounts | Email, Google and Apple sign-in through Firebase. Deleting an account erases all its data (a Cloud Function). |
| Notebooks | A shelf with categories and groups. Each notebook has a cover, paper, style and size. Pages have pen, highlighter, eraser, undo, zoom and palm rejection, plus stickers, text boxes and photos. |
| Content | A catalog of covers, papers, sticker packs, PDF planners and page templates, published from Firebase ([docs/content.md](docs/content.md)). |
| Planner, Calendar, To-do | Daily planner pages, events with repeats in month, week and day views, task lists, and reminders as local notifications. |
| Store | Templates screen, Notely Pro and packs through RevenueCat. Built and tested, switched on once the accounts in [docs/store-setup.md](docs/store-setup.md) exist. |
| Web | Everything syncs. Handwriting, text boxes and photos are view-only on the web. |

**Testing on an iPad:** see [docs/testing-on-ipad.md](docs/testing-on-ipad.md).

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
cd firebase/functions && npm install && npm test   # Cloud Functions
python3 tool/catalog.py check                      # catalog content
```

## Publishing the web app

```sh
tool/deploy_web.sh     # flutter build web, then firebase deploy --only hosting
```

Golden screenshots are generated on Linux (as in CI). They may differ slightly on macOS.

## Code layout

```
lib/
  app/                 app widget, router, responsive shell (phone / tablet / web)
  core/
    catalog/           catalog listings, downloads and pack cache
    entitlements/      what the user may use; the notebook limit
    purchases/         RevenueCat
    paper/, pdf/       paper styles, PDF rendering
    skins/             notebook styles (manifests, theme builder)
    settings/          settings synced to the account
  features/
    auth/              sign-in
    shelf/, notebooks/ the shelf, notebooks, sections, pages
    canvas/            ink, stickers, text boxes, photos, templates
    planner/, calendar/, tasks/, reminders/
    store/             Templates screen, item pages, Pro paywall
    settings/, skins/
assets/skins/          notebook styles (one folder per style)
catalog/               catalog content, published with tool/catalog.py
firebase/              security rules, their tests, Cloud Functions
```
