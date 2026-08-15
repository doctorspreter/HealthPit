//
//  ProviderRegistry.swift
//  HealthPitCore
//
//  Zentrale Liste aller Anbieter. Ein neuer Anbieter braucht hier einen
//  Eintrag, ein Mapping und einen Adapter – am Datenmodell aendert sich nichts.
//

import Foundation

/// Was fuer ein System hinter einem Provider-Code steckt.
enum ProviderKind: String, Sendable, Codable {
    /// Geraetehersteller mit eigener Cloud (Garmin, Huawei, …).
    case vendor = "VENDOR"
    /// Plattform, die Daten vieler Hersteller buendelt (Apple Health).
    case platform = "PLATFORM"
    /// Ziel-/Quellsystem ohne eigene Messung (Home-Assistant-Bridge).
    case sink = "SINK"
    /// HealthPit selbst.
    case internalApp = "INTERNAL"
}

struct ProviderDefinition: Hashable, Sendable, Codable {
    let code: ProviderCode
    let name: String
    let kind: ProviderKind
    /// Kann HealthPit von dort lesen?
    let canRead: Bool
    /// Kann HealthPit dorthin zurueckschreiben?
    let canWrite: Bool
    /// Unterstuetzt das System einen eigenen Sync-Identifier oder ein
    /// Metadatenfeld, in das HealthPit die Observation ID legen kann?
    ///
    /// Ohne das faellt die Schleifenerkennung auf External Record IDs und
    /// Quellenerkennung zurueck.
    let supportsSyncIdentifier: Bool
    /// Vergibt das System stabile Record-IDs, die beim naechsten Abruf gleich
    /// bleiben? Bei `false` darf `external_record_id` nicht als Beweis gelten.
    let hasStableRecordIDs: Bool
    let isImplemented: Bool
}

struct ProviderRegistry: Sendable {
    private(set) var providersByCode: [ProviderCode: ProviderDefinition]

    init(providers: [ProviderDefinition] = ProviderRegistry.builtIn) {
        providersByCode = Dictionary(uniqueKeysWithValues: providers.map { ($0.code, $0) })
    }

    var all: [ProviderDefinition] {
        providersByCode.values.sorted { $0.code < $1.code }
    }

    func definition(_ code: ProviderCode) -> ProviderDefinition? {
        providersByCode[code]
    }

    func contains(_ code: ProviderCode) -> Bool {
        providersByCode[code] != nil
    }

    mutating func register(_ definition: ProviderDefinition) {
        providersByCode[definition.code] = definition
    }

    /// Welcher Anbieter steckt hinter dieser Quell-App?
    ///
    /// Apple Health nennt zu jedem Datensatz die App, die ihn geschrieben hat.
    /// Genau daran haengt die Unterscheidung zwischen Erzeuger und Lieferweg:
    /// Ein Wert, den die Garmin-App nach Apple Health legt, stammt von Garmin
    /// und kommt ueber Apple Health herein. Ohne diese Zuordnung stuende
    /// spaeter alles unter „Apple Health“, und ein Anbieterwechsel liesse den
    /// alten Bestand nicht mehr wiederfinden.
    ///
    /// Unbekannte Kennungen ergeben `nil` – dann gilt der einliefernde
    /// Anbieter als Erzeuger. Geraten wird nicht.
    static func provider(forBundleID bundleID: String?,
                         sourceName: String? = nil,
                         ownBundleID: String? = nil) -> ProviderCode? {
        guard let bundleID = bundleID?.lowercased(), !bundleID.isEmpty else { return nil }

        if let ownBundleID, bundleID == ownBundleID.lowercased() { return .healthPit }
        if GymPitMapping.isGymPitSource(bundleIdentifier: bundleID, sourceName: sourceName) {
            return .gymPit
        }

        for (prefix, provider) in bundleIDPrefixes where bundleID.hasPrefix(prefix) {
            return provider
        }
        return nil
    }

    /// Bekannte Quell-Apps. Praefixe, weil Apple die Uhr je Geraet mit eigener
    /// Kennung fuehrt (`com.apple.health.<UUID>`).
    static let bundleIDPrefixes: [(String, ProviderCode)] = [
        ("com.apple.health", .appleHealth),
        ("com.apple.workout", .appleHealth),
        ("com.garmin.connect", .garmin),
        ("com.huawei.health", .huawei),
        ("com.huawei.hwid", .huawei),
        ("com.sec.android.app.shealth", .samsung),
        ("com.samsung.shealth", .samsung),
        ("com.fitbit.", .fitbit),
        ("com.ouraring.", .oura),
        ("fi.polar.", .polar),
        ("com.polar.", .polar)
    ]

    static let builtIn: [ProviderDefinition] = [
        ProviderDefinition(code: .healthPit, name: "HealthPit", kind: .internalApp,
                           canRead: true, canWrite: true,
                           supportsSyncIdentifier: true, hasStableRecordIDs: true,
                           isImplemented: true),
        ProviderDefinition(code: .appleHealth, name: "Apple Health", kind: .platform,
                           canRead: true, canWrite: true,
                           supportsSyncIdentifier: true, hasStableRecordIDs: true,
                           isImplemented: true),
        ProviderDefinition(code: .gymPit, name: "GymPit", kind: .vendor,
                           canRead: true, canWrite: true,
                           supportsSyncIdentifier: true, hasStableRecordIDs: true,
                           isImplemented: true),
        ProviderDefinition(code: .homeAssistant, name: "Home Assistant Bridge", kind: .sink,
                           canRead: true, canWrite: true,
                           supportsSyncIdentifier: true, hasStableRecordIDs: true,
                           isImplemented: true),
        ProviderDefinition(code: .garmin, name: "Garmin", kind: .vendor,
                           canRead: true, canWrite: false,
                           supportsSyncIdentifier: false, hasStableRecordIDs: true,
                           isImplemented: false),
        ProviderDefinition(code: .huawei, name: "Huawei Health", kind: .vendor,
                           canRead: true, canWrite: true,
                           supportsSyncIdentifier: false, hasStableRecordIDs: true,
                           isImplemented: false),
        ProviderDefinition(code: .samsung, name: "Samsung Health", kind: .vendor,
                           canRead: true, canWrite: true,
                           supportsSyncIdentifier: false, hasStableRecordIDs: true,
                           isImplemented: false),
        ProviderDefinition(code: .fitbit, name: "Fitbit", kind: .vendor,
                           canRead: true, canWrite: false,
                           supportsSyncIdentifier: false, hasStableRecordIDs: true,
                           isImplemented: false),
        ProviderDefinition(code: .oura, name: "Oura", kind: .vendor,
                           canRead: true, canWrite: false,
                           supportsSyncIdentifier: false, hasStableRecordIDs: true,
                           isImplemented: false),
        ProviderDefinition(code: .polar, name: "Polar", kind: .vendor,
                           canRead: true, canWrite: false,
                           supportsSyncIdentifier: false, hasStableRecordIDs: true,
                           isImplemented: false)
    ]
}
