"""Writes the store listings for the paid calendar templates.

  python3 tool/make_calendar_listings.py

The templates themselves are drawn by the app (see
lib/features/calendar/templates/calendar_template.dart); a listing is just
a name, a template id and how to unlock it, so the Templates store can
show and sell it. Writes catalog/calendar_<id>/listing.json for each paid
template, keeping existing versions. Check and publish with
tool/catalog.py.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DART = ROOT / "lib/features/calendar/templates/calendar_template.dart"

# id, name and tags; the product is read from the Dart file.
TEMPLATES = {
    "paper": ("Paper Planner", ["paper", "cream", "serif", "hand-drawn"]),
    "wall": ("Wall Calendar", ["wall calendar", "illustrated", "monthly art"]),
    "botanical": ("Botanical", ["green", "leaves", "calm"]),
    "pastel": ("Pastel", ["pastel", "rainbow", "cute"]),
    "bold": ("Bold Modern", ["bold", "modern", "minimal"]),
    "chalkboard": ("Chalkboard", ["chalk", "green", "doodles"]),
    "seasons": ("Seasons", ["seasonal", "illustrated", "colourful"]),
}


def products():
    """Template id -> product id, as the app has them."""
    text = DART.read_text()
    found = {}
    for block in re.split(r"CalendarTemplate\(", text)[1:]:
        tid = re.search(r"id: '([a-z0-9_]+)'", block)
        pid = re.search(r"productId: '([a-z0-9_]+)'", block)
        if tid and pid:
            found[tid.group(1)] = pid.group(1)
    return found


def main():
    by_id = products()
    for tid, (name, tags) in TEMPLATES.items():
        product = by_id[tid]
        folder = ROOT / "catalog" / f"calendar_{tid}"
        folder.mkdir(parents=True, exist_ok=True)
        listing = {
            "kind": "calendar",
            "name": f"{name} calendar",
            "version": 1,
            "unlock": {"pro": True, "products": [product]},
            "templateId": tid,
            "category": "calendars",
            "tags": tags,
        }
        path = folder / "listing.json"
        if path.exists():
            listing["version"] = json.loads(path.read_text()).get("version", 1)
        path.write_text(json.dumps(listing, indent=2) + "\n")
        print(f"calendar_{tid}: {product}")


if __name__ == "__main__":
    main()
