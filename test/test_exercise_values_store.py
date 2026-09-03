"""Every attribute the store reads must be one the store has.

This exists because ``exercise_values`` read ``self._data``, which does not
exist — the store keeps its buckets in ``self._users``. The payload tests could
not see it: the mistake only surfaced when Home Assistant set up the sensor
platform, and there it took every entity down with it. No entities meant the
history import answered 409 for a sensor that had never been created.

Home Assistant is not importable here, so this reads the source. That is enough
to catch a wrong attribute, which is the mistake that actually happened.
"""

from __future__ import annotations

import ast
from pathlib import Path

_STORE = Path(__file__).parents[1] / "custom_components" / "healthpit" / "store.py"
_TREE = ast.parse(_STORE.read_text(encoding="utf-8"))


def _store_class() -> ast.ClassDef:
    for node in _TREE.body:
        if isinstance(node, ast.ClassDef) and node.name.endswith("Store"):
            return node
    raise AssertionError("no store class found")


def _assigned_attributes(cls: ast.ClassDef) -> set[str]:
    """Attributes the class ever assigns to self."""
    found = set()
    for node in ast.walk(cls):
        if isinstance(node, ast.Attribute) and isinstance(node.ctx, ast.Store):
            if isinstance(node.value, ast.Name) and node.value.id == "self":
                found.add(node.attr)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Attribute):
            target = node.target
            if isinstance(target.value, ast.Name) and target.value.id == "self":
                found.add(target.attr)
    return found


def _read_attributes(cls: ast.ClassDef) -> set[str]:
    return {
        node.attr
        for node in ast.walk(cls)
        if isinstance(node, ast.Attribute)
        and isinstance(node.ctx, ast.Load)
        and isinstance(node.value, ast.Name)
        and node.value.id == "self"
    }


def test_the_store_only_reads_attributes_it_owns():
    cls = _store_class()
    assigned = _assigned_attributes(cls)
    methods = {
        node.name
        for node in cls.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    unknown = {
        attr
        for attr in _read_attributes(cls)
        if attr.startswith("_") and attr not in assigned and attr not in methods
    }

    assert not unknown, f"reads attributes it never assigns: {sorted(unknown)}"


def test_exercise_values_exists_and_reads_the_user_buckets():
    cls = _store_class()
    method = next(
        (
            node
            for node in cls.body
            if isinstance(node, ast.FunctionDef) and node.name == "exercise_values"
        ),
        None,
    )
    assert method is not None, "the sensors call exercise_values"

    source = ast.unparse(method)
    assert "self._users" in source, source
