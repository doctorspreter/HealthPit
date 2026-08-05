//
//  WorkoutFormatting.swift
//  Healthpit
//

import Foundation

func parseTrendDate(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: text)
}

/// Gewicht in der eingestellten Einheit. Der Parameter bleibt in Kilogramm –
/// gespeichert wird durchgaengig metrisch.
func formatKg(_ value: Double) -> String {
    WorkoutUnits.weight(kg: value)
}

func formatWorkoutDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes >= 60 {
        return L10n.format("%lld Std %lld Min", Int64(minutes / 60), Int64(minutes % 60))
    }
    return L10n.format("%lld Min", Int64(minutes))
}
