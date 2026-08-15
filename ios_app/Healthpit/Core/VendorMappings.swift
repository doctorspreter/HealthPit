//
//  VendorMappings.swift
//  HealthPitCore
//
//  Beispielhafte Mapping-Tabellen fuer Anbieter, deren Anbindung noch nicht
//  gebaut ist. Sie zeigen, was ein neuer Anbieter braucht: Zeilen in
//  `provider_metric_mapping` – und sonst nichts am Datenmodell.
//
//  Die Feldnamen folgen den oeffentlichen API-Bezeichnungen der Hersteller.
//  Sobald eine Anbindung wirklich gebaut wird, wandert die Liste in den
//  jeweiligen Adapter und wird dort vervollstaendigt.
//

import Foundation

enum GarminMapping {
    static let mappings: [ProviderMetricMapping] = [
        .init(provider: .garmin, sourceMetric: "dailies.steps", metricID: "ACT_STEPS",
              sourceUnit: .count, canonicalUnit: .count),
        .init(provider: .garmin, sourceMetric: "dailies.distanceInMeters", metricID: "ACT_DISTANCE",
              sourceUnit: .meter, canonicalUnit: .meter),
        .init(provider: .garmin, sourceMetric: "dailies.activeKilocalories", metricID: "NRG_ACTIVE",
              sourceUnit: .kilocalorie, canonicalUnit: .kilocalorie),
        .init(provider: .garmin, sourceMetric: "dailies.bmrKilocalories", metricID: "NRG_BASAL",
              sourceUnit: .kilocalorie, canonicalUnit: .kilocalorie),
        .init(provider: .garmin, sourceMetric: "heartRate", metricID: "HRT_RATE",
              sourceUnit: .beatsPerMinute, canonicalUnit: .beatsPerMinute),
        .init(provider: .garmin, sourceMetric: "restingHeartRateInBeatsPerMinute", metricID: "HRT_RESTING_RATE",
              sourceUnit: .beatsPerMinute, canonicalUnit: .beatsPerMinute),
        // Garmin rechnet die Variabilitaet als RMSSD – deshalb nicht auf
        // HRT_HRV_SDNN mappen, das waere eine andere Zahl.
        .init(provider: .garmin, sourceMetric: "hrvRmssd", metricID: "HRT_HRV_RMSSD",
              sourceUnit: .millisecond, canonicalUnit: .millisecond),
        .init(provider: .garmin, sourceMetric: "spo2", metricID: "RSP_SPO2",
              sourceUnit: .percent, canonicalUnit: .percent),
        .init(provider: .garmin, sourceMetric: "weightInGrams", metricID: "BDY_WEIGHT",
              sourceUnit: .gram, canonicalUnit: .kilogram),
        .init(provider: .garmin, sourceMetric: "bodyFatInPercent", metricID: "BDY_FAT",
              sourceUnit: .percent, canonicalUnit: .percent),
        .init(provider: .garmin, sourceMetric: "sleeps.deepSleepDurationInSeconds", metricID: "SLP_DEEP_DURATION",
              sourceUnit: .second, canonicalUnit: .second),
        .init(provider: .garmin, sourceMetric: "sleeps.remSleepInSeconds", metricID: "SLP_REM_DURATION",
              sourceUnit: .second, canonicalUnit: .second),
        // Proprietaer: bleibt bei Garmin und wird mit nichts verrechnet.
        .init(provider: .garmin, sourceMetric: "bodyBattery", metricID: "GAR_BODY_BATTERY",
              sourceUnit: .score, canonicalUnit: .score),
        .init(provider: .garmin, sourceMetric: "stressLevel", metricID: "GAR_STRESS_SCORE",
              sourceUnit: .score, canonicalUnit: .score)
    ]
}

enum HuaweiMapping {
    static let mappings: [ProviderMetricMapping] = [
        .init(provider: .huawei, sourceMetric: "com.huawei.continuous.steps.delta", metricID: "ACT_STEPS",
              sourceUnit: .count, canonicalUnit: .count),
        .init(provider: .huawei, sourceMetric: "com.huawei.continuous.distance.delta", metricID: "ACT_DISTANCE",
              sourceUnit: .meter, canonicalUnit: .meter),
        .init(provider: .huawei, sourceMetric: "com.huawei.instantaneous.heart_rate", metricID: "HRT_RATE",
              sourceUnit: .beatsPerMinute, canonicalUnit: .beatsPerMinute),
        .init(provider: .huawei, sourceMetric: "com.huawei.instantaneous.spo2", metricID: "RSP_SPO2",
              sourceUnit: .percent, canonicalUnit: .percent),
        .init(provider: .huawei, sourceMetric: "com.huawei.instantaneous.body_weight", metricID: "BDY_WEIGHT",
              sourceUnit: .kilogram, canonicalUnit: .kilogram),
        .init(provider: .huawei, sourceMetric: "com.huawei.continuous.calories_burnt", metricID: "NRG_ACTIVE",
              sourceUnit: .kilocalorie, canonicalUnit: .kilocalorie),
        .init(provider: .huawei, sourceMetric: "com.huawei.health.score", metricID: "HUA_HEALTH_SCORE",
              sourceUnit: .score, canonicalUnit: .score)
    ]
}
