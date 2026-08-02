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

func formatKg(_ value: Double) -> String {
    if value >= 1000 {
        return String(format: "%.1f t", value / 1000)
    }
    return String(format: "%.0f kg", value)
}

func formatWorkoutDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes >= 60 {
        return L10n.format("%lld Std %lld Min", Int64(minutes / 60), Int64(minutes % 60))
    }
    return L10n.format("%lld Min", Int64(minutes))
}
