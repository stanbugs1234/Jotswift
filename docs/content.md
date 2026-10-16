# Making content: styles, covers, papers, stickers, templates and collections

Jotswift's look comes from content, not code.

| Kind | What it is | Where it lives | How it ships |
|---|---|---|---|
| **Notebook style** | Paper, ink colors and fonts for a notebook's pages | `assets/skins/<id>/` | With the app |
| **Cover** | A notebook cover image | `catalog/<id>/` | Published from Firebase, no app update |
| **Paper** | A page background: color and ruling | `catalog/<id>/` | Published |
| **Sticker pack** | Images to place on pages | `catalog/<id>/` | Published |
| **Template** | A PDF planner, or single PDF pages | `catalog/<id>/` | Published |
| **Collection** | A set of the above, sold together | `catalog/<id>/` | Published |

The app's own screens don't change with any of these. They use the plain
light and dark themes in `assets/interface/`, chosen under **Settings →
Appearance**.

---

## Notebook styles

A style is a folder with a `manifest.json`. Each notebook can pick a style
in its editor, and **Settings → Notebook style** sets the default for
notebooks that don't pick one.

```
assets/skins/
  catalog.json          ← style ids in the order shown in the app
  classic/
    manifest.json
```

**Adding one**

1. Copy a folder, such as `assets/skins/classic/`, to `assets/skins/<your_id>/`.
   The id may only use lowercase letters, digits and `_`.
2. Edit `manifest.json`, and set `"id"` to the folder name.
3. Add the id to these:
   - `assets/skins/catalog.json`
   - `pubspec.yaml`: add `- assets/skins/<your_id>/` under `assets:`
   - the style lists in `test/core/skins/bundled_skins_test.dart` and `test/goldens/skins_golden_test.dart`
4. Run the tests and make the screenshot:
   ```sh
   flutter test                                   # valid manifest, readable colors
   flutter test --tags golden --update-goldens    # test/goldens/skins/<id>.png
   ```
   Check that the screenshot looks right.

If a step is missed, the tests say which one.

**manifest.json**

```jsonc
{
  "schemaVersion": 1,            // always 1 for now
  "id": "botanical",             // same as the folder name
  "version": 1,                  // bump whenever you change the style
  "name": "Botanical",
  "description": "Sage greens and terracotta on cream, for calm, leafy pages.",
  "pro": true,                   // optional: included in Jotswift Pro instead of free
  "brightness": "light",         // "light" or "dark"

  "colors": {                    // "#RRGGBB" or "#AARRGGBB"; style the preview card
    "primary": "#4F7B5A", "onPrimary": "#FFFFFF",
    "secondary": "#D98E73", "onSecondary": "#2B2B2B",
    "background": "#EEF1E8", "surface": "#FBF8F1", "onSurface": "#2B2B2B",
    "outline": "#A9B8A0", "error": "#B3261E"
  },

  "paper": {                     // the paper new notebooks get
    "color": "#FBF8F1",
    "lineColor": "#D8D2C4",
    "marginColor": "#E8A0A0",    // optional, lined paper only
    "pattern": "dot",            // blank, lined, narrowLined, grid, dot, music, cornell
    "spacing": 26                // 8–200
  },

  "inkColors": ["#2B2B2B", "#4F7B5A", "#D98E73", "#8A6FB0", "#C9A227"],
                                 // pen palette; the first is the default pen

  "typography": {                // any family from fonts.google.com
    "heading": "Cormorant Garamond",
    "body": "Inter",
    "accent": "Dancing Script"   // planner and list headers
  },

  "cornerRadius": 16             // roundness of pages
}
```

**Readability rules** (checked by the tests, following WCAG AA):

| Pair | Minimum contrast |
|---|---|
| `onSurface` on `surface`, `background` and `paper.color` | 4.5 : 1 |
| `onPrimary` on `primary` | 4.5 : 1 |
| `onSecondary` on `secondary` | 3 : 1 |
| First ink color on `paper.color` | 4.5 : 1 |

**Pro styles:** a notebook that already uses a Pro style keeps it if Pro ends. Only choosing it again needs Pro.

**Tips:**
- Keep `lineColor` faint, so it guides handwriting without competing with it.
- For dark styles, make `paper.color` a little lighter than `background`.
- If a font name is misspelled, the app silently uses the default font, so check the name on fonts.google.com.

---

## Catalog items

Covers, papers, stickers, templates and collections are published from
Firebase. Each is a folder in `catalog/`, and its name is the item's id:
lowercase letters, digits and `_`. An id can never be reused.

### Every listing.json

```jsonc
{
  "kind": "cover",               // cover, paper, stickers, template, collection
  "name": "Night Sky",           // shown in pickers and the store
  "version": 1,                  // raise it whenever the files change
  "unlock": { "free": true },    // see "Free, Pro or sold" below
  "collectionId": "space",       // optional: the collection it belongs to
  "category": "covers",          // templates: see "Template categories" below
  "tags": ["dark", "illustrated"]
}
```

### Covers
- **Files:**
  - `cover.webp`: 1536 x 2048
  - `preview.webp`: at most 512 px wide
- **Listing:** add `"color": "#1C2A57"`, shown while the image loads.

### Papers
- **Files:** none. The paper lives in the listing:
  ```jsonc
  "paper": {
    "color": "#EEF2EA",
    "lineColor": "#AFC0A8",      // faint, but must be visible (the check tests it)
    "marginColor": null,
    "pattern": "dot",
    "spacing": 26
  }
  ```

### Sticker and cover packs drawn in code
```sh
python3 tool/make_stickers.py all   # 7 packs: planner icons, washi tape, labels, study, seasons, faces, weather & moon
python3 tool/make_covers.py all     # 3 packs of 12: textures, patterns, seasons (each pack is a collection of covers)
```

### Sticker packs
- **Files:**
  - `stickers.json`, which lists every image
  - a `stickers/` folder of transparent WebP images, at most 1024 px
  - `preview.webp`
- **stickers.json:**
  ```jsonc
  { "stickers": [ { "file": "stickers/star.webp", "name": "Star" } ] }
  ```
- Stickers are placed 240 page units wide (a page is about 1400 wide) and keep their shape.

### Templates
- **Files:** `template.pdf`, `template.json` and `preview.webp`. Any PDF works, including a designer's.
- **Making Jotswift's own:**
  ```sh
  python3 tool/make_planner.py planner 2028    # catalog/planner_2028/: a dated weekly planner
  python3 tool/make_planner.py essentials      # catalog/essentials_pages/: to-do, meetings, habits
  ```
- **Page packs and journals** are listed in `tool/packs.json` (name, category, unlock, US price, and the layouts from `tool/layouts/`), then made with:
  ```sh
  python3 tool/make_pack.py student_pages   # or: all, or --list
  ```
  A new layout is a function in a `tool/layouts/<category>.py` module that returns `(page, title)`, built from the helpers in `tool/layouts/kit.py`.
- **Linked diaries and planners** (a year page, month pages, then a page per day or week, with month tabs and arrows) come from:
  ```sh
  python3 tool/make_diary.py all 2027          # every book for 2027
  python3 tool/make_diary.py academic_planner 2026   # July 2026 - June 2027
  python3 tool/make_diary.py --list
  ```
  Styles, page bodies and prices are in `BOOKS` in `tool/make_diary.py`. Dated items are named `<book>_<year>` and sold as `planner_<book>_<year>`; make next year's each autumn.
- **Spread planners** (landscape two-page spreads with rainbow tabs, undated, in Classic, Pastel and Neutral colourways) are listed in `tool/spreads.json` and made with `python3 tool/make_spreads.py all`. Layouts live in `tool/spreads/` (one module per section, drawn with `tool/spreads/kit.py`). Each pack holds a PDF per colourway, listed as `"variants"` in template.json; people pick the colours when they make the notebook.
- **Template categories** decide the row on the Templates screen: `planners` (or no category) for dated planners, `spreads`, `diaries`, `journals`, `study`, `work`, `wellness`, `lifestyle`, `creative`, and `pages` for general page packs.
- **template.json** says how the PDF is used:
  ```jsonc
  // A planner: every listed page becomes a page of a new notebook, in sections.
  { "mode": "notebook", "sections": [
      { "title": "Months", "pages": [ { "pdfPage": 2, "title": "January" } ] } ] }

  // Single pages, added with "New page from template".
  { "mode": "pages", "pages": [ { "pdfPage": 1, "title": "To-do list" } ] }
  ```
- **Dates:** a planner's pages can say which days they cover, so a notebook opens on today's page (on a new day) and the page has a Today button. Use `"from"` and `"to"` (`YYYY-MM-DD`) for dated pages, or `"month"` (1-12) for undated monthly pages that fit any year. The narrowest page wins: a week over its month, a month over the year.
  ```jsonc
  { "pdfPage": 45, "title": "Week 42", "from": "2027-10-11", "to": "2027-10-17" }
  { "pdfPage": 11, "title": "October", "month": 10 }
  ```
  `make_planner.py`, `make_collection.py` and `make_budget.py` write these. Older pages without dates open where the user left off.
- **Links:** links between pages are ordinary PDF links. Tapping one opens that page.
- **Page size:** a notebook made from a template gets the page size closest to the PDF's.
- **Versions:** pages keep the version they were made with, so a new version never moves writing on a filled page.
- **Size:** up to 25 MB.

### Collections
- **Making a whole collection in code:** add its style to `tool/collections.json` (colors, page color, border, header style, motif, font, cover colors, papers), then:
  ```sh
  python3 tool/make_collection.py botanical   # or: all
  python3 tool/make_collection.py all --year 2026   # only the dated planners, for another year
  ```
  This writes the collection and its items: a dated planner (`<id>_planner_2027`), a page pack with every layout in `tool/page_layouts.py` (`<id>_pages`, 23 pages: planning, to-do, trackers, study), three covers, papers and a sticker pack. Each item gets `"collectionId"`, so buying the collection unlocks it all. A new layout added to `page_layouts.py` appears in every collection the next time it's made.
  - Re-running keeps each item's `version`; raise it by hand when the files change, before publishing again.
  - Look at the PDFs and previews before publishing.
- **Files:** `preview.webp`. A collection is a listing plus its preview:
  ```jsonc
  { "kind": "collection", "name": "Botanical", "version": 1,
    "unlock": { "pro": true, "products": ["pack_botanical"] } }
  ```
- **Adding items:** give each item `"collectionId": "botanical"`. Its store page then lists everything in it.
- **Unlocking:**
  - When an item is published, it gets its collection's products and Pro on top of its own unlock. So buying the collection unlocks everything in it, including items added later.
  - If the collection's products change, publish its items again.

---

## Free, Pro or sold

`unlock` says how someone gets an item. Any one way is enough.

| unlock | Who can use it |
|---|---|
| `{ "free": true }` | Everyone |
| `{ "pro": true }` | Jotswift Pro subscribers |
| `{ "products": ["pack_space"] }` | People who bought `pack_space` |
| `{ "pro": true, "products": ["pack_space"] }` | Either, which is the usual choice for paid items |

- **Product ids:** they look like `pack_<name>`, `planner_<name>_<year>` or `bundle_<name>`. They can never be renamed or reused.
- **Prices:** set in App Store Connect and Google Play, not here.
- **Grants:** support can give an item for free by adding its id to the account's `entitlements.grants`.
- **Ends of access:** after a refund or when Pro ends, notebooks and pages keep what they already use. Only new use is locked.

**Putting a paid item on sale:**
1. Publish it `--hidden`.
2. Create its product in App Store Connect, Google Play and RevenueCat ([store-setup.md](store-setup.md)).
3. Publish it `--testers` and try a sandbox purchase.
4. Publish it `--public`.

---

## Check, publish, change, remove

```sh
pip install pillow                                   # once
python3 tool/catalog.py check                        # every item; also runs in CI

gcloud auth login                                    # once, as a Firebase project owner
python3 tool/catalog.py publish night_sky --testers  # only tester accounts see it
python3 tool/catalog.py publish night_sky --public   # everyone sees it
```

- **What the check covers:** sizes and formats, that ruling is visible, PDF page numbers, unlocks, collections, and pack size (5 MB, or 25 MB for templates).
- **`--dry-run`** shows what would be uploaded without changing anything.
- **Publishing:**
  - uploads `pack.zip` and `preview.webp` to Storage under `catalog/<id>/<version>/`
  - writes the listing to Firestore `catalog/<id>`
- **Testers:** `python3 tool/catalog.py set-tester <uid> on`. The uid is under Firebase console → Authentication.
- **Changing:** edit, raise `version`, publish again. Devices download the new version the next time they show it. The tool refuses to republish changed files under the same version.
- **Removing:** `--retired` takes the item out of the pickers and the store, and notebooks already using it keep it. `--hidden` hides it too.

**Who can download what** (`firebase/storage.rules`):
- Previews are open to anyone signed in.
- A pack downloads only for someone who may use the item, by the same rule as the app: free, Pro on a Pro item, a product bought, or a grant.
