//
//  HealthError.swift
//  Healthpit
//
//  Zentrales Fehler-Enum für die HealthKit-Schicht. Unterscheidet bewusst
//  zwischen echten Fehlern (Gerät nicht verfügbar, Query fehlgeschlagen) und
//  dem Normalfall "keine Daten" – Letzterer ist KEIN Fehler, sondern ein
//  Empty-State (siehe PLAN.md Abschnitt 9: Lesezugriff-Privacy).
//

import Foundation

enum HealthError: LocalizedError {
    /// HealthKit ist auf diesem Gerät grundsätzlich nicht verfügbar (z. B. iPad).
    case healthDataUnavailable
    /// Der Autorisierungs-Request schlug fehl.
    case authorizationFailed(underlying: Error)
    /// Eine Query schlug fehl.
    case queryFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return L10n.string("Health-Daten sind auf diesem Gerät nicht verfügbar.")
        case .authorizationFailed(let error):
            return L10n.format("Zugriff auf Apple Health fehlgeschlagen: %@", error.localizedDescription)
        case .queryFailed(let error):
            return L10n.format("Abfrage fehlgeschlagen: %@", error.localizedDescription)
        }
    }
}
