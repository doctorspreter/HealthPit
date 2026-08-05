//
//  BridgeErrorText.swift
//  Healthpit
//
//  Klartext-Meldungen fuer Bridge-Fehler – in der App-Sprache, nicht in der
//  Geraetesprache.
//
//  Foundation uebersetzt `localizedDescription` nach der *System*sprache. In
//  einer App mit eigener Sprachauswahl mischt das die Sprachen: wer die App auf
//  Englisch stellt, bekommt auf einem deutschen iPhone deutsche Netzwerkfehler.
//  Deshalb wird jeder Fehler hier einmal uebersetzt, bevor er in die
//  Oberflaeche geht.
//
//  Zweitens trennt diese Datei die Meldung von der Diagnose: der Anwender liest
//  einen vollstaendigen Satz, der technische Rest (roher Antwortkoerper,
//  Fehlercode) wandert in `technicalDetail` und dort in eine aufklappbare
//  Zeile. Frueher stand beides zusammen in einer Statuszeile.
//

import Foundation

enum BridgeErrorText {

    /// Die Meldung, die der Anwender lesen soll.
    static func message(for error: Error) -> String {
        if let bridgeError = error as? BridgeSyncError {
            return bridgeError.errorDescription ?? L10n.string("Die Bridge hat nicht wie erwartet geantwortet.")
        }
        if let urlError = error as? URLError {
            return transportFailure(urlError)
        }
        return L10n.string("Die Verbindung zur Bridge ist fehlgeschlagen.")
    }

    /// Technischer Zusatz fuer die Detailzeile – oder nil, wenn die Meldung
    /// schon alles sagt.
    static func technicalDetail(for error: Error) -> String? {
        if let bridgeError = error as? BridgeSyncError {
            return bridgeError.technicalDetail
        }
        if let urlError = error as? URLError {
            return "URLError \(urlError.code.rawValue)"
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    /// Klartext fuer einen Transportfehler (kein Netz, DNS, TLS, Zeitablauf …).
    static func transportFailure(_ error: URLError) -> String {
        let host = error.failingURL?.host() ?? ""

        switch error.code {
        case .notConnectedToInternet:
            return L10n.string("Dieses iPhone ist gerade mit keinem Netzwerk verbunden.")

        case .timedOut:
            return host.isEmpty
                ? L10n.string("Die Bridge hat nicht rechtzeitig geantwortet.")
                : L10n.format("Die Bridge unter %@ hat nicht rechtzeitig geantwortet.", host)

        case .cannotFindHost, .dnsLookupFailed:
            return host.isEmpty
                ? L10n.string("Die Bridge-Adresse ist im Netzwerk nicht auffindbar.")
                : L10n.format("Die Adresse %@ ist im Netzwerk nicht auffindbar. Bitte Hostnamen oder IP-Adresse prüfen.", host)

        case .cannotConnectToHost:
            // Bei einer Adresse im Heimnetz ist die häufigste Ursache nicht der
            // falsche Port, sondern die verweigerte Freigabe für das lokale Netzwerk.
            if isLocalNetworkHost(host) {
                return L10n.format("Unter %@ nimmt niemand Verbindungen an. Bitte prüfen, ob die Bridge läuft, ob der Port stimmt und ob Healthpit in den iOS-Einstellungen unter „Datenschutz & Sicherheit“ auf das lokale Netzwerk zugreifen darf.", host)
            }
            return host.isEmpty
                ? L10n.string("Unter der Bridge-Adresse nimmt niemand Verbindungen an.")
                : L10n.format("Unter %@ nimmt niemand Verbindungen an. Läuft die Bridge, und stimmt der Port?", host)

        case .networkConnectionLost:
            return L10n.string("Die Verbindung zur Bridge ist abgerissen.")

        case .secureConnectionFailed, .serverCertificateHasUnknownRoot:
            return host.isEmpty
                ? L10n.string("Die verschlüsselte Verbindung zur Bridge kam nicht zustande.")
                : L10n.format("Die verschlüsselte Verbindung zu %@ kam nicht zustande. Bitte das Zertifikat der Bridge prüfen.", host)

        case .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            return host.isEmpty
                ? L10n.string("Das Zertifikat der Bridge ist abgelaufen oder noch nicht gültig.")
                : L10n.format("Das Zertifikat von %@ ist abgelaufen oder noch nicht gültig.", host)

        case .serverCertificateUntrusted, .clientCertificateRejected:
            return host.isEmpty
                ? L10n.string("Dem Zertifikat der Bridge wird nicht vertraut.")
                : L10n.format("Dem Zertifikat von %@ wird nicht vertraut.", host)

        case .appTransportSecurityRequiresSecureConnection:
            return L10n.string("iOS hat die unverschlüsselte Verbindung blockiert. Für eine Adresse außerhalb des Heimnetzes ist https:// nötig.")

        case .badURL, .unsupportedURL:
            return L10n.string("Die eingetragene Bridge-Adresse ist keine gültige Adresse.")

        case .userAuthenticationRequired:
            return L10n.string("Die Bridge verlangt eine Anmeldung. Bitte Benutzernamen und API-Token prüfen.")

        case .cancelled:
            return L10n.string("Die Verbindung wurde abgebrochen.")

        default:
            return host.isEmpty
                ? L10n.string("Die Bridge ist nicht erreichbar.")
                : L10n.format("Die Bridge unter %@ ist nicht erreichbar.", host)
        }
    }

    /// Adresse im eigenen Netz? Deckt die RFC-1918-Bereiche, Link-Local und
    /// `.local`-Namen ab – genau die Faelle, fuer die iOS die Freigabe
    /// "Lokales Netzwerk" verlangt.
    static func isLocalNetworkHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower.hasSuffix(".local") || lower == "localhost" { return true }
        if lower.hasPrefix("10.") || lower.hasPrefix("192.168.") || lower.hasPrefix("169.254.") {
            return true
        }
        // 172.16.0.0 – 172.31.255.255
        guard lower.hasPrefix("172.") else { return false }
        let secondOctet = lower.dropFirst(4).prefix(while: { $0 != "." })
        guard let value = Int(secondOctet) else { return false }
        return (16...31).contains(value)
    }

    /// Was eine Antwort bedeutet, die keine Healthpit-Bridge geschickt haben kann.
    ///
    /// Der haeufigste Fall ist eine Adresse, hinter der ein Webserver oder ein
    /// Reverse Proxy sitzt: die Antwort ist dann HTML statt JSON.
    static func unexpectedResponse(host: String, statusCode: Int, body: Data) -> String {
        let text = String(data: body.prefix(200), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if text.hasPrefix("<") {
            return L10n.format("Unter %@ antwortet ein Webserver, aber keine Healthpit-Bridge. Bitte Adresse und Port prüfen.", host)
        }
        if text.isEmpty {
            return L10n.format("Die Bridge unter %@ hat eine leere Antwort geschickt (HTTP %lld).", host, Int64(statusCode))
        }
        return L10n.format("Die Bridge unter %@ hat eine unerwartete Antwort geschickt (HTTP %lld).", host, Int64(statusCode))
    }

    /// Rohe Antwort fuer die Detailzeile, gekuerzt und einzeilig.
    static func responseSnippet(_ body: Data) -> String? {
        guard let text = String(data: body.prefix(300), encoding: .utf8) else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }
}
