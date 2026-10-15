# Notely — Product & Technical Plan

A handwriting-first notebook app, in the spirit of OneNote. You write with a stylus (or finger) on an iOS or Android tablet or phone, and the notes show up on the web almost instantly. It also includes a calendar, a daily planner and to-do lists. The look comes from swappable **skins**: a few free ones ship with the app, and the rest are sold, along with premium features.

---

## 1. Goals and non-goals

**Goals for v1**
- Write on iOS and Android **tablets and phones** with low latency and pressure-sensitive ink (Apple Pencil, S Pen, or finger on phones).
- The same notes appear on the web app in near real time. The web is for **viewing and typing**: ink shows read-only, while typed text, tasks and events can be edited.
- An account is required (sign in with Apple, Google or email). That keeps sync and purchases simple.
- Notebooks → Sections → Pages, like OneNote.
- Page types: **Freeform note**, **Daily planner**, **To-do list**, **Calendar** (month/week/day views).
- Works offline on the tablet and syncs when it reconnects.
- 3–4 free skins, purchasable skin packs, and a "Pro" tier that unlocks extra features.

**Non-goals for v1** (later phases)
- Real-time multi-user collaboration on one page
- Native desktop apps (Flutter can add these later)
- Handwriting-to-text search (Phase 5)
- Two-way Google/Outlook calendar sync (Phase 5)

---

## 2. Tech stack (recommended)

| Concern | Choice | Why |
|---|---|---|
| App framework | **Flutter** (one codebase for iOS, iPadOS, Android and Web) | Phone, tablet and web come from the same code |
| State management | **Riverpod** (+ `riverpod_generator`) | Testable and works well with async streams |
| Routing | **go_router** | Deep links and clean web URLs (`/notebook/:id/page/:id`) |
| Models | **freezed** + **json_serializable** | Immutable models with generated serialization |
| Backend | **Firebase**: Auth, Cloud Firestore, Cloud Storage, Cloud Functions | Real-time listeners plus **offline persistence on mobile and web** with no custom sync server |
| Ink rendering | `CustomPainter` + **perfect_freehand** | Smooth, pressure-aware strokes |
| Payments | **RevenueCat** (Apple IAP, Google Play Billing, and Stripe through RevenueCat Web Billing) | One source of truth for entitlements across all three platforms |
| Analytics / crashes | Firebase Analytics + Crashlytics (Sentry for web) | |
| CI/CD | GitHub Actions + Codemagic (or Fastlane) for store builds; Firebase Hosting for web | |

> **Why not Supabase?** It's a valid alternative (Postgres, Row Level Security). Firestore wins here because its offline cache and real-time sync work out of the box on Flutter **web and mobile**. Getting the same offline-first behavior on Supabase would mean building our own local DB and sync layer (for example Drift + PowerSync).

---

## 3. Architecture

```
lib/
  main.dart
  app/                    # MaterialApp, router, bootstrapping, DI
  core/
    skins/                # Skin engine (see §6)
    entitlements/         # Purchases + feature gates (see §7)
    sync/                 # Firestore wrappers, offline status, conflict helpers
    utils/
  features/
    auth/
    notebooks/            # notebooks, sections, page list
    canvas/               # ink engine, tools, page rendering
    planner/              # daily planner page type
    todo/                 # to-do lists
    calendar/             # events, month/week/day views
    store/                # skin & feature shop UI
    settings/
  shared/widgets/
```

Each feature folder has three layers:
- `data/`: repositories (Firestore) and DTOs
- `domain/`: freezed models and business logic
- `presentation/`: widgets and Riverpod providers

UI code never calls Firestore directly. It always goes through a repository, so the backend can be swapped later and tests can use fakes.

---

## 4. Data model (Firestore)

```
users/{uid}
  activeSkinId, appearance, updatedAt               # settings, synced across devices
  tester: bool                                      # set only by tool/catalog.py
  entitlements: { pro, proUntil, products[], grants[], updatedAt }
                                                    # written only by the RevenueCat webhook

users/{uid}/notebooks/{notebookId}
  title, cover {color | art | photo}, paper, paperSize, orientation,
  collectionId (its style), categoryId?, groupId?, order, lastOpenedAt, updatedAt

users/{uid}/notebooks/{nbId}/sections/{sectionId}
  title, order

users/{uid}/categories/{id}, users/{uid}/groups/{id}  # the shelf
users/{uid}/favoritePapers/{key}

users/{uid}/pages/{pageId}                           # flat collection: easy queries across notebooks
  notebookId, sectionId, title, order, paper?,
  template? {itemId, version, pdfPage, pack, sha256, bytes}, updatedAt

users/{uid}/pages/{pageId}/strokes/{strokeId}        # one doc per stroke (append-only)
  points (packed), tool, color, width, createdAt, deleted (tombstone)

users/{uid}/pages/{pageId}/elements/{elementId}      # stickers now; text boxes and images later
  kind, frame {x, y, w, h, rotation}, z, data{...}, deleted

users/{uid}/taskLists/{id}                           # title, color, order
users/{uid}/tasks/{id}                               # title, notes, done, due ("YYYY-MM-DD"),
                                                     # priority 0-3, listId?, order, createdAt, completedAt?
users/{uid}/events/{id}                              # title, notes, color, allDay,
                                                     # start/end (ms) or startDay/endDay,
                                                     # recurrence {freq, interval, weekdays[], until?, count?}

catalog/{itemId}                                     # covers, papers, stickers, templates,
  kind, name, version, format, unlock {free, pro, products[]},   collections; read-only
  visibility, collectionId?, category, tags, files {pack, sha256, bytes, preview}, ...
```

**Why one stroke per document:** strokes are append-only and each has a unique ID. Two devices adding ink at the same time never conflict. Erasing marks a stroke `deleted` (a tombstone) instead of removing it. This avoids the 1 MB Firestore document limit and makes sync close to conflict-free. If a page grows very large (thousands of strokes), a Cloud Function can **compact** old strokes into a snapshot blob in Cloud Storage.

**Security rules:** a user can only read and write `users/{uid}/**` when `request.auth.uid == uid`. The `entitlements` and `tester` fields are read-only to clients. Catalog packs in Storage download only for people who may use them (`firebase/storage.rules`).

---

## 5. The ink canvas (the hardest part)

1. **Input:** use a `Listener` to get raw `PointerEvent`s, which include `pressure`, `tilt` and `kind`.
   - **Palm rejection:** once a stylus has been seen, only `PointerDeviceKind.stylus` draws. Fingers then pan and zoom.
   - **Phones** (usually no stylus): a "Draw / Scroll" toggle. In Draw mode one finger draws and two fingers pan and zoom.
   - **Web:** ink is view-only (render strokes, no drawing tools), so the web doesn't need the input pipeline.
2. **Rendering is split into two layers** for performance:
   - A *committed layer*: finished strokes cached into a `ui.Picture` / raster image and redrawn only when they change.
   - A *live layer*: only the stroke being drawn right now, repainted every frame.
3. **Smoothing:** `perfect_freehand` turns raw points into a filled outline polygon.
4. **Tools:** pen, highlighter (multiply blend), eraser (stroke eraser for v1, pixel eraser later), lasso select/move, text box, image insert, shapes (Pro).
5. **Coordinates:** the page has a fixed logical size (e.g. 1404×1872, like a letter-ratio page). Store points in page coordinates so ink looks identical on the tablet and the web at any zoom level.
6. **Undo/redo:** a per-session command stack (add stroke / delete stroke / move elements).
7. **Sync:** when the pen lifts, write the stroke to Firestore. Firestore's local cache shows it instantly, and the web client's snapshot listener receives it within about a second.

**Spike this early** (start of Phase 2). Ink latency is the main technical risk. Because the web only renders ink, web performance is less of a concern.

**Layouts:** phones use a bottom nav bar and full-screen page view, with notebooks in a drawer. Tablets and web use a persistent sidebar. The page has a fixed size, so on phones it is zoomed to fit width and scrolled.

---

## 6. Notebook styles and content

Notely works like Noteshelf. The app's screens use a plain light or dark theme (Settings → Appearance). Each notebook has its own **cover**, **paper**, **style** and pages, which can come from **templates** and carry **stickers**. All of it is data, not code. [docs/content.md](docs/content.md) explains how to make and publish each kind, and [docs/skins-plan.md](docs/skins-plan.md) has the product plan behind it.

- **Notebook styles** (`assets/skins/`):
  - Bundled with the app: Classic, Minimal Dark, Pastel, Kraft Paper, and Botanical, which is included in Pro.
  - A `SkinEngine` turns a manifest into the `NotelySkin` theme extension, which draws a notebook's pages.
- **The catalog:**
  - Covers, papers, sticker packs, PDF templates and collections are published with `tool/catalog.py` to Firestore `catalog/` and Storage, with no app update.
  - Packs download on first use, are checked against their SHA-256, and are kept on the device by version.
- **Templates** are PDFs (pdfrx), with page links and pages pinned to the template version they were made from.

---

## 7. Monetization and entitlements

**Products and recommended prices (USD)** (product ids in [docs/skins-plan.md](docs/skins-plan.md) §7)
| Product | Price | Store type |
|---|---|---|
| Small pack (stickers, study pages) | **$1.99** | Non-consumable |
| Collection pack (covers + papers + planner + stickers) | **$2.99** | Non-consumable |
| Dated planner (one year) | **$3.99** | Non-consumable |
| Bundle (several collections) | **$5.99** | Non-consumable |
| **Notely Pro**, monthly | **$2.99/mo** | Auto-renewing subscription |
| **Notely Pro**, yearly | **$19.99/yr** (about 45% off monthly), with a **7-day free trial** | Auto-renewing subscription |
| Lifetime Pro (add later, after launch) | $49.99 | Non-consumable |

**Why these numbers**
- Note apps like Goodnotes and Notability charge roughly $10–20 a year. Notely also includes a planner and calendar, so $19.99/yr sits at the top of that range but stays competitive.
- Small pack prices ($1.99) are impulse buys. Bundles raise the average order.
- Push the **yearly** plan: show it first and use the free trial only on yearly. Yearly subscribers stay much longer.
- **Pro includes everything marked Pro**, plus a new collection or planner each month. Packs are also sold on their own, for people who don't want a subscription.
- Apple and Google take 15% under their small-business programs (under $1M/yr). Web purchases through Stripe cost about 3%.
- Launch with these prices, then A/B test with RevenueCat Experiments once there's traffic. Check current competitor prices before launch.

**Suggested free vs Pro split**
| Free | Pro |
|---|---|
| 3 notebooks, unlimited pages | Unlimited notebooks |
| Pen, highlighter, eraser, text | Shapes, lasso transform, custom pen presets, pixel eraser |
| Basic planner + to-do + calendar | Recurring events, reminders, calendar templates, habit tracker |
| Free styles, covers, papers, Basics stickers, the free planner | Everything marked Pro (styles, covers, papers, planners, stickers) |
| Sync across devices | PDF import/annotate, PDF export, handwriting search (later) |


**How purchases flow**
- **iOS / Android:** purchases must go through Apple / Google in-app purchase for digital goods. Use the `purchases_flutter` (RevenueCat) SDK.
- **Web:** RevenueCat Web Billing (backed by Stripe) or Stripe Checkout directly.
- **Single source of truth:** a RevenueCat webhook calls a Cloud Function, which writes `users/{uid}.entitlements`. The app reads entitlements from Firestore and RevenueCat, so something bought on the iPad unlocks on the web too.
- The RevenueCat `appUserID` is set to the Firebase `uid`.
- Right after a purchase, the app trusts the store receipt on that device, so the unlock doesn't wait for the webhook.
- Feature checks live in `lib/core/entitlements/` (`canCreateNotebookProvider` for the notebook limit). The limit only applies once the store is open.
- **Built (milestone 8):** the store code, paywall and webhook. Turning them on needs the accounts in [docs/store-setup.md](docs/store-setup.md).

---

## 8. Feature details

**Notebooks:** sidebar tree of notebooks → sections → pages (collapsible on tablet portrait). Drag to reorder. Page thumbnails come from a cached raster.

**Daily planner page:** auto-created for a date (`/planner/2026-10-14`). The skin's template art is the background, with these regions laid on top:
- Schedule column: shows calendar events for the day, and is tappable to add one
- Top 3 priorities and tasks due today (live data from `tasks`)
- Free ink area for notes

You can handwrite anywhere on the page, and the structured widgets stay interactive.

**To-do lists:** typed tasks with checkboxes, due dates, priority and drag reorder. A "handwritten task" option stores an ink snippet as the task title, with text recognition in Phase 5.

**Calendar:** month, week and day views (consider `table_calendar` for month, custom widgets for week/day). Events have colors and RRULE recurrence (Pro). Local reminders via `flutter_local_notifications` (Pro). Tapping a day opens that day's planner page.

**Web app:** same Flutter code built with `flutter build web`. It is for **viewing and typing**: notebooks and pages render with their ink (read-only), and users can add and edit text boxes, tasks, events and planner entries. There are no ink tools on the web. It uses a responsive layout with the sidebar always visible, plus keyboard shortcuts.

---

## 9. Roadmap

### Phase 0: Setup (1 week)
- [x] `flutter create` with iOS, Android and web; set up folder structure, lints, CI
- [x] Firebase project created ("Notely")
- [x] Register the iOS and Android apps in Firebase; `lib/firebase_options.dart`
- [x] Register the web app config
- [x] Firestore security rules + emulator tests (`firebase/`)
- [x] Publish the rules to the live database
- [ ] Auth: sign in with Apple, Google and email (required, see §1); account deletion (required by Apple)
  - [x] Deleting an account erases all its data (`deleteUserData` Cloud Function, deployed)
  - [x] Sign-in and settings screens, auth interface, stand-in auth for development
  - [x] Firebase Auth implementation (email, Google, Apple)
  - [ ] Google sign-in on Android: add the app's SHA-1 fingerprint in Firebase
  - [x] Apple sign-in: iOS entitlement added (`ios/Runner/Runner.entitlements`)
  - [ ] Apple sign-in: enable it on the App ID and in Firebase; Services ID + key for Android/web
- [x] Responsive app shell: phone (bottom nav), tablet and web (sidebar). The notebooks drawer comes with Phase 2

### Phase 1: Styles and content (done, then reworked Noteshelf-style; see docs/noteshelf-implementation.md)
- [x] Skin manifest format + `SkinEngine` (manifest → ThemeData + `ThemeExtension<NotelySkin>`)
- [x] 4 bundled free skins (Classic, Minimal Dark, Pastel, Kraft Paper)
- [x] Notebook style picker; Noteshelf-style shelf, covers and new-notebook screen
- [x] Catalog in Firestore and Storage: covers, papers, stickers, templates, collections, downloaded and cached
- [x] Golden tests: every skin on every page type
- [x] Content guide (`docs/content.md`): styles, covers, papers, stickers, templates and collections

### Phase 2: Core notebook MVP (4–6 weeks)
- [x] Notebooks / sections / pages: create, rename, delete (Firestore + offline)
- [ ] Tablet sidebar with the notebook tree (currently the same screens as phones)
- [ ] **Ink spike on real devices:** pressure ink on an iPad, an Android tablet and a phone; measure latency and FPS with 2,000+ strokes on a page (**needs devices**)
- [x] Canvas: pen, highlighter, stroke eraser, undo/redo, zoom/pan, palm rejection, phone Draw/Scroll toggle
- [x] Page paper (blank, lined, narrow, grid, dot, music, Cornell) and PDF templates with links
- [x] Text boxes and image insert
- [x] Offline mode and sync status indicator (cloud icon on pages and in the sidebar; a strip while offline; web keeps an offline copy too)
- [x] Web: read-only ink rendering
- [x] Web: text boxes, photos and stickers editable (ink stays view-only); links and refreshes keep their page
- [x] Web: deployed to Firebase Hosting at https://notely-b1aec.web.app (`tool/deploy_web.sh`)
- [x] Firestore security rules + rules unit tests

### Phase 3: Planner, to-do, calendar (4–5 weeks)
- [x] Tasks and task lists (editable on web); plan in [docs/phase3-plan.md](docs/phase3-plan.md)
- [x] Events and calendar month/week/day views (editable on web)
- [x] Daily planner page with live tasks and events plus a free ink area
- [x] Simple reminders (local notifications)

### Phase 4: Store and monetization (2–3 weeks)
- [x] Purchases code (RevenueCat) and webhook Cloud Function → entitlements, tested
- [ ] Accounts and products set up ([docs/store-setup.md](docs/store-setup.md)); webhook deployed; sandbox purchases on the iPad
- [x] Templates screen with previews, item pages and the Pro paywall
- [ ] "Try it": write on a sample page before buying
- [x] Feature gate: 3 notebooks on free
- [x] Restore purchases

### Phase 5: Polish and growth (ongoing)
- [ ] Handwriting recognition and search (`google_mlkit_digital_ink_recognition` on mobile; a server-side option for web)
- [ ] PDF import/annotate and export
- [ ] Google / Outlook calendar sync
- [ ] Shared notebooks (read-only links first, then collaboration)
- [ ] More content: journals, study packs, sticker art, the 2028 planner
- [ ] Desktop builds (macOS / Windows)

### Launch checklist
- [ ] App Store and Play listings, screenshots, privacy policy, terms
- [ ] Privacy nutrition labels / Data Safety form
- [ ] IAP products reviewed and approved
- [ ] Load test of Firestore costs (strokes are the main cost driver; see risks)

---

## 10. Testing strategy
- **Unit:** models, stroke encoding, manifest and listing parsing, unlock rules, feature gates.
- **Widget / golden tests:** each skin rendered on each page type, to catch theming regressions.
- **Firestore and Storage rules:** Firebase Emulator Suite + `@firebase/rules-unit-testing`.
- **Cloud Functions:** the RevenueCat webhook with recorded events against the Firestore emulator.
- **Integration:** `integration_test` on a physical iPad, an Android tablet, an iPhone and an Android phone (pen input can't be fully simulated).
- **Manual sync matrix:** phone/tablet offline → write → reconnect → check the web; web typing and tablet inking on the same page at once.

---

## 11. Key risks and mitigations
| Risk | Mitigation |
|---|---|
| Ink latency / jank (esp. low-end Android phones) | Early ink spike, two-layer rendering, raster caching |
| Firestore cost from many stroke docs | Batch writes, compact old strokes into Storage blobs, compact point encoding |
| Sync conflicts | Append-only strokes + tombstones; last-write-wins only for element moves and metadata |
| App Store rejection over payments | Native IAP on mobile; web purchases only on web; RevenueCat to unify |
| Content bloating the app | Only styles are bundled; covers, stickers and templates download on demand |
| Scope creep | Ship Phases 1–3 as a free beta before building the store |

---

## 12. Decisions
| Question | Decision |
|---|---|
| Platforms | iOS + Android, **phones and tablets**, plus web |
| Pricing | Skins $1.99 ($2.99 premium), bundles $5.99, Pro $2.99/mo or $19.99/yr with a 7-day trial (see §7) |
| Accounts | **Required** (Apple, Google, email) |
| Starting point | **Skins first** (Phase 1); the skin art is made by our team |
| Web | **Viewing and typing**: ink is read-only, while text, tasks and events are editable |
| Backend | **Firebase** |
