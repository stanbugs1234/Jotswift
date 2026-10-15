"""Page layouts by category. A layout is a function returning (page, title);
packs name them "<module>.<function>", e.g. "study.vocabulary". "core.*" are
the layouts in page_layouts.py that every collection's page pack uses."""

import page_layouts
from layouts import starter, study, wellness, work

MODULES = {
    "core": page_layouts,
    "starter": starter,
    "study": study,
    "work": work,
    "wellness": wellness,
}


def get(name):
    """The layout function called [name]."""
    module, _, fn = name.partition(".")
    if module not in MODULES or not hasattr(MODULES[module], fn):
        raise SystemExit(f"Unknown layout: {name}")
    return getattr(MODULES[module], fn)
