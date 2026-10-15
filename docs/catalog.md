# Publishing covers, papers and stickers

New covers, papers and sticker packs go live from Firebase, without an app update. Each item is a folder in `catalog/` and is published with `tool/catalog.py`.

## Make an item

```
catalog/
  night_sky/
    listing.json
    cover.webp      covers only: 1536 x 2048 WebP
    preview.webp    covers only: a small copy, at most 512 px wide
```

The folder name is the item's id: lowercase letters, digits and `_`. It can never be reused for something else.

**A cover's listing.json**
```jsonc
{
  "kind": "cover",
  "name": "Night Sky",           // shown under the preview
  "version": 1,                  // raise it whenever the images change
  "unlock": { "free": true },    // or { "pro": true } / { "products": ["pack_space"] }
  "category": "covers",
  "tags": ["dark", "illustrated"],
  "color": "#1C2A57"             // shown while the image loads
}
```

**A paper's listing.json:** no image files are needed. The paper lives in the listing.
```jsonc
{
  "kind": "paper",
  "name": "Sage Dot",
  "version": 1,
  "unlock": { "free": true },
  "paper": {
    "color": "#EEF2EA",
    "lineColor": "#AFC0A8",      // faint, but visible on the paper
    "marginColor": null,         // lined papers only, e.g. "#E8A0A0"
    "pattern": "dot",            // blank, lined, narrowLined, grid, dot, music, cornell
    "spacing": 26                // 8-200
  }
}
```

**A sticker pack:** the listing, plus `stickers.json`, a `stickers/` folder of transparent WebP images (at most 1024 px), and a `preview.webp`.
```jsonc
// listing.json
{ "kind": "stickers", "name": "Basics", "version": 1, "unlock": { "free": true } }

// stickers.json: every image in stickers/ must be listed
{ "stickers": [ { "file": "stickers/star.webp", "name": "Star" } ] }
```
Stickers are placed 240 page units wide (a page is about 1400 wide) and keep their image's shape.

## Check it

```sh
pip install pillow                 # once
python3 tool/catalog.py check      # every item; also runs in CI
```

The check covers sizes and formats, that the ruling can be seen, that the unlock is valid, and the size limit (5 MB per pack).

## Publish it

```sh
gcloud auth login                                   # once, as a Firebase project owner
python3 tool/catalog.py publish night_sky --testers # only tester accounts see it
python3 tool/catalog.py publish night_sky --public  # everyone sees it
```

Add `--dry-run` to see what would be uploaded. Publishing:
- uploads `pack.zip` and `preview.webp` to Storage under `catalog/<id>/<version>/`
- writes the listing to Firestore `catalog/<id>`

**Testers:** `python3 tool/catalog.py set-tester <uid> on` marks an account (find the uid under Firebase console → Authentication).

**Changing an item:** edit it, raise `version`, publish again. Devices download the new version the next time they show it. The tool refuses to republish changed files under the same version.

**Removing an item:** `python3 tool/catalog.py publish night_sky --retired`. It disappears from the pickers, and notebooks already using it keep it. `--hidden` hides it too (e.g. while its store products are set up).

## Who can download what

`firebase/storage.rules`: previews are open to anyone signed in. A pack can only be downloaded by someone who may use the item: it's free, they have Pro and it's a Pro item, they bought one of its products, or it was granted to them. Purchases come with the store (milestone 8).
