//
//  ReleaseNotes.swift
//  Healthpit
//
//  Inhalt des Hinweisfensters beim ersten Start einer neuen Fassung.
//  Deutsch ist die Ausgangssprache; alles laeuft ueber L10n und liegt in den
//  Sprachdateien.
//

import Foundation

enum ReleaseNotes {
    nonisolated static let storageKey = "lastSeenReleaseNotesVersion"

    /// Die Fassung, zu der dieser Text gehoert.
    nonisolated static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Ob der Hinweis noch aussteht.
    nonisolated static func isUnseen(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: storageKey) != version
    }

    nonisolated static func markSeen(in defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: storageKey)
    }

    // MARK: Warnhinweis

    static var warningTitle: String {
        L10n.string("Wichtig: Diese Fassung braucht eine neue Installation")
    }

    /// Fett gesetzter Kern und normaler Rest, damit die Kernaussage nicht im
    /// Fliesstext untergeht.
    static var warningParagraphs: [(bold: String, rest: String)] {
        [
            (
                L10n.string("Die neue Integration „Healthpit“ muss über HACS installiert werden."),
                L10n.string("Sie ersetzt die bisherige „Healthpit Bridge“.")
            ),
            (
                L10n.string("Der Docker-Container und die Home-Assistant-App werden nicht mehr benötigt"),
                L10n.string("und können nach der Umstellung entfernt werden. Die App sendet ihre Daten direkt an Home Assistant.")
            ),
        ]
    }

    static var warningSteps: [String] {
        [
            L10n.string("In HACS die Integration Healthpit installieren, Home Assistant neu starten und sie unter Geräte & Dienste hinzufügen."),
            L10n.string("Im Home-Assistant-Profil einen Long-Lived Access Token anlegen und in der App unter Einstellungen ▸ Verbindung eintragen."),
            L10n.string("Alte „Healthpit Bridge“-Integration, Docker-Container und Add-on entfernen."),
        ]
    }

    // MARK: Neuerungen

    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    static var highlights: [Item] {
        [
            Item(symbol: "arrow.up.forward.app",
                 title: L10n.string("Direkt an Home Assistant"),
                 detail: L10n.string("Kein Container, kein Add-on, kein Zwischenstück.")),
            Item(symbol: "person.2",
                 title: L10n.string("Mehrere Personen im Haushalt"),
                 detail: L10n.string("Jede Person mit eigenem Token bekommt eigene Entitäten.")),
            Item(symbol: "drop",
                 title: L10n.string("Zyklus-Tracker"),
                 detail: L10n.string("Monatsweise Übersicht, Einträge erfassen und löschen.")),
            Item(symbol: "ruler",
                 title: L10n.string("Maßeinheiten umschaltbar"),
                 detail: L10n.string("Wie in Apple Health, metrisch oder imperial.")),
            Item(symbol: "map",
                 title: L10n.string("Laufstrecken als zusammenhängende Route"),
                 detail: L10n.string("Mit Streckenbild und Abruf als GPX, GeoJSON oder SVG.")),
            Item(symbol: "chart.line.uptrend.xyaxis",
                 title: L10n.string("Rückwirkende Statistiken"),
                 detail: L10n.string("Graphen decken die Vergangenheit ab statt bei null anzufangen.")),
            Item(symbol: "arrow.triangle.2.circlepath",
                 title: L10n.string("Statusanzeige beim Synchronisieren"),
                 detail: L10n.string("Jeder Schritt sichtbar, am Ende Ergebnis oder Grund des Fehlschlags.")),
            Item(symbol: "repeat",
                 title: L10n.string("Wiederkehrende Trainings"),
                 detail: L10n.string("Rhythmus und Enddatum beim manuellen Anlegen.")),
        ]
    }
}
