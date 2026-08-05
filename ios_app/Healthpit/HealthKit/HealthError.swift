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
        case .authorizationFailed:
            return L10n.string("Der Zugriff auf Apple Health wurde nicht erteilt. Bitte in den iOS-Einstellungen unter Datenschutz › Health prüfen.")
        case .queryFailed:
            return L10n.string("Die Daten konnten nicht aus Apple Health gelesen werden.")
        }
    }

    /// Der zugrunde liegende Fehler – fuer Protokoll und Detailzeile.
    ///
    /// Bewusst nicht in `errorDescription`: Foundation uebersetzt ihn nach der
    /// *Geraete*sprache und wuerde die App-Sprache damit unterlaufen.
    var technicalDetail: String? {
        switch self {
        case .healthDataUnavailable:
            return nil
        case .authorizationFailed(let error), .queryFailed(let error):
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
    }
}
