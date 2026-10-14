# Motley — Product & Technical Plan

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
  displayName, email, activeSkinId, createdAt
  entitlements: { pro: bool, skins: [skinId...] }   # written only by Cloud Function

users/{uid}/notebooks/{notebookId}
  title, color, skinId?, order, createdAt, updatedAt, deleted

users/{uid}/notebooks/{nbId}/sections/{sectionId}
  title, color, order

users/{uid}/pages/{pageId}                           # flat collection: easy queries across notebooks
  notebookId, sectionId, title, type: note|planner|todo|calendar
  template: blank|lined|grid|dot|plannerDaily|...
  date? (planner pages), order, updatedAt, deleted, size {w,h}

users/{uid}/pages/{pageId}/strokes/{strokeId}        # one doc per stroke (append-only)
  points: [x,y,pressure,...] (packed list / base64 Float32), tool, color, width,
  createdAt, deviceId, deleted (tombstone for eraser)

users/{uid}/pages/{pageId}/elements/{elementId}      # text boxes, images, stickers, shapes
  kind, x, y, w, h, z, data{...}, updatedAt

users/{uid}/tasks/{taskId}
  title, notes, done, dueDate?, listId, priority, order, pageId?, completedAt

users/{uid}/taskLists/{listId}
  title, color, order

users/{uid}/events/{eventId}
  title, start, end, allDay, color, recurrence (RRULE string), notes, reminderMinutes[]

skins/{skinId}                                       # public catalog, read-only to clients
  name, version, price tier, productId, previewUrl, manifestUrl, free: bool
```

**Why one stroke per document:** strokes are append-only and each has a unique ID. Two devices adding ink at the same time never conflict. Erasing marks a stroke `deleted` (a tombstone) instead of removing it. This avoids the 1 MB Firestore document limit and makes sync close to conflict-free. If a page grows very large (thousands of strokes), a Cloud Function can **compact** old strokes into a snapshot blob in Cloud Storage.

**Security rules:** a user can only read and write `users/{uid}/**` when `request.auth.uid == uid`. The `entitlements` field is read-only to clients.

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

## 6. Skins system

A skin is **data, not code**, so new skins can be sold without shipping an app update.

**Skin manifest** (JSON in Cloud Storage, cached locally):
```json
{
  "id": "botanical",
  "version": 3,
  "name": "Botanical",
  "colors": { "primary": "#4F7B5A", "surface": "#FBF8F1", "onSurface": "#2B2B2B", "accent": "#D98E73", ... },
  "darkColors": { ... },
  "fonts": { "heading": "Playfair Display", "body": "Inter", "handwritingAccent": "Caveat" },
  "paper": { "texture": "paper_cream.webp", "lineColor": "#D8D2C4" },
  "pageTemplates": { "plannerDaily": "planner_daily.svg", "todo": "todo.svg", "calendarMonth": "cal_month.svg" },
  "stickers": ["leaf1.png", "fern.png", ...],
  "icons": "rounded",
  "cornerRadius": 16
}
```

**In the app:**
- A `SkinEngine` loads the manifest and builds a Flutter `ThemeData` plus a custom `ThemeExtension<MotleySkin>`. The extension carries the paper texture, template art, stickers and decorative assets.
- Skins can apply app-wide (the default) or per notebook (a Pro feature).
- Assets are downloaded on demand and cached with `flutter_cache_manager`.
- **Free skins** are bundled in the app so they work offline on first launch: e.g. *Classic*, *Minimal Dark*, *Pastel* and *Kraft Paper*.
- **Paid skins** are fetched only once the entitlement exists. Store previews use low-resolution preview images.

---

## 7. Monetization and entitlements

**Products and recommended prices (USD)**
| Product | Price | Store type |
|---|---|---|
| Individual skin | **$1.99** ($2.99 for premium skins with extra templates and stickers) | Non-consumable |
| Skin bundle (4–5 themed skins) | **$5.99** (about 30–40% off buying them one by one) | Non-consumable |
| **Motley Pro**, monthly | **$2.99/mo** | Auto-renewing subscription |
| **Motley Pro**, yearly | **$19.99/yr** (about 45% off monthly), with a **7-day free trial** | Auto-renewing subscription |
| Lifetime Pro (add later, after launch) | $49.99 | Non-consumable |

**Why these numbers**
- Note apps like Goodnotes and Notability charge roughly $10–20 a year. Motley also includes a planner and calendar, so $19.99/yr sits at the top of that range but stays competitive.
- Small skin prices ($1.99) are impulse buys. Bundles raise the average order.
- Push the **yearly** plan: show it first and use the free trial only on yearly. Yearly subscribers stay much longer.
- **Pro includes a "Pro skins" collection** (e.g. one new skin each month for subscribers). This gives skin lovers a reason to subscribe instead of buying one skin at a time. Other skins stay sold individually.
- Apple and Google take 15% under their small-business programs (under $1M/yr). Web purchases through Stripe cost about 3%.
- Launch with these prices, then A/B test with RevenueCat Experiments once there's traffic. Check current competitor prices before launch.

**Suggested free vs Pro split**
| Free | Pro |
|---|---|
| 3 notebooks, unlimited pages | Unlimited notebooks |
| Pen, highlighter, eraser, text | Shapes, lasso transform, custom pen presets, pixel eraser |
| Basic planner + to-do + calendar | Recurring events, reminders, calendar templates, habit tracker |
| 4 free skins | Per-notebook skins, all "Pro-included" skins, sticker packs |
| Sync across devices | PDF import/annotate, PDF export, handwriting search (later) |

**How purchases flow**
- **iOS / Android:** purchases must go through Apple / Google in-app purchase for digital goods. Use the `purchases_flutter` (RevenueCat) SDK.
- **Web:** RevenueCat Web Billing (backed by Stripe) or Stripe Checkout directly.
- **Single source of truth:** a RevenueCat webhook calls a Cloud Function, which writes `users/{uid}.entitlements`. The app reads entitlements from Firestore and RevenueCat, so something bought on the iPad unlocks on the web too.
- The RevenueCat `appUserID` is set to the Firebase `uid`.
- A `FeatureGate` provider (`ref.watch(canUse(Feature.shapes))`) is the only place feature checks happen.

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
- [ ] `flutter create` with iOS, Android and web; set up folder structure, lints, CI
- [ ] Firebase project (dev + prod), FlutterFire config
- [ ] Auth: sign in with Apple, Google and email (required, see §1); account deletion (required by Apple)
- [ ] Responsive app shell: phone (bottom nav + drawer), tablet and web (sidebar)

### Phase 1: Skins (3–4 weeks), built first
- [ ] Skin manifest format + `SkinEngine` (manifest → ThemeData + `ThemeExtension<MotleySkin>`)
- [ ] 4 bundled free skins (Classic, Minimal Dark, Pastel, Kraft Paper)
- [ ] Skin picker screen with live preview on sample pages
- [ ] Skin catalog in Firestore; paid skin asset download and caching
- [ ] Golden tests: every skin on every screen and page type
- [ ] Skin authoring guide (`docs/skins.md`) so we can make new skins without code changes

### Phase 2: Core notebook MVP (4–6 weeks)
- [ ] Notebooks / sections / pages CRUD; sidebar (tablet/web) and drawer (phone) navigation
- [ ] **Ink spike first:** pressure ink on an iPad, an Android tablet and a phone; measure latency and FPS with 2,000+ strokes on a page
- [ ] Canvas: pen, highlighter, stroke eraser, undo/redo, zoom/pan, palm rejection, phone Draw/Scroll toggle
- [ ] Page templates (blank, lined, grid, dot), drawn from the active skin
- [ ] Text boxes and image insert
- [ ] Offline mode and sync status indicator
- [ ] Web: read-only ink rendering, text box editing; deploy to Firebase Hosting
- [ ] Firestore security rules + rules unit tests

### Phase 3: Planner, to-do, calendar (4–5 weeks)
- [ ] Tasks and task lists (editable on web)
- [ ] Events and calendar month/week/day views (editable on web)
- [ ] Daily planner page type with live task/event widgets plus a free ink area
- [ ] Simple reminders (local notifications)

### Phase 4: Store and monetization (2–3 weeks)
- [ ] RevenueCat set up for App Store, Play Store and Web; webhook Cloud Function → entitlements
- [ ] Store UI with previews and "try before you buy" (preview the skin on the current page)
- [ ] Feature gates for Pro features
- [ ] Restore purchases

### Phase 5: Polish and growth (ongoing)
- [ ] Handwriting recognition and search (`google_mlkit_digital_ink_recognition` on mobile; a server-side option for web)
- [ ] PDF import/annotate and export
- [ ] Google / Outlook calendar sync
- [ ] Shared notebooks (read-only links first, then collaboration)
- [ ] Habit tracker, journal templates, sticker packs
- [ ] Desktop builds (macOS / Windows)

### Launch checklist
- [ ] App Store and Play listings, screenshots, privacy policy, terms
- [ ] Privacy nutrition labels / Data Safety form
- [ ] IAP products reviewed and approved
- [ ] Load test of Firestore costs (strokes are the main cost driver; see risks)

---

## 10. Testing strategy
- **Unit:** models, stroke encoding, skin manifest parsing, feature gates.
- **Widget / golden tests:** each skin rendered on each page type, to catch theming regressions.
- **Firestore rules:** Firebase Emulator Suite + `@firebase/rules-unit-testing`.
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
| Skin assets bloating the app | Bundle only free skins; paid skins downloaded on demand |
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
