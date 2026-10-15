# Plan: Noteshelf-style covers, paper, templates and stickers

Jotswift's look and its store are modeled on **Noteshelf 3**. This replaces the
app-wide skins in [PLAN.md](../PLAN.md) §6 and adds to the store plan in §7.
How to make and publish content is in [content.md](content.md).

**Summary**
- **Like Noteshelf**, the personality lives **on each notebook**, not on the app. Each notebook has a **cover** and **paper**, and planners and journals are **templates**. **Stickers** go on any page. The app itself is a clean light/dark interface.
- Today's 5 skins become **collections**: a set of matching covers, paper colors and an ink palette that a notebook can use.
- Content is made in four kinds: **covers, papers, templates, sticker packs**. All four are sold the same way: free, in **Pro**, or as a **pack** bought once.
- Only free content ships inside the app. Everything else is **downloaded**, so new designs go live without an app update.
- **Unlike Noteshelf**, packs can also be bought one at a time, as well as through the subscription.

---

## 1. What Noteshelf does, and what we copy

| In Noteshelf 3 | In Jotswift |
|---|---|
| Shelf of notebooks shown with their covers; grid or list, large or small thumbnails; sort by last opened, modified, name or custom | **Copy.** The notebook list becomes a shelf of covers |
| Categories in the sidebar, and groups (nested as deep as you like) for notebooks; tags | **Copy** categories and groups. Tags come later |
| Many built-in covers; a photo as a cover (with Unsplash search); writing or doodling on a cover | **Copy** built-in covers and photo covers. Drawing on the cover comes later |
| Each notebook has a default paper; any single page can use a different template; favorite templates saved | **Copy** |
| Paper background: four preset colors or any color from a color wheel | **Copy** |
| **Templates** in the sidebar: 200+ planners, journals, trackers and study pages; stickers are browsed there too | **Copy** as a **Templates** screen (our store) |
| App appearance: light, dark or follow the system | **Copy.** The app interface stops changing per skin |
| Free: 3 notebooks, some templates. Premium: unlimited notebooks, all templates, handwriting recognition, backup, AI credits. Apple: $7.99/wk, $9.99/mo, $29.99/yr | **Similar.** Free has 3 notebooks (already in PLAN.md). **Pro** unlocks all Pro content. We keep $2.99/mo / $19.99/yr and **also** sell packs |

Things to check in Noteshelf on the iPad before building screens: the steps for creating a new notebook (cover, then paper, size, orientation), the paper choices (line styles, spacing, page sizes), how dated planners link between pages, and how stickers are placed and resized.

**Do not copy Noteshelf's artwork, template designs, names or icons.** We copy how it works and how it's organized. All covers, papers, templates and stickers are our own (or licensed).

---

## 2. The four kinds of content

| Kind | What it is | Made from | Usually |
|---|---|---|---|
| **Cover** | The front of a notebook on the shelf and when opened | One image (or a color, a pattern or the user's photo) | Free colors; art covers in packs |
| **Paper** | The background of a normal page: color, ruling and spacing | A small JSON description, plus an optional texture image | Free basics; textured papers in packs |
| **Template** | A designed page or set of pages: planners, journals, trackers, study pages, music paper | A PDF, plus a JSON file with its tappable links | Some free; most Pro or in packs |
| **Sticker pack** | Images to place, move and resize on a page | Transparent WebP images | One free pack; others in packs |

**Paper (basic, free):** blank, lined, narrow lined, grid, dotted, plus music staves and Cornell notes. The colors are white, cream, gray and dark, or any color. There are three line spacings. Today's `paper` block in the manifest already covers most of this.

**Templates in detail.** A **dated planner** is a template whose pages link to each other (year → month → week → day, with tabs down the side). The links are areas on the page saved in the template's JSON. Tapping one jumps to that page. The pages are a PDF because:
- planner designers already work in PDF, which is how Noteshelf-style planners are sold,
- Jotswift draws PDFs anyway once **PDF import** (PLAN.md Phase 5) is built, so it's one feature, not two,
- a dated planner is generated once per year, when the user picks the year and start day.

Live widgets stay separate. The **daily planner page** from PLAN.md §8, with tasks and events from the calendar, is still built in code. Template art can decorate it.

**Collections** (today's skins) group matching content, for example the *Botanical* collection:
- 3 covers (sage, terracotta, leaf print)
- 2 papers (cream dotted, cream lined with a sage margin)
- a weekly planner template
- a botanical sticker pack
- an ink palette that is offered while writing in those notebooks

A collection is what the store shows as one card and, if paid, sells as one pack.

**Example launch lineup**
| Collection | Contents | Sold as |
|---|---|---|
| Basics | 12 color covers, all basic papers, To-do and Meeting notes templates, 1 sticker pack | Free, bundled |
| Classic, Kraft, Pastel, Minimal Dark | Covers + papers + ink palette (from today's skins) | Free, bundled |
| Botanical, Parchment, Blueprint | Covers, papers, a planner, stickers | $2.99 each, or $5.99 for all 3 |
| 2027 Planner | Dated yearly planner (linked year/month/week/day), 3 cover choices | Pro, or $3.99 |
| Study Pack | Cornell, lecture, flashcard and exam-prep templates | Pro, or $1.99 |

---

## 3. The app's own appearance

- The interface (sidebar, toolbars, menus) uses one neutral design in **light or dark**, following the system or chosen in Settings, like Noteshelf.
- Skins stop recoloring the interface. A notebook's look comes from its cover and paper. While writing, the pen palette offers the notebook's collection colors first.
- The existing `SkinEngine` code keeps building the interface theme, but from just two built-in themes (light and dark). Its paper and ink parts become the **Paper** and **ink palette** of the content model.
- **Optional later:** an accent color picker for the interface, which is cheap and stays separate from content.

---

## 4. Notebooks, pages and the shelf

**Changes to the data model** (see PLAN.md §4)

```
users/{uid}/notebooks/{id}
  title, categoryId, groupId?, order, createdAt, updatedAt, lastOpenedAt
  cover:  { kind: color|art|photo, color?, coverId?, photoPath? }
  paper:  { paperId? | custom: {color, pattern, spacing}, size: letter|a4|a5|phone, orientation }
  collectionId?                       # for the pen palette

users/{uid}/pages/{pageId}
  … as today, plus:
  paper?:     same shape as above      # this page differs from the notebook
  template?:  { templateId, version, pdfPage }   # page comes from a template

users/{uid}/categories/{id}  title, order
users/{uid}/groups/{id}      title, categoryId, parentGroupId?, order
users/{uid}/favorites        templateIds[], paperIds[]
```

Photo covers are stored in Cloud Storage under the user's folder.

**Screens**
- **Shelf** (replaces the notebook list): covers in a grid or list, sort menu, and a category sidebar on tablet and web.
- **New notebook:** pick a cover, then a paper or template, then size and orientation. It works the same way on phone, tablet and web.
- **Page menu:** change the paper or template for this page, and add a page from a template.
- **Templates** (the store): sections for Planners, Journals, Study, Papers, Covers and Stickers, plus Collections, Pro and Owned. Every item has a preview, and **Try it** opens a sample page without buying.
- **Stickers:** a tray in the page toolbar showing owned packs. A placed sticker is an `element` on the page, which PLAN.md §4 already has.

---

## 5. The catalog: one listing format for every kind

Each item has its **files** (made by the design team) and a **listing** (how it's sold). They are kept separate so that one item can be free, in Pro and in a pack without changing the item itself.

```jsonc
// Firestore: catalog/{itemId}   (free items: assets/catalog/<id>.json in the app)
{
  "id": "botanical_weekly_2027",
  "kind": "template",                  // cover | paper | template | stickers | collection
  "name": "Botanical Weekly Planner 2027",
  "version": 2,                        // bump on any change; devices re-download
  "collectionId": "botanical",
  "category": "planners",              // for store sections
  "tags": ["weekly", "dated", "light"],
  "unlock": {
    "free": false,
    "pro": true,                       // included with Jotswift Pro
    "products": ["pack_botanical"]     // also sold in the Botanical pack
  },
  "visibility": "public",              // hidden | testers | public | retired
  "releasedAt": "2026-11-01",
  "minAppVersion": "1.2.0",
  "files": {
    "pack": "catalog/botanical_weekly_2027/2/pack.zip",
    "sha256": "…",
    "bytes": 4100000,
    "preview": "catalog/botanical_weekly_2027/2/preview.webp"
  }
}
```

What's in each `pack.zip`:
| Kind | Files |
|---|---|
| Cover | `cover.webp` (1536×2048) |
| Paper | `paper.json` (color, pattern, spacing, margin) + optional `texture.webp` (512 px seamless tile) |
| Template | `template.pdf` + `template.json` (page names, link areas, how to generate dated pages) |
| Stickers | `stickers/*.webp` (at most 1024 px each) + `stickers.json` (names, default sizes) |
| Collection | `collection.json`: lists its item ids + the ink palette. A collection is a listing that points to other items |

Rules that matter:
- **`retired` hides an item but never takes it away.** Notebooks already using a cover or template keep working.
- **Pages keep the template version they were made with.** A new template version is used only for new pages, so a user's writing never shifts on a page they've already filled.
- **Older apps are safe.** An app skips items with a newer `minAppVersion`.
- **Size budget:** at most 5 MB per pack, except templates (at most 25 MB).

---

## 6. Downloading and offline use

1. The app listens to the Firestore `catalog`, together with the bundled free items. Store pages use the small preview images only.
2. A pack downloads when it's first used, for example when a notebook is created with that cover. The app checks the download against `sha256`, unpacks it and keeps it on the device. The web caches it in the browser.
3. Once a notebook uses a pack, it stays on the device, so notebooks work offline.
4. Previews can be seen by anyone. Full packs can only be downloaded by a signed-in user who may use them: Storage security rules check the user's entitlements in Firestore.
5. **If an item can't be used** (offline before the first download, refunded, Pro ended), what's already written is never hidden. Pages keep their template and paper. The user just can't start *new* notebooks or pages with that item until it's usable again. This is kinder than switching their notebooks back to plain paper.

---

## 7. Selling

### Products
| Product | Price (USD) | Store type | Product id |
|---|---|---|---|
| Small pack (sticker pack, study pack) | $1.99 | Non-consumable | `pack_<id>` |
| Collection pack (covers + papers + planner + stickers) | $2.99 | Non-consumable | `pack_<collection>` |
| Dated planner (one year) | $3.99 | Non-consumable | `planner_<id>_<year>` |
| Bundle (several collections) | $5.99 | Non-consumable | `bundle_<id>` |
| Jotswift Pro | $2.99/mo, $19.99/yr, 7-day trial on yearly | Subscription | `pro_monthly`, `pro_yearly` |

This keeps the pricing in PLAN.md §7, with planners and sticker packs added. For comparison, Noteshelf charges $29.99/yr on Apple, and Etsy sells Noteshelf-compatible planners for about $1–7.

**Naming products.** Apple never lets a product id be reused, even after it's deleted. So ids follow the item id exactly and are never renamed.

**Pro includes:** unlimited notebooks, every item marked `pro`, a new collection or planner each month, handwriting search (later) and backup. This mirrors what Noteshelf Premium includes.

### What the account stores
```
users/{uid}.entitlements          (written only by the Cloud Function)
  pro: true
  proUntil: 2027-10-14
  products: ["pack_botanical", "planner_botanical_2027"]
  grants:   ["study_pack"]         // items given for free (promos, support)
```

The account stores the products a user bought, and the app works out which items they unlock. A user can use an item if any one of these is true:
- it is free
- the user has Pro and the item is marked `pro`
- the user owns one of the products in the item's `unlock` list
- the item is in `grants`

An item inside an owned collection is unlocked too. RevenueCat needs only **one** entitlement, `pro`. Packs arrive as ordinary purchases with their product id.

### How a purchase flows
1. On iOS and Android the app buys through Apple or Google with RevenueCat. On the web it uses RevenueCat Web Billing (Stripe). The RevenueCat user id is the Firebase uid.
2. RevenueCat calls a webhook, and a Cloud Function updates `users/{uid}.entitlements`. It adds the product on a purchase and removes it on a refund. It sets `pro`/`proUntil` from subscription events.
3. The item unlocks on every device and on the web through Firestore. Right after a purchase, the app also trusts RevenueCat's receipt on that device, so the unlock doesn't wait for the webhook.
4. **Restore Purchases** is on the Templates screen (Apple requires it).

### Policies to decide now
| Question | Recommendation |
|---|---|
| A packed collection gains new items later | **Yes for collections, no for bundles.** Adding a cover to Botanical later is a nice surprise for owners. Bundles stay fixed once sold. |
| Pro items sold on their own? | **Yes, from the start**, as packs. This is the difference from Noteshelf, and the reason to sell packs at all. |
| Pro ends | Notebooks and pages already made keep their covers, papers and templates. Only *new* use of Pro items is locked (§6). |
| Family Sharing (Apple) | **On** for packs. Apple doesn't allow turning it off later, so decide before the first pack goes on sale. |
| Free set | Basics + the four current free skins as collections. Enough to feel generous, like Noteshelf's free tier. |

### App Store / Play rules
- The **first** in-app purchase must be submitted for review with an app version. Later products can be reviewed on their own.
- Create each paid item's product in App Store Connect, Play Console and RevenueCat before making it public. A listing can stay `hidden` until then.
- Inside the iOS and Android apps, digital items are sold only through Apple and Google. Check the current rules before linking to web purchases.

---

## 8. Making and releasing content

The source files live in the repo under `catalog/<id>/`, so every change is reviewed.

1. **Make it:** design the cover, paper, template or stickers, and write the listing.
2. **Check it** with `tool/catalog_check`: sizes and dimensions, PDF page count, links that point to real pages, contrast for papers (the rules in content.md), and preview renders. It runs in CI.
3. **Publish to testers** with `tool/publish_catalog <id> --testers`. It zips, uploads and writes the listing as `testers`.
4. **Set up products** for paid items, and wait for Apple's review.
5. **Release** with `tool/publish_catalog <id> --public`.

**What to measure:** previews opened, "Try it" taps, purchases and **use** (notebooks made with a cover, pages made from a template). Use shows what to make more of.

---

## 9. Order of work

The file-by-file build plan is in [noteshelf-implementation.md](noteshelf-implementation.md).

| Step | What | Replaces in PLAN.md |
|---|---|---|
| **1. Shelf and covers** | Shelf screen, categories and groups, cover per notebook (colors + bundled art covers + photo), new-notebook flow. Interface switches to neutral light/dark. | Phase 2 "tablet sidebar", Phase 1 skin picker |
| **2. Paper** | Paper per notebook and per page, the basic paper set, color picker, favorites. Current skins become free collections. | Phase 2 "page templates" |
| **3. Catalog and downloads** | Firestore catalog, Storage packs, download cache, `tool/catalog_check`, `tool/publish_catalog`. Prove it with **free** downloaded covers and papers. | Phase 1 "skin catalog" |
| **4. Stickers** | Sticker tray, placing, moving and resizing; one free pack. | Phase 2 "image insert" (same element code) |
| **5. Templates** | PDF page rendering, `template.json` links, dated planner generation. This also builds the base for PDF import. | Pulls part of Phase 5 "PDF import" earlier |
| **6. Store** | Templates screen as a store, RevenueCat, webhook, entitlements, restore, first paid packs and a planner. | Phase 4 |
| **7. Grow** | Monthly Pro drops, yearly planners, drawing on covers, tags, Unsplash covers, interface accent color. | Phase 5 |

---

## 10. Decisions needed

The recommendations above stand unless changed:
1. **Skins become per-notebook collections, and the interface becomes plain light/dark**, like Noteshelf. This is the biggest change from PLAN.md.
2. Packs are sold individually as well as through Pro.
3. Templates are PDFs with a links file.
4. Collections can grow; bundles can't.
5. Family Sharing is on for packs.
6. Pro stays at $19.99/yr (below Noteshelf's $29.99), or matches it.
