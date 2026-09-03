//
//  BridgeUnit.swift
//  Healthpit
//
//  Welche Einheit ein Wert traegt, wenn er nach Home Assistant geht.
//
//  Die App reicht das eingestellte Masssystem durch: waehlt der Nutzer
//  imperial, kommen drueben lb und mi an. Damit Home Assistant den Wechsel
//  als Umrechnung derselben Groesse begreift und die Langzeitstatistik
//  mitzieht, statt sie zu zerreissen, braucht jeder solche Sensor eine
//  device_class — und ein Einheitenkuerzel in genau der Schreibweise, die
//  Home Assistant kennt ("mL", nicht "ml"; "fl. oz.", nicht "fl oz").
//
//  Uebersetzt wird hier nichts. Ein Sensorname oder eine Einheit, die sich
//  mit der App-Sprache aendert, ist genau der Fehler, den das hier behebt.
//

import Foundation

enum BridgeUnit {

    struct Descriptor: Sendable {
        /// Einheitenkuerzel, wie Home Assistant es schreibt.
        let symbol: String
        /// Home-Assistant-device_class, oder `nil` wenn es keine passende gibt.
        let deviceClass: String?
    }

    /// Beschreibung fuer ein Anzeige-Einheitenkuerzel der App.
    ///
    /// Unbekannte Kuerzel sind Wort-Einheiten wie "Schritte" oder "Etagen".
    /// Die gehen englisch hinaus und tragen keine device_class — Home
    /// Assistant kennt keine Groesse dafuer.
    static func descriptor(forDisplaySymbolKey key: String) -> Descriptor {
        table[key] ?? Descriptor(symbol: L10n.canonical(key), deviceClass: nil)
    }

    private static let table: [String: Descriptor] = [
        // Laenge
        "km":       Descriptor(symbol: "km",  deviceClass: "distance"),
        "m":        Descriptor(symbol: "m",   deviceClass: "distance"),
        "cm":       Descriptor(symbol: "cm",  deviceClass: "distance"),
        "mi":       Descriptor(symbol: "mi",  deviceClass: "distance"),
        "yd":       Descriptor(symbol: "yd",  deviceClass: "distance"),
        "ft":       Descriptor(symbol: "ft",  deviceClass: "distance"),
        "in":       Descriptor(symbol: "in",  deviceClass: "distance"),

        // Masse
        "kg":       Descriptor(symbol: "kg",  deviceClass: "weight"),
        "g":        Descriptor(symbol: "g",   deviceClass: "weight"),
        "mg":       Descriptor(symbol: "mg",  deviceClass: "weight"),
        "µg":       Descriptor(symbol: "µg",  deviceClass: "weight"),
        "lb":       Descriptor(symbol: "lb",  deviceClass: "weight"),

        // Temperatur
        "°C":       Descriptor(symbol: "°C",  deviceClass: "temperature"),
        "°F":       Descriptor(symbol: "°F",  deviceClass: "temperature"),

        // Geschwindigkeit
        "km/h":     Descriptor(symbol: "km/h", deviceClass: "speed"),
        "mph":      Descriptor(symbol: "mph",  deviceClass: "speed"),
        "m/s":      Descriptor(symbol: "m/s",  deviceClass: "speed"),
        "ft/s":     Descriptor(symbol: "ft/s", deviceClass: "speed"),

        // Volumen — Home Assistant schreibt Milliliter und Unzen anders als wir.
        "L":        Descriptor(symbol: "L",        deviceClass: "volume"),
        "ml":       Descriptor(symbol: "mL",       deviceClass: "volume"),
        "fl oz":    Descriptor(symbol: "fl. oz.",  deviceClass: "volume"),

        // Dauer
        "ms":       Descriptor(symbol: "ms",  deviceClass: "duration"),
        "min":      Descriptor(symbol: "min", deviceClass: "duration"),
        "h":        Descriptor(symbol: "h",   deviceClass: "duration"),

        // Sonstige mit passender Groesse
        "mmHg":     Descriptor(symbol: "mmHg", deviceClass: "pressure"),
        "W":        Descriptor(symbol: "W",    deviceClass: "power"),
        "dB":       Descriptor(symbol: "dB",   deviceClass: "sound_pressure"),

        // Ohne device_class: Home Assistant kennt keine passende Groesse.
        // Trotzdem hier, damit sie nicht durch die Uebersetzung laufen.
        "%":          Descriptor(symbol: "%",          deviceClass: nil),
        "bpm":        Descriptor(symbol: "bpm",        deviceClass: nil),
        "kcal":       Descriptor(symbol: "kcal",       deviceClass: nil),
        "mg/dL":      Descriptor(symbol: "mg/dL",      deviceClass: nil),
        "ml/kg·min":  Descriptor(symbol: "ml/kg·min",  deviceClass: nil),
        "L/min":      Descriptor(symbol: "L/min",      deviceClass: nil),
        "×":          Descriptor(symbol: "×",          deviceClass: nil),
        "":           Descriptor(symbol: "",           deviceClass: nil),
    ]
}
