//
//  BridgeSettings.swift
//  Healthpit
//
//  Zentrale Keys fuer die Home-Assistant-Bridge-Einstellungen.
//

import Foundation

enum BridgeSettings {
    nonisolated static let baseURLKey = "bridgeBaseURL"
    nonisolated static let localConnectionEnabledKey = "bridgeLocalConnectionEnabled"
    nonisolated static let localHostKey = "bridgeLocalHost"
    nonisolated static let localPortKey = "bridgeLocalPort"
    nonisolated static let usernameKey = "bridgeUsername"
    nonisolated static let apiTokenKey = "bridgeApiToken"
    nonisolated static let otpCodeKey = "bridgeOtpCode"
    nonisolated static let otpSecretKey = "bridgeOtpSecret"
    nonisolated static let sessionTokenKey = "bridgeSessionToken"
    nonisolated static let sessionExpiresAtKey = "bridgeSessionExpiresAt"
    // The bridge a session was issued by. A session from a different bridge is
    // worthless, so the settings screen can tell the user to reconnect instead
    // of claiming a connection that no longer applies.
    nonisolated static let sessionEndpointKey = "bridgeSessionEndpoint"
    nonisolated static let deviceIDKey = "bridgeDeviceID"
    nonisolated static let syncEnabledKey = "bridgeSyncEnabled"
    nonisolated static let syncIntervalKey = "bridgeSyncInterval"
    nonisolated static let lastSyncDateKey = "bridgeLastSyncDate"
    nonisolated static let lastLocalRefreshDateKey = "lastLocalRefreshDate"
    nonisolated static let appleHealthWorkoutUploadCutoffKey = "bridgeAppleHealthWorkoutUploadCutoff"
    nonisolated static let appleHealthWorkoutPackageCursorKey = "bridgeAppleHealthWorkoutPackageCursor"
    nonisolated static let hiddenHealthWorkoutIDsKey = "hiddenHealthWorkoutIDs"

    nonisolated static let backgroundTaskIdentifier = "com.tauwe.HealthApp.bridge-sync"
}
