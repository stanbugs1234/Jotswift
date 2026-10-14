# Making a skin

A skin is a folder with a `manifest.json` file. No code changes are needed to add one.

```
assets/skins/
  catalog.json          ← lists skin ids in the order shown in the app
  classic/
    manifest.json
  my_new_skin/
    manifest.json
```

## Steps

1. Copy an existing skin folder (e.g. `assets/skins/classic/`) to `assets/skins/<your_id>/`.
   The id may only contain lowercase letters, digits and `_`.
2. Edit `manifest.json` (fields below). Set `"id"` to the folder name.
3. Add the id to `assets/skins/catalog.json`.
4. Add `- assets/skins/<your_id>/` under `assets:` in `pubspec.yaml`.
5. Add the id to the skin lists in `test/core/skins/bundled_skins_test.dart` and `test/goldens/skins_golden_test.dart`.
6. Run the checks:
   ```sh
   flutter test                                   # the manifest is valid and the colors are readable
   flutter test --tags golden --update-goldens    # creates test/goldens/skins/<id>.png
   ```
   Open the new screenshot in `test/goldens/skins/` and check it looks right.
7. Try it in the app: **Settings → Skins**, then tap your skin.

If a step is missed, the tests say which one.

## manifest.json

```jsonc
{
  "schemaVersion": 1,            // always 1 for now
  "id": "botanical",             // same as the folder name
  "version": 1,                  // bump whenever you change the skin
  "name": "Botanical",           // shown in the app
  "description": "Sage greens and terracotta on cream, for calm, leafy pages.",
  "tier": "paid",                // "free", "paid" (sold on its own) or "pro" (included with Motley Pro)
  "productId": "skin_botanical", // store product id; required when tier is "paid"
  "brightness": "light",         // "light" or "dark"

  "colors": {                    // "#RRGGBB" or "#AARRGGBB"
    "primary": "#4F7B5A",        // buttons, selected tabs, headings in the accent font
    "onPrimary": "#FFFFFF",      // text and icons on primary
    "secondary": "#D98E73",      // highlights, second event color
    "onSecondary": "#2B2B2B",    // text on secondary
    "background": "#EEF1E8",     // behind pages
    "surface": "#FBF8F1",        // cards, nav bar, sidebar
    "onSurface": "#2B2B2B",      // main text color
    "outline": "#A9B8A0",        // borders
    "error": "#B3261E"
  },

  "paper": {
    "color": "#FBF8F1",          // page color
    "lineColor": "#D8D2C4",      // ruling / grid / dot color
    "marginColor": "#E8A0A0",    // optional left margin line (lined paper only)
    "pattern": "dot",            // "blank", "lined", "grid" or "dot"
    "spacing": 26                // distance between lines or dots (8–200)
  },

  "inkColors": ["#2B2B2B", "#4F7B5A", "#D98E73", "#8A6FB0", "#C9A227"],
                                 // pen palette; the first is the default pen

  "typography": {                // any family from fonts.google.com
    "heading": "Cormorant Garamond",
    "body": "Inter",
    "accent": "Dancing Script"   // decorative font for planner and list headers
  },

  "cornerRadius": 16,            // roundness of pages, cards and buttons
  "stickers": []                 // reserved for sticker packs (not used yet)
}
```

## Readability rules (checked by the tests)

These follow the WCAG AA contrast guidelines so text stays easy to read:

| Pair | Minimum contrast |
|---|---|
| `onSurface` on `surface`, `background` and `paper.color` | 4.5 : 1 |
| `onPrimary` on `primary` | 4.5 : 1 |
| `onSecondary` on `secondary` | 3 : 1 |
| First ink color on `paper.color` | 4.5 : 1 |

If a test fails, darken or lighten one of the two colors. Any online contrast checker (e.g. webaim.org/resources/contrastchecker) shows the ratio.

## Tips

- Keep `lineColor` faint. It should guide handwriting, not compete with it.
- Choose ink colors that look different from each other and from `lineColor`.
- Dark skins: use a slightly lighter `paper.color` than `background` so pages stand out.
- Fonts download on first use. If a family name is misspelled, the app falls back to the default font, so check the name on fonts.google.com.

## Coming later

- **Paid skins downloaded on demand**: paid skins will live in Firebase Storage and be listed in a Firestore `skins` catalog instead of being bundled. The manifest format stays the same.
- **Texture images, page template art and stickers**: `paper.texture` and `stickers` are already in the format for when artwork is ready.
