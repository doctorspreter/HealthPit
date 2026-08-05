//
//  HealthpitAPI.swift
//  Healthpit
//
//  Wohin die App sendet: direkt an Home Assistant, abgesichert ueber einen
//  Long-Lived Access Token. Home Assistant erkennt am Token, welcher Benutzer
//  sendet, und legt dessen Entitaeten getrennt an — die App muss ihre Identitaet
//  nicht selbst behaupten.
//

import Foundation

enum HealthpitAPI {
    /// Pfadpraefix der Integration.
    static let prefix = "api/healthpit/v1"

    /// Standardport von Home Assistant.
    static let defaultPort = "8123"

    static func path(_ path: String) -> String {
        "\(prefix)/\(path)"
    }

    /// Endpunkt, an dem sich pruefen laesst, ob die Gegenstelle antwortet.
    /// Er ist authentifiziert, ein Probelauf braucht also den Token.
    static var probePath: String { path("status") }
}
