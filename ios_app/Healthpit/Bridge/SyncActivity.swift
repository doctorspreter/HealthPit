//
//  SyncActivity.swift
//  Healthpit
//
//  Was der Sync gerade tut. Vorher gab es nur einen Spinner und danach eine
//  Zahl; welcher Schritt gerade laeuft oder woran es scheiterte, war nicht zu
//  sehen.
//

import Foundation
import Observation

/// Ein Schritt des Synchronisierungsablaufs.
enum SyncStep: String, CaseIterable, Identifiable, Sendable {
    case metrics
    case uploadWorkouts
    case reconcile
    case downloadWorkouts
    case records

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metrics: return L10n.string("Messwerte senden")
        case .uploadWorkouts: return L10n.string("Workouts senden")
        case .reconcile: return L10n.string("Gelöschtes abgleichen")
        case .downloadWorkouts: return L10n.string("Workouts abholen")
        case .records: return L10n.string("Rekorde berechnen")
        }
    }
}

@MainActor
@Observable
final class SyncActivity {
    static let shared = SyncActivity()

    enum State: Equatable {
        case idle
        case running(SyncStep)
        case succeeded(count: Int)
        case failed(message: String)
    }

    private(set) var state: State = .idle
    /// Abgeschlossene Schritte, damit die Anzeige den Fortschritt zeigt und
    /// nicht nur den Augenblick.
    private(set) var finishedSteps: Set<SyncStep> = []

    private init() {}

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var currentStep: SyncStep? {
        if case .running(let step) = state { return step }
        return nil
    }

    func begin() {
        finishedSteps = []
        state = .running(.metrics)
    }

    func enter(_ step: SyncStep) {
        if let current = currentStep, current != step {
            finishedSteps.insert(current)
        }
        state = .running(step)
    }

    func succeed(count: Int) {
        if let current = currentStep {
            finishedSteps.insert(current)
        }
        state = .succeeded(count: count)
    }

    func fail(_ message: String) {
        state = .failed(message: message)
    }

    func reset() {
        state = .idle
        finishedSteps = []
    }
}
