//
//  AppLanguage.swift
//  Healthpit
//
//  Persistierte Sprachauswahl fuer die gesamte SwiftUI-Oberflaeche.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case simplifiedChinese = "zh-Hans"

    nonisolated static let storageKey = "appLanguage"

    var id: String { rawValue }

    nonisolated var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Systemstandard"
        case .german: return "Deutsch"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .simplifiedChinese: return "简体中文"
        }
    }

    static func from(_ rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }
}

enum L10n {
    nonisolated private static let supportedLanguageIDs = ["de", "en", "es", "fr", "zh-Hans"]

    nonisolated static var selectedLanguage: AppLanguage {
        UserDefaults.standard.string(forKey: AppLanguage.storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    nonisolated static var locale: Locale {
        selectedLanguage.locale
    }

    /// Lokalisiert auch dynamische Modelltexte, die SwiftUI als `String`
    /// (und nicht als `LocalizedStringKey`) erhaelt.
    nonisolated static func string(_ key: String) -> String {
        let selected = selectedLanguage

        if selected == .german {
            return key
        }
        guard selected != .system,
              let path = Bundle.main.path(forResource: selected.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    /// Erkennt auch Texte, die in einer frueher gewaehlten Sprache im Cache
    /// gespeichert wurden, und uebersetzt sie in die aktuell gewaehlte Sprache.
    nonisolated static func stringResolvingStoredTranslation(_ value: String) -> String {
        let direct = string(value)
        if direct != value { return direct }

        for languageID in supportedLanguageIDs {
            guard let path = Bundle.main.path(forResource: languageID, ofType: "lproj"),
                  let bundle = Bundle(path: path),
                  let url = bundle.url(forResource: "Localizable", withExtension: "strings"),
                  let data = try? Data(contentsOf: url),
                  let table = try? PropertyListSerialization.propertyList(from: data,
                                                                          options: [],
                                                                          format: nil) as? [String: String],
                  let sourceKey = table.first(where: { $0.value == value })?.key else {
                continue
            }
            return string(sourceKey)
        }

        return value
    }
}
