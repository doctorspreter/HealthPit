#!/usr/bin/env python3
"""Erzeugt die Metrik-IDs, die GymPit braucht, aus HealthPits Katalog.

Der Katalog in `Healthpit/Core/MetricCatalog.swift` ist die einzige Quelle der
Namen. GymPit bekommt daraus eine erzeugte Datei — kein zweiter Katalog, keine
handgepflegte Kopie. Benennt jemand in HealthPit um oder loescht eine ID, faellt
sie hier heraus und GymPits Build bricht, statt dass die beiden Apps still
auseinanderlaufen.

Aufruf:
    python3 Scripts/export-metric-ids.py <ziel.swift>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Was GymPit liefert: Trainings, Kraftsaetze, Geraeteeinstellungen und die
# Kennzahlen, die dabei anfallen. Alles andere aus dem Katalog (Schlaf, Zyklus,
# Umgebung) geht GymPit nichts an und wuerde nur Rauschen erzeugen.
NEEDED_PREFIXES = ("WRK_", "HRT_RATE", "HRT_MAX_RATE", "NRG_ACTIVE", "ACT_DISTANCE")

CATALOG = Path(__file__).resolve().parent.parent / "Healthpit/Core/MetricCatalog.swift"

ENTRY = re.compile(
    r'MetricDefinition\("(?P<id>[A-Z][A-Z0-9_]+)"'
    r'(?P<rest>.*?)'
    r'(?=MetricDefinition\("|\n    \])',
    re.S,
)
NAME = re.compile(r'name:\s*"([^"]*)"')
UNIT = re.compile(r'canonicalUnit:\s*\.(\w+)')
VALUE_TYPE = re.compile(r'valueType:\s*\.(\w+)')


def entries() -> list[dict]:
    source = CATALOG.read_text(encoding="utf-8")
    found = []
    for match in ENTRY.finditer(source):
        metric_id = match.group("id")
        if not any(metric_id.startswith(prefix) for prefix in NEEDED_PREFIXES):
            continue
        rest = match.group("rest")
        found.append(
            {
                "id": metric_id,
                "name": (NAME.search(rest).group(1) if NAME.search(rest) else metric_id),
                "unit": (UNIT.search(rest).group(1) if UNIT.search(rest) else None),
                "type": (VALUE_TYPE.search(rest).group(1) if VALUE_TYPE.search(rest) else "number"),
            }
        )
    return sorted(found, key=lambda item: item["id"])


UNIT_CODES = {
    "second": "S", "meter": "M", "kilogram": "KG", "kilocalorie": "KCAL",
    "count": "CNT", "beatsPerMinute": "BPM", "percent": "PCT", "score": "SCORE",
    "kilometer": "KM", "watt": "W",
}


def swift(found: list[dict]) -> str:
    lines = [
        "//",
        "//  HealthPitMetricIDs.swift",
        "//  GymPit",
        "//",
        "//  ERZEUGT – NICHT BEARBEITEN.",
        "//",
        "//  Quelle: HealthPit, Healthpit/Core/MetricCatalog.swift",
        "//  Neu erzeugen: python3 Scripts/export-metric-ids.py <ziel>",
        "//",
        "//  Diese Datei ist der Vertrag zwischen GymPit und HealthPit. Beide",
        "//  benutzen dieselben Bezeichner, damit ein Wert unterwegs nicht",
        "//  umbenannt werden muss und in HealthPit auf der richtigen Entitaet",
        "//  landet.",
        "//",
        "",
        "import Foundation",
        "",
        "/// Ein Wert, wie HealthPit ihn kennt.",
        "struct HealthPitMetric: Hashable, Sendable {",
        "    /// Die zentrale, dauerhaft stabile Kennung.",
        "    let id: String",
        "    /// Kanonische Einheit; `nil` bei Text-, Enum- und Ja/Nein-Werten.",
        "    let unit: String?",
        "    /// Klartext, wie HealthPit ihn fuehrt.",
        "    let name: String",
        "}",
        "",
        "enum HealthPitMetricIDs {",
        "",
    ]
    for item in found:
        unit = f'"{UNIT_CODES[item["unit"]]}"' if item["unit"] in UNIT_CODES else "nil"
        constant = camel(item["id"])
        lines.append(f'    /// {item["name"]}')
        lines.append(
            f'    static let {constant} = HealthPitMetric(id: "{item["id"]}", '
            f'unit: {unit}, name: "{item["name"]}")'
        )
    lines += [
        "",
        "    /// Alles, was GymPit liefern kann – fuer Pruefungen und Anzeigen.",
        "    static let all: [HealthPitMetric] = [",
    ]
    lines += [f"        {camel(item['id'])}," for item in found]
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def camel(metric_id: str) -> str:
    parts = metric_id.lower().split("_")
    return parts[0] + "".join(part.capitalize() for part in parts[1:])


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    found = entries()
    if not found:
        print("Keine passenden Metriken gefunden – hat sich der Katalog geaendert?")
        return 1
    target = Path(sys.argv[1])
    target.write_text(swift(found), encoding="utf-8")
    print(f"{len(found)} Metriken nach {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
