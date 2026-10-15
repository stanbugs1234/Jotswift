"""Spread planners: landscape two-page layouts with rainbow tabs. Layouts
are named "<module>.<function>"; each module lists titles in TITLES."""

import importlib

MODULES = ["notes"]


def get(name):
    """(layout function, default title) for [name]."""
    module, _, fn = name.partition(".")
    if module not in MODULES:
        raise SystemExit(f"Unknown spread module: {module}")
    mod = importlib.import_module(f"spreads.{module}")
    if not hasattr(mod, fn):
        raise SystemExit(f"Unknown spread layout: {name}")
    f = getattr(mod, fn)
    return f, mod.TITLES.get(f, fn.replace("_", " ").capitalize())
