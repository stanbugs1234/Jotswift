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
| 4 | New-notebook flow and per-page paper | L | Turn on Firebase Storage (needs the Blaze plan) |
| 5 | Catalog and downloads (free items only) | L | — |
| 6 | Stickers | M | Sticker art (I can make placeholders) |
| 7 | PDF templates and dated planners | L | Planner designs (I can make a simple first one) |
| 8 | Store and purchases | L | App Store Connect, Play Console, RevenueCat and Stripe accounts and products |
| 9 | Clean-up and docs | S | — |

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

## Milestone 4: New-notebook flow and per-page paper

**New notebook** (`lib/features/notebooks/new_notebook/`): one sheet with a live preview.
1. Title.
2. **Cover:** tabs for Colors, Designs (from collections) and Photo.
3. **Paper:** the basic patterns × colors, any color (a color wheel), and the papers of each collection.
4. Size and orientation.

**Photo covers**
- New dependencies: `image_picker` and `firebase_storage`.
- The photo is resized on the device to at most 1536×2048, then uploaded to `users/{uid}/covers/{notebookId}.jpg`.
- New `firebase/storage.rules`: a user can only read and write their own folder, and the file must be an image under 5 MB. Rules tests are added next to the Firestore ones in `firebase/rules-tests`.

**Per page**
- Page menu: **Change paper** (for this page only), and **Add page** with a choice of paper.
- Favorites: a star on any paper adds it to `users/{uid}.favorites`, shown first in pickers. The Firestore rules get a size check for that field.

**On the iPad:** check the cover photo upload and paper changes with the Pencil.

**Tests:** create a notebook with each cover kind, page paper override, favorites, storage rules tests.

---

## Milestone 5: Catalog and downloads (free items first)

**App**
- `lib/core/catalog/`:
  - `CatalogItem` (the listing format in skins-plan.md §5)
  - `BundledCatalog` (`assets/catalog/`), `FirestoreCatalog` (`catalog/{id}`), and `catalogProvider`, which merges them and hides `hidden`, `retired`, newer-`minAppVersion` and (unless tester) `testers` items
  - `PackCache`: downloads `pack.zip` from Storage, checks the `sha256`, unzips into the app's support folder by id and version, and removes unused old versions. On the web, files are kept in memory and the browser's cache.
- New dependencies: `archive`, `crypto`, `path_provider`.
- Covers, papers and collections from the catalog appear in the milestone 4 pickers. They download when first used.

**Firebase**
- The Firestore rule for `skins/{id}` becomes `catalog/{id}`: read if signed in, never written by the app.
- Storage rules for `catalog/`:
  - previews: anyone signed in can read
  - packs: readable only if the item is free or the user is entitled (`firestore.get` on the user's entitlements and the catalog entry)

**Tools** (in `firebase/tools/`, Node, using the Admin SDK)
- `catalog_check`: listing format, sizes, image dimensions, PDF pages and links, paper contrast.
- `publish_catalog <id> --testers|--public`: zips, computes the hash, uploads and writes the listing.
- A GitHub Actions job runs `catalog_check` on every change under `catalog/`.

**Proof:** publish two free covers and a free paper, then use them on the iPad (including offline after the first use).

**Tests:** catalog merge and filtering, cache (download, bad hash rejected, version change, clean-up) with a fake downloader, rules tests for the catalog and packs.

---

## Milestone 6: Stickers

- Elements on a page: `users/{uid}/pages/{pageId}/elements/{id}` `{kind: "sticker", itemId, file, x, y, w, h, rotation, z}`. This is the `elements` collection already in PLAN.md §4, and the same code later serves image insert and text boxes.
- `ElementLayer` in the canvas, drawn **under** the ink so you can write over stickers.
- **Sticker tray** in the ink toolbar ([ink_toolbar.dart](../lib/features/canvas/ink_toolbar.dart)): owned packs, tap or drag to place.
- **Select tool:** tap a sticker to move, resize (corner handle), rotate or delete it. Undo and redo cover these actions.
- **Web:** stickers are shown, not edited (matching the web's view-and-type role).
- A first free sticker pack. I can draw simple placeholder stickers in code. The real art comes from your designer.

**Tests:** element repository in both backends, select/move/resize gestures, undo/redo, golden of a page with stickers and ink.

---

## Milestone 7: PDF templates and dated planners

**Rendering**
- New dependency: `pdfrx`, which renders PDF pages on iOS, Android and the web.
- A page with a `template` draws that PDF page as its background, rendered at the current zoom and cached. Ink is drawn on top as today.
- The same renderer becomes **PDF import** (PLAN.md Phase 5): an imported PDF is a private template.

**`template.json`**
```jsonc
{
  "pages": [{ "key": "year", "pdfPage": 1 }, { "key": "month", "pdfPage": 2 }, …],
  "links": [{ "on": "year", "rect": [0.1, 0.2, 0.2, 0.25], "to": "month:1" }, …],
  "dated": { "kinds": ["year", "month", "week", "day"], "weekStarts": "monday" }
}
```

**Using a template**
- **A single page:** add it from the page menu.
- **A dated planner:** pick the year and start day. The app creates every page (about 430 for a daily planner), written in batches of up to 400. It saves a map from page key to page id on the notebook, so links can jump between pages.
- **Links:** in Scroll mode, or with a finger when a Pencil is in use, tapping a link area jumps to that page.
- Pages store the template version they were made with (skins-plan.md §5).

**First planner:** a simple dated weekly planner that I generate from code. Your designer's planners replace it.

**On the iPad:** writing speed on a PDF background, and memory use on a 400-page planner.

**Tests:** template.json parsing and link validation, dated page generation (leap years, week start), link navigation, golden of a template page with ink.

---

## Milestone 8: Store and purchases

**You need to set up first** (I'll write the step-by-step):
1. App Store Connect: Paid Apps agreement, banking and tax; Family Sharing decision; products.
2. Google Play Console: merchant account and products.
3. A RevenueCat project with the App Store, Play Store and Web Billing (Stripe); a `pro` entitlement; webhook to the Cloud Function.
4. Firebase on the Blaze plan (needed for Cloud Functions; also for Storage in milestone 4).

**App**
- New dependency: `purchases_flutter`. RevenueCat is configured at sign-in with the Firebase uid.
- `lib/core/entitlements/` ([entitlements.dart](../lib/core/entitlements/entitlements.dart)):
  - reads `users/{uid}.entitlements` and merges RevenueCat's latest receipt
  - `canUse(CatalogItem)` implements the rules in skins-plan.md §7
  - `FeatureGate` for Pro features (notebook limit of 3 on free)
- **Templates screen** (`lib/features/store/`), in the sidebar:
  - sections for Planners, Journals, Study, Papers, Covers, Stickers, Collections, Pro and Owned
  - an item page with previews, **Try it** (sample page with the item, without saving), and Buy or Use
- **Paywall** for Pro, with yearly first and the 7-day trial.
- **Restore Purchases** on the Templates screen and in Settings.
- Locked items: anything already used stays visible, and only new use is blocked.

**Firebase**
- New `firebase/functions/` (TypeScript): a `revenuecatWebhook` function that checks RevenueCat's secret header and updates `users/{uid}.entitlements` for purchases, refunds and subscription changes. It's tested with recorded RevenueCat events in the emulator.
- The Firestore rules already block the app from writing `entitlements`.

**On the iPad:** a sandbox purchase of a pack and of Pro, a restore, a refund and an expired subscription.

**Tests:** every unlock rule in skins-plan.md §7, the feature gate, the webhook function, and the store flow with a fake purchases client.

---

## Milestone 9: Clean-up and docs

- Remove the unused skin code: `SkinManifest`'s commerce fields, `skin_picker_screen.dart`, `skin_detail_screen.dart`, and the old `skins` rules. The interface theme and the manifest parser keep only what they still use.
- Rewrite [skins.md](skins.md) as **content.md**: how to make covers, papers, templates, sticker packs and collections, and how to release them.
- Update PLAN.md §4, §6, §7 and the roadmap.

---

## Order and checkpoints

- Milestones 1–4 make Notely *feel* like Noteshelf, without any downloads or purchases. That's a good point to put it on your iPad and compare it with Noteshelf side by side.
- Milestones 5–7 add content.
- Milestone 8 starts earning. Its account setup (step 1 of milestone 8) can start any time, because Apple and Google approvals take days.
- Every milestone ends with `flutter analyze`, all tests passing, the rules tests for Firebase changes, a build installed on the iPad, and a commit.
