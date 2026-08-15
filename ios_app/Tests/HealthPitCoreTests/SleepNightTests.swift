//
//  SleepNightTests.swift
//  HealthPitCoreTests
//
//  Nachgerechnet an der Nacht vom 11. auf den 12. August 2026, die in Apple
//  Health so aussieht:
//
//      Zeit im Bett   6 Std 32 Min
//      Schlafdauer    6 Std 17 Min
//      Verlauf        etwa 22:00 bis 04:30, vier kurze Wachphasen
//
//  Die Vorgaengerfassung zeigte dafuer 2 Std 31 Min Schlaf bei 7 Std 41 Min
//  Bettzeit. Beide Abweichungen haben hier ihren Test.
//

import Foundation
import XCTest
@testable import HealthPitCore

final class SleepNightTests: XCTestCase {

    private let watch = "com.apple.health.ABC123"
    private let phone = "com.apple.Health"

    /// 11.08.2026, Ortszeit.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 11) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func sample(_ kind: SleepSampleInput.Kind,
                        _ start: Date,
                        _ end: Date,
                        source: String? = nil) -> SleepSampleInput {
        SleepSampleInput(kind: kind, start: start, end: end,
                         provider: .appleHealth, sourceAppID: source ?? watch)
    }

    /// Die Nacht der Uhr: 22:00 bis 04:30, dazwischen Phasen und vier
    /// Wachfenster von zusammen 15 Minuten.
    private func recordedNight() -> [SleepSampleInput] {
        [
            sample(.core,  at(22, 0),  at(23, 30)),
            sample(.deep,  at(23, 30), at(0, 45, day: 12)),
            sample(.awake, at(0, 45, day: 12), at(0, 50, day: 12)),
            sample(.rem,   at(0, 50, day: 12), at(1, 40, day: 12)),
            sample(.core,  at(1, 40, day: 12), at(2, 30, day: 12)),
            sample(.awake, at(2, 30, day: 12), at(2, 35, day: 12)),
            sample(.deep,  at(2, 35, day: 12), at(3, 20, day: 12)),
            sample(.rem,   at(3, 20, day: 12), at(4, 25, day: 12)),
            sample(.awake, at(4, 25, day: 12), at(4, 30, day: 12))
        ]
    }

    func testTheWholeNightCountsNotOnlyThePartAfterMidnight() throws {
        let nights = SleepNightBuilder.nights(from: recordedNight())
        let night = try XCTUnwrap(nights.first)

        // 22:00 bis 04:30 sind 6 Std 30 Min Spanne, davon 15 Minuten wach.
        XCTAssertEqual(night.start, at(22, 0))
        XCTAssertEqual(night.end, at(4, 30, day: 12))
        XCTAssertEqual(night.asleep, 6 * 3600 + 15 * 60, accuracy: 60,
                       "Der Teil vor Mitternacht gehört dazu")
        XCTAssertEqual(night.awake, 15 * 60, accuracy: 1)
        XCTAssertEqual(night.timeInBed, 6 * 3600 + 30 * 60, accuracy: 60)
    }

    /// Der Fehler der Vorgaengerfassung: gelesen wurde nur der Kalendertag.
    ///
    /// HealthKit liefert dabei jede Probe, die den Tag beruehrt – die Phase
    /// von 23:30 bis 00:45 kommt also mit. Verloren geht, was vollstaendig
    /// davor liegt, hier die 90 Minuten ab 22:00. Wer frueher zu Bett geht,
    /// verliert entsprechend mehr; so werden aus einer Nacht zwei Stunden.
    func testReadingOnlyTheCalendarDayLosesMostOfTheNight() throws {
        let midnight = at(0, 0, day: 12)
        let afterMidnightOnly = recordedNight().filter { $0.end > midnight }
        let truncated = try XCTUnwrap(SleepNightBuilder.nights(from: afterMidnightOnly).first)
        let complete = try XCTUnwrap(SleepNightBuilder.nights(from: recordedNight()).first)

        XCTAssertLessThan(truncated.asleep, complete.asleep)
        XCTAssertEqual(complete.asleep - truncated.asleep, 90 * 60, accuracy: 60,
                       "Genau die 90 Minuten vor Mitternacht fehlen")
    }

    func testAwakePhasesDoNotEndTheNight() throws {
        let nights = SleepNightBuilder.nights(from: recordedNight())
        XCTAssertEqual(nights.count, 1,
                       "Vier Wachfenster ergeben eine Nacht, nicht fünf")
    }

    /// Der zweite Fehler: Bettzeit von der einen Quelle, Phasen von der
    /// anderen. Getrennt gezaehlt bleibt jede Aufzeichnung fuer sich stimmig.
    func testTwoSourcesStayTwoRecordings() throws {
        var samples = recordedNight()
        // Das Telefon meldet nur ein langes „im Bett“ von 21:00 bis 04:41.
        samples.append(sample(.inBed, at(21, 0), at(4, 41, day: 12), source: phone))

        let nights = SleepNightBuilder.nights(from: samples)
        XCTAssertEqual(nights.count, 2)

        let watchNight = try XCTUnwrap(nights.first { $0.sourceAppID == watch })
        let phoneNight = try XCTUnwrap(nights.first { $0.sourceAppID == phone })

        XCTAssertEqual(watchNight.asleep, 6 * 3600 + 15 * 60, accuracy: 60)
        XCTAssertEqual(watchNight.timeInBed, 6 * 3600 + 30 * 60, accuracy: 60)

        // Die reine Bettzeit-Aufzeichnung hat keinen Schlaf – und verdirbt
        // damit auch keine Rechnung mehr.
        XCTAssertEqual(phoneNight.asleep, 0)
        XCTAssertEqual(phoneNight.timeInBed, 7 * 3600 + 41 * 60, accuracy: 60)
    }

    func testNightsAreAssignedToTheDayTheyEndOn() throws {
        let interval = DateInterval(start: at(0, 0, day: 12), end: at(0, 0, day: 13))
        let nights = SleepNightBuilder.nights(from: recordedNight(), endingIn: interval)

        XCTAssertEqual(nights.count, 1, "Die Nacht endet am 12. und gehört zum 12.")

        // Eine Nacht, die am 11. endet, gehört nicht in dieses Fenster.
        let earlier = [sample(.core, at(22, 0, day: 9), at(5, 0, day: 10))]
        XCTAssertTrue(SleepNightBuilder.nights(from: earlier, endingIn: interval).isEmpty)
    }

    func testTheSessionIdentifierIsStableForTheSameRecording() throws {
        let first = try XCTUnwrap(SleepNightBuilder.nights(from: recordedNight()).first)
        let second = try XCTUnwrap(SleepNightBuilder.nights(from: recordedNight()).first)
        XCTAssertEqual(first.sessionID, second.sessionID)
    }
}
