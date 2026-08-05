//
//  HealthCategory.swift
//  Healthpit
//
//  Oberste Gliederungsebene der App: die sieben Datenkategorien aus PLAN.md
//  (Abschnitt 2). Jede Kategorie liefert Titel, SF-Symbol und Akzentfarbe für
//  Dashboard-Karten und Navigation.
//

import SwiftUI

/// Eine fachliche Gruppe von Gesundheitsdaten (Dashboard-Kachel + Detailbereich).
enum HealthCategory: String, CaseIterable, Identifiable, Sendable {
    case activity
    case workouts
    case heart
    case sleep
    case body
    case nutrition
    case vitals
    case cycle

    var id: String { rawValue }

    /// Anzeigename für UI (deutsch).
    var title: String {
        switch self {
        case .activity:  return L10n.string("Aktivität")
        case .workouts:  return L10n.string("Workouts")
        case .heart:     return L10n.string("Herz")
        case .sleep:     return L10n.string("Schlaf")
        case .body:      return L10n.string("Körper")
        case .nutrition: return L10n.string("Ernährung")
        case .vitals:    return L10n.string("Vitalwerte")
        case .cycle:     return L10n.string("Zyklus")
        }
    }

    /// SF-Symbol für Kachel/Navigation.
    var systemImage: String {
        switch self {
        case .activity:  return "figure.walk"
        case .workouts:  return "figure.run"
        case .heart:     return "heart.fill"
        case .sleep:     return "bed.double.fill"
        case .body:      return "figure.arms.open"
        case .nutrition: return "fork.knife"
        case .vitals:    return "lungs.fill"
        case .cycle:     return "drop.circle.fill"
        }
    }

    /// Akzentfarbe gemäß Design-System (PLAN.md Abschnitt 7).
    var tint: Color {
        switch self {
        case .activity:  return .orange
        case .workouts:  return .green
        case .heart:     return .pink
        case .sleep:     return .indigo
        case .body:      return .purple
        case .nutrition: return .teal
        case .vitals:    return .cyan
        case .cycle:     return .red
        }
    }
}
