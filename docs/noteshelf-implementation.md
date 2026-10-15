# Implementation plan: Noteshelf-style notebooks

How to build what [skins-plan.md](skins-plan.md) describes, in nine milestones.
Each milestone ships on its own and leaves the app working. Sizes are relative:
**S** about a day, **M** a few days, **L** a week or more.

It assumes the recommendations in skins-plan.md §10: the interface becomes
plain light/dark, skins become per-notebook collections, packs are sold
individually as well as through Pro, and templates are PDFs.

| # | Milestone | Size | Needs from you |
|---|---|---|---|
| 1 | Paper and cover data model ✅ | M | — |
| 2 | Plain light/dark interface; skins become collections ✅ | M | — |
| 3 | The shelf: covers, categories, groups, sort ✅ | L | — |
| 4 | New-notebook flow and per-page paper ✅ | L | Turn on Firebase Storage (needs the Blaze plan) ✅ |
| 5 | Catalog and downloads (free items only) ✅ | L | — |
| 6 | Stickers ✅ | M | Sticker art (placeholder pack published) |
| 7 | PDF templates and dated planners ✅ | L | Planner designs (a generated 2027 planner is published) |
| 8 | Store and purchases ✅ (switched on once accounts exist) | L | App Store Connect, Play Console, RevenueCat and Stripe accounts and products: see [store-setup.md](store-setup.md) |
| 9 | Clean-up and docs ✅ | S | — |

---

## Milestone 1: Paper and cover data model

The data changes come first, with no visible change, so later screens build on tested models.

**New code**
- `lib/core/paper/paper_style.dart`: `PaperStyle {color, lineColor, marginColor?, pattern, spacing}` with `toMap`/`fromMap`. `PaperPattern` moves here and gains `narrowLined`, `music` and `cornell`. Also `PaperSize {letter, a4, a5, phone}` and `PaperOrientation`.
- `lib/core/paper/basic_papers.dart`: the built-in basic papers (7 patterns × white/cream/gray/dark) as constants.
- `lib/features/notebooks/domain/notebook_cover.dart`: `NotebookCover {kind: color | art | photo, color, coverId?, photoPath?}`.

**Changes**
- `Notebook` ([notebook_models.dart](../lib/features/notebooks/domain/notebook_models.dart)) gains `cover`, `paper`, `paperSize` and `orientation`. (`collectionId` arrives with milestone 2, and the shelf fields `categoryId`, `groupId`, `order` and `lastOpenedAt` with milestone 3, where they're first used. A paper `texture` arrives with the catalog in milestone 5.)
  - **Existing notebooks need no migration.** `fromMap` turns the old `color` field into a color cover. A missing `paper` falls back to the paper of the user's current skin, so existing notebooks look exactly as they do today.
- `NotePage` gains `paper?` (only when the page differs from its notebook) and `template?` (used from milestone 7).
- `NotebookRepository` ([notes_repository.dart](../lib/features/notebooks/data/notes_repository.dart)):
  - `createNotebook` takes a `NewNotebook` spec (title, cover, paper, size, orientation, collection).
  - `updateNotebook` accepts a cover and paper.
  - new `setPagePaper(pageId, PaperStyle?)`.
  - Implemented in both the Firestore and in-memory backends.
- `PaperPainter` ([paper.dart](../lib/core/skins/widgets/paper.dart)) takes a `PaperStyle` instead of reading `NotelySkin`. The `Paper` widget takes an optional style and falls back to the skin until milestone 2.

**Tests:** model round-trips, reading old notebooks without the new fields, both backends (create, update, page override), and the paper painter golden for each pattern.

---

## Milestone 2: Plain interface; skins become collections

**Interface**
- New `lib/app/app_theme.dart`: one light and one dark interface theme. They're built with the existing `SkinEngine` from two built-in definitions (`assets/interface/light.json`, `dark.json`), so the theme code is reused.
- New setting **Appearance**: System / Light / Dark. It's saved on the device and the account, the same way `activeSkinId` is today ([user_settings_repository.dart](../lib/core/settings/user_settings_repository.dart)). `MaterialApp` gets `theme`, `darkTheme` and `themeMode`.

**Collections**
- For now, each bundled skin manifest *is* a collection: a notebook style with paper, ink palette and accent font. It's turned into the page style by `SkinEngine.buildNotelySkin`. A separate `Collection` format (covers, several papers) arrives with the catalog in milestone 5, so the five skins aren't converted twice.
- Notebooks gain `collectionId`. A notebook without one uses the user's default style (the saved `activeSkinId`), so the user's earlier choice carries over.
- **Pages are drawn in their notebook's style:** `PageStyle` swaps the paper, ink palette and accent font into the page screen, while bars and menus keep the interface theme. The canvas and ink toolbar read them as before.
- The skin picker stays, renamed **Notebook styles**, and sets the default style. It's the only way to choose a look until the new-notebook flow in milestone 4.

**Tests:** appearance setting (device + account sync, like [account_skin_sync_test.dart](../test/core/skins/account_skin_sync_test.dart)), collection parsing, canvas uses notebook paper and palette, and goldens for the interface in light and dark plus each collection's paper.

---

## Milestone 3: The shelf ✅

**Data**
- `users/{uid}/categories/{id}` `{title, order}` and `users/{uid}/groups/{id}` `{title, categoryId?, parentGroupId?, order}`. The existing security rules already allow anything under `users/{uid}`.
- Notebooks gain `categoryId`, `groupId`, `order` and `lastOpenedAt`.
- **Only top-level items carry a category.** A notebook or group inside a group belongs to its top group's category, so moving a group (with everything in it) is one write, and nested items can't disagree about their category.
- `ShelfRepository` (both backends): categories and groups (create, rename, delete), moving notebooks and groups, and custom order. Deleting a category or group never deletes notebooks: they move up a level.
- Opening a notebook records `lastOpenedAt`. Writing in it bumps `updatedAt`, at most once a minute, so "Last modified" reflects writing.

**Screens** (`lib/features/shelf/`)
- `ShelfScreen` replaces the old notebook list. It shows All notebooks, Recent (the last 20 opened), one category or one group, chosen by the URL (`/notebooks?category=…`, `?group=…`, `?view=recent`).
- `CoverView` draws a cover with a spine; `GroupStackView` draws a group as a stack of up to three covers. Art and photo covers show their color until milestone 4.
- **View options:** sort by custom, last opened, last modified or name; grid or list; large or small covers. Saved per device.
- **Drag and drop** (long press): onto a group moves the notebook or group into it; onto a notebook (in custom order) places it just before.
- Menus: rename, change color, **Move to…** (a picker of categories and groups), delete.
- **Sidebar** on wide screens (1024 px and up, e.g. iPad landscape and the web): All notebooks, Recent, categories (with options and New category), Planner, Calendar, To-do and Settings. **Narrower screens** (phones, iPad portrait) get category chips across the top of the shelf; long-press a chip for its options. (The phone drawer from the original plan wasn't needed.)

**Tests:** shelf logic (what each location shows, nesting, missing groups, sorting, back navigation, URLs), repository operations in both backends, and screen flows on phone and tablet widths, including drag and drop.

## Milestone 4: New-notebook flow and per-page paper ✅

**New and edit notebook** (`NotebookEditor`, a full-screen dialog): a live preview of the cover and a page, then
1. Title.
2. **Cover:** Colors (16), Designs and Photo. Designs are six patterns drawn in code (stripes, dots, grid, chevron, waves, label) in any cover color, until catalog art arrives in milestone 5.
3. **Paper** (`PaperPicker`): seven rulings, white/cream/gray/dark or any color (hue, saturation and lightness sliders), narrow/medium/wide spacing, starred favorites, and each notebook style's paper.
4. **Style:** the ink colors and fonts. Picking a style switches to its paper unless a paper was chosen.
5. Page size (Letter, A4, A5, Phone) and orientation. These are for new notebooks only, since ink is saved in page units. Letter keeps the size every page had before, so older pages don't move.

The editor saves a concrete paper and style, so later changes to the default style don't change existing notebooks. Editing is under **Cover, paper & style** in the shelf and notebook menus.

**Photo covers:** `image_picker` shrinks the photo on the device (at most 1536 x 2048), then `CoverPhotoStore` uploads it to `users/{uid}/covers/{id}.jpg`. `firebase/storage.rules` lets each person reach only their own folder, and only images under 5 MB (tested in the Storage emulator). A failed upload shows a message and leaves the cover unchanged.

**Per page:** **Page paper** on the page screen, **Change paper** in the page list, and **New page with different paper** in the notebook menu. Each offers "Use the notebook's paper". Favorites are saved in `users/{uid}/favoritePapers`.

**Not done:** photos of a notebook that is cancelled or later changed stay in Storage. A clean-up function can come with the Cloud Functions in milestone 8.

## Milestone 5: Catalog and downloads (free items only) ✅

**Built for covers and papers**, the two kinds the pickers already had. Templates, sticker packs and collections are read but not shown yet, and are added with their milestones. The bundled skins stay as they are until collections arrive.

**App** (`lib/core/catalog/`)
- `CatalogItem`: the listing format of skins-plan.md §5. Instead of `minAppVersion`, each listing has a `format` number; the app skips formats newer than it reads, and kinds it doesn't know.
- **Papers live in the listing itself** (a paper is a few numbers), so nothing is downloaded and the notebook keeps a copy. Covers come as `pack.zip` with `cover.webp`.
- `CatalogRepository` (Firestore `catalog`), `catalogProvider` (everything readable, including retired items, so notebooks using them keep working) and `offeredCatalogProvider` (public, or for testers, and unlocked).
- `PackCache` looks in memory, then on the device, then downloads. Downloads are checked against `sha256` and unpacked, and file names that could escape the folder are dropped. Packs are kept per version (`<support>/catalog/<id>/<version>/`; memory on the web), old versions are removed, and requests made at the same time share one download.
- Pickers: **More covers** (with previews) and **More papers**. `CoverView` draws catalog covers once downloaded. `Entitlements.canUseCatalogItem` covers free, Pro, products and grants.
- The tester flag is `users/{uid}.tester`, which only the server may set.

**Firebase**
- Firestore: `catalog/{id}` is readable when signed in and never written by the app. `tester` joins `entitlements` as a server-only field.
- Storage: previews are readable when signed in. A pack is readable only if `canUseItem` passes; it looks up the listing and the user's entitlements in Firestore. The Storage service account was given `roles/firebaserules.firestoreServiceAgent` so these rules can read Firestore.
- Rules tests cover free, Pro, product, grant and visitor access. The Firestore and Storage test files run one at a time, as they share the emulator's database.

**Tools:** `tool/catalog.py` (Python, like the icon script) runs `check`, `publish <id> --testers|--public|--hidden|--retired [--dry-run]` and `set-tester <uid> on|off`. It uses the gcloud login. CI runs `check`. Guide: [content.md](content.md).

**Published:** the free covers Night Sky and Terrazzo, and the free paper Sage Dot.

## Milestone 6: Stickers ✅

- **Elements:** `users/{uid}/pages/{pageId}/elements/{id}` `{kind: "sticker", itemId, file, x, y, w, h, rotation, z, deleted}`, where x and y are the center. Removing sets `deleted`, as erasing does for strokes, so undo and other devices see it. `ElementRepository` is in both backends, and deleting a page deletes its elements. Kinds this version doesn't know (images and text boxes later) are skipped.
- **Canvas:** stickers are drawn **under** the ink, so you can write over them.
- **Select tool:** tap a sticker to select it, then:
  - drag to move it,
  - use the corner handle to resize it (it keeps its shape),
  - use the top handle to rotate it (it snaps straight within 4°),
  - tap the red × to remove it.

  In Select mode a stylus never draws; fingers can move stickers, and a finger on empty paper still scrolls. While a sticker moves, the canvas shows its new place until the saved copy catches up (as with ink), so nothing jumps.
- **Sticker tray** (toolbar): every sticker pack the user can use, downloaded on first open. Tapping a sticker places it in the middle of the view, selected, and switches to the Select tool. (Dragging from the tray was left out: tapping covers it.)
- **Undo and redo** cover placing, moving, resizing, rotating and removing (`ElementPresenceCommand`, `ElementFrameCommand`).
- **Web:** stickers show, but the page stays view-only.
- **Content:** `tool/catalog.py` handles `stickers` packs (`stickers.json` + transparent WebP images, each checked). The free **Basics** pack has 16 stickers drawn in code as placeholders until real art arrives: star, heart, done, arrow, smile, sun, cloud, flower, leaf, coffee, idea, pin, important, music, sparkle and birthday.

## Milestone 7: PDF templates and dated planners ✅

**One change of approach:** a dated planner is a **ready-dated PDF per year**, as commercial planners are sold, not generic pages that the app fills with dates. Its links are ordinary **PDF links**. This keeps the app simple, lets designers' PDFs work as they are, and is the same path PDF import will take. Picking the year means picking that year's planner, which matches the `planner_<id>_<year>` products in skins-plan.md §7.

**Rendering:** `lib/core/pdf/pdf_renderer.dart` hides `pdfrx` (PDFium on iOS, Android, desktop and the web) behind `PdfRenderer` and `PdfFile` (page sizes, links, render), so tests use a fake. A template page is drawn 1600 px wide (sharp at fit-to-width on a tablet), fitted inside the page, and freed when the page closes.

**Data:**
- Pages gain `template {itemId, version, pdfPage, pack, sha256, bytes}`. Keeping the exact pack means a page made from version 1 still downloads version 1 after version 2 is published. Template packs keep their old versions on the device.
- `template.json` (`TemplateSpec`) is either a planner (`mode: notebook`, sections of PDF pages with titles) or single pages (`mode: pages`). The listing records `templateMode` and `pageCount`, so pickers don't need a download.
- Repositories add `createPages` (batched, 450 per write) and `watchNotebookPages`.

**Using templates:**
- **New notebook → Start with:** Blank pages, or a planner. A planner sets the page size from the PDF and creates every page in its sections; for example the 2027 planner gives sections 2027, Months and Weeks, 66 pages in all.
- **Notebook menu → New page from template:** a sheet with each single-page template's pages shown as small renders.
- **Links:** a quick finger or mouse tap on a link opens the page it points to. A finger tap there doesn't leave a dot; a Pencil tap always writes.

**Content:** `tool/make_planner.py` writes vector PDFs (standard library only) with link annotations. The free **2027 Weekly Planner** has a year page, 12 month calendars and 53 week pages. Month tabs on every page, year and month links, week rows that open their week, and previous/next week arrows give 1,100 links, all checked with Apple's PDFKit. The free **Essentials** pack has to-do, meeting notes and habit tracker pages. `tool/catalog.py` checks templates: the PDF, `template.json`, and that page numbers exist.

**Not done yet:**
- **Sharpness when zoomed:** template pages don't re-render sharper on zoom. They're drawn once at 1600 px, which gets soft beyond about 2x.
- **PDF import** (the user's own PDFs) reuses all of this, but still needs a file picker and upload. It stays in Phase 5.

## Milestone 8: Store and purchases ✅

Built and tested. It switches on when a build has a RevenueCat key. Until then the store shows "Coming soon", nothing can be bought, and there's no notebook limit. [store-setup.md](store-setup.md) is the step-by-step guide for your accounts.

**App**
- **New dependency:** `purchases_flutter`.
- **`lib/core/purchases/`:**
  - `PurchasesClient` covers prices, buying, restoring and the device receipt.
  - `RevenueCatPurchases` implements it with the RevenueCat SDK, and `UnavailablePurchases` is used when there's no key.
  - Keys come from `--dart-define=REVENUECAT_APPLE_KEY` (plus `_GOOGLE_` and `_WEB_`).
  - The RevenueCat user is the Firebase uid.
- **`lib/core/entitlements/`:**
  - `Entitlements` reads `users/{uid}.entitlements` (`pro`, `proUntil`, `products`, `grants`) and merges the device receipt, so a purchase unlocks at once.
  - `feature_gate.dart` limits free accounts to 3 notebooks.
- **Collections:** `tool/catalog.py` copies a collection's products and Pro into each of its items when publishing. That way the app and the Storage rules only check the item itself.
- **The Templates screen** (`lib/features/store/`):
  - Sections: Planners, Journals, Study, Collections, Page templates, Covers, Papers and Stickers.
  - Filters: All, Free, Pro and Yours.
  - A Pro banner, and Restore purchases.
  - Reached from the sidebar, the shelf's app bar and Settings.
- **Item page:**
  - Shows a preview, what the item is, and which collection it belongs to.
  - A locked item has Buy (with the price from the store) and *Included in Jotswift Pro*.
  - An unlocked item has Use: a new notebook with the planner, cover or paper, or a hint for page templates and stickers.
  - "Try it" is a preview image for now. A page to write on without saving would need a scratch notebook, and can come later.
- **The paywall:**
  - Yearly first with the 7-day trial, then monthly, plus Restore.
  - It closes itself when Pro arrives.
  - It opens when a free account at the notebook limit taps New notebook.
- **Settings:** Jotswift Pro, Templates and Restore purchases.
- **Locked items:** pages and notebooks keep whatever they already use, and only new use is blocked.

**Firebase**
- **`firebase/functions/`** (TypeScript) holds `revenuecatWebhook`.
  - It checks the Authorization header with a constant-time comparison.
  - On any event it reads the customer from RevenueCat's API and rewrites `pro`, `proUntil` and `products`, leaving `grants` alone. Repeated, late or out-of-order events, refunds, expiry and transfers are all handled by that one path.
  - Anonymous RevenueCat ids are ignored.
- The Firestore rules already block the app from writing `entitlements`.

**Tests**
- 14 function tests:
  - the unlock maths
  - recorded RevenueCat events (Pro trial, pack purchase and refund, expiry, transfer, anonymous purchase) run against the Firestore emulator
- 17 app tests:
  - every unlock rule
  - account plus receipt
  - store sign-in and sign-out
  - the notebook limit
  - the store, buy, cancel, Pro, restore, and the store before it opens, all with a fake store

**Still to do on the iPad, once the accounts exist:** a sandbox purchase of a pack and of Pro, a restore, a refund and an expired subscription.

---

## Milestone 9: Clean-up and docs ✅

- **Skin store code removed:**
  - `SkinTier`, `productId`, the unused `stickers` and `paper.texture` manifest fields, `ownedSkinIds`, and the skin picker and detail screens.
  - A style now has one optional flag, `"pro": true`. Botanical uses it, so it's included in Pro instead of being a separate purchase that couldn't be bought.
  - The old `skins/{id}` Firestore rules were already gone.
- **Settings → Notebook style** is one screen: tap a style to make it the default. A Pro style shows the paywall first.
- **A notebook keeps its own style** even if that style is no longer unlocked. This matches the rule that only new use is locked.
- **One guide:** skins.md and catalog.md are merged into [content.md](content.md).
- **PLAN.md** updated: §4 data model, §6 content, §7 products and purchases, the roadmap and the testing notes.

---

## Order and checkpoints

- Milestones 1–4 make Jotswift *feel* like Noteshelf, without any downloads or purchases. That's a good point to put it on your iPad and compare it with Noteshelf side by side.
- Milestones 5–7 add content.
- Milestone 8 starts earning. Its account setup (step 1 of milestone 8) can start any time, because Apple and Google approvals take days.
- Every milestone ends with `flutter analyze`, all tests passing, the rules tests for Firebase changes, a build installed on the iPad, and a commit.
