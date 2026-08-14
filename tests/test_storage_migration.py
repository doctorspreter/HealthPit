"""The storage upgrade has to hook into Home Assistant the way it expects.

This exists because it did not: the migration was handed to ``Store`` as a
``migrate_func`` keyword, which looks plausible, imports fine and fails only
at setup time on a real Home Assistant — with the integration refusing to
load.

Home Assistant is not importable here (it needs a newer Python than the one
this repository is tested with), so these checks read the source. That is
enough to catch a wrong hook, which is the mistake that actually happened.
"""

import ast
from pathlib import Path

import pytest


_STORE = Path(__file__).parents[1] / "custom_components" / "healthpit" / "store.py"
_TREE = ast.parse(_STORE.read_text(encoding="utf-8"))


def _classes() -> dict[str, ast.ClassDef]:
    return {
        node.name: node for node in _TREE.body if isinstance(node, ast.ClassDef)
    }


def test_the_store_is_never_handed_a_migration_callback() -> None:
    """``Store.__init__`` takes no callback. Passing one breaks setup."""
    for node in ast.walk(_TREE):
        if not isinstance(node, ast.Call):
            continue
        for keyword in node.keywords:
            assert keyword.arg != "migrate_func", (
                "Store takes no migrate_func; override _async_migrate_func in a "
                "subclass instead"
            )


def test_the_migration_is_a_store_subclass() -> None:
    storage = _classes().get("HealthPitStorage")
    assert storage is not None, "the migration needs its own Store subclass"

    bases = [ast.unparse(base) for base in storage.bases]
    assert any(base.startswith("Store") for base in bases), bases


def test_the_hook_has_the_signature_home_assistant_calls() -> None:
    storage = _classes()["HealthPitStorage"]
    hooks = [
        node
        for node in storage.body
        if isinstance(node, ast.AsyncFunctionDef)
        and node.name == "_async_migrate_func"
    ]
    assert hooks, "_async_migrate_func is what Home Assistant calls"

    arguments = [argument.arg for argument in hooks[0].args.args]
    assert arguments == [
        "self",
        "old_major_version",
        "old_minor_version",
        "old_data",
    ], arguments


def test_the_store_is_built_from_the_subclass() -> None:
    source = _STORE.read_text(encoding="utf-8")
    assert "HealthPitStorage(" in source
    # The plain Store is only referenced as a type and as the base class.
    assert "= Store(" not in source


@pytest.mark.parametrize(
    "name", ["async_create_issue", "async_delete_issue"]
)
def test_the_repair_notice_uses_the_documented_helpers(name: str) -> None:
    issue = (
        Path(__file__).parents[1]
        / "custom_components"
        / "healthpit"
        / "compatibility_issue.py"
    ).read_text(encoding="utf-8")
    assert f"ir.{name}(" in issue
