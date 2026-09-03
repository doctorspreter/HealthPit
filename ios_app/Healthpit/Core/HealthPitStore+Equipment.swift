//
//  HealthPitStore+Equipment.swift
//  HealthPitCore
//

import Foundation

extension HealthPitStore {

    func equipment(includeRetired: Bool = true,
                   userID: String = HealthPitUser.local) throws -> [Equipment] {
        let sql = includeRetired
            ? "SELECT * FROM equipment WHERE user_id = ? AND deleted_at IS NULL ORDER BY in_use_from DESC;"
            : "SELECT * FROM equipment WHERE user_id = ? AND deleted_at IS NULL AND retired_at IS NULL ORDER BY in_use_from DESC;"
        return try database.query(sql, [.text(userID)]).compactMap(Equipment.init(row:))
    }

    func upsertEquipment(_ item: Equipment,
                         userID: String = HealthPitUser.local,
                         provider: ProviderCode = .healthPit) throws {
        let now = Date()
        try database.run("""
            INSERT INTO equipment
                (equipment_id, user_id, kind, name, in_use_from, retired_at,
                 is_automatic, replace_after_km, replace_after_days,
                 service_every_km, last_service_km, last_service_at, notes,
                 origin_provider, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(equipment_id) DO UPDATE SET
                kind             = excluded.kind,
                name             = excluded.name,
                in_use_from      = excluded.in_use_from,
                retired_at       = excluded.retired_at,
                is_automatic     = excluded.is_automatic,
                replace_after_km = excluded.replace_after_km,
                replace_after_days = excluded.replace_after_days,
                service_every_km = excluded.service_every_km,
                last_service_km  = excluded.last_service_km,
                last_service_at  = excluded.last_service_at,
                notes            = excluded.notes,
                updated_at       = excluded.updated_at,
                deleted_at       = NULL;
            """, [
                .text(item.id), .text(userID), .text(item.kind.rawValue), .text(item.name),
                .date(item.inUseFrom), .date(item.retiredAt),
                .integer(item.isAutomatic ? 1 : 0),
                .double(item.replaceAfterKm), .int(item.replaceAfterDays),
                .double(item.serviceEveryKm),
                .double(item.lastServiceKm), .date(item.lastServiceAt),
                .text(item.notes), .text(provider.rawValue), .date(now), .date(now),
            ])
    }

    func deleteEquipment(id: String, userID: String = HealthPitUser.local) throws {
        try database.run("""
            UPDATE equipment SET deleted_at = ?, updated_at = ?
            WHERE equipment_id = ? AND user_id = ?;
            """, [.date(Date()), .date(Date()), .text(id), .text(userID)])
    }

    // MARK: Teile

    func equipmentComponents(userID: String = HealthPitUser.local) throws -> [EquipmentComponent] {
        try database.query("""
            SELECT * FROM equipment_component
            WHERE user_id = ? AND deleted_at IS NULL
            ORDER BY created_at;
            """, [.text(userID)])
            .compactMap(EquipmentComponent.init(row:))
    }

    func upsertEquipmentComponent(_ component: EquipmentComponent,
                                  userID: String = HealthPitUser.local) throws {
        let now = Date()
        try database.run("""
            INSERT INTO equipment_component
                (component_id, equipment_id, user_id, kind, name, action,
                 interval_km, interval_days, last_done_km, last_done_at,
                 notes, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(component_id) DO UPDATE SET
                equipment_id  = excluded.equipment_id,
                kind          = excluded.kind,
                name          = excluded.name,
                action        = excluded.action,
                interval_km   = excluded.interval_km,
                interval_days = excluded.interval_days,
                last_done_km  = excluded.last_done_km,
                last_done_at  = excluded.last_done_at,
                notes         = excluded.notes,
                updated_at    = excluded.updated_at,
                deleted_at    = NULL;
            """, [
                .text(component.id), .text(component.equipmentID), .text(userID),
                .text(component.kind.rawValue), .text(component.name),
                .text(component.action.rawValue),
                .double(component.intervalKm), .int(component.intervalDays),
                .double(component.lastDoneKm), .date(component.lastDoneAt),
                .text(component.notes), .date(now), .date(now),
            ])
    }

    func deleteEquipmentComponent(id: String, userID: String = HealthPitUser.local) throws {
        try database.run("""
            UPDATE equipment_component SET deleted_at = ?, updated_at = ?
            WHERE component_id = ? AND user_id = ?;
            """, [.date(Date()), .date(Date()), .text(id), .text(userID)])
    }

    // MARK: Abweichende Zuordnung einzelner Trainings

    /// Nur die Abweichungen: `nil` als Wert heisst „hier ausdruecklich nichts".
    func equipmentOverrides(userID: String = HealthPitUser.local) throws -> [String: String?] {
        var out: [String: String?] = [:]
        for row in try database.query(
            "SELECT workout_id, equipment_id FROM equipment_usage WHERE user_id = ?;",
            [.text(userID)]
        ) {
            guard let workout = row.string("workout_id") else { continue }
            out[workout] = row.string("equipment_id")
        }
        return out
    }

    func setEquipmentOverride(workoutID: String,
                              equipmentID: String?,
                              userID: String = HealthPitUser.local) throws {
        try database.run("""
            INSERT INTO equipment_usage (workout_id, user_id, equipment_id, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(workout_id, user_id) DO UPDATE SET
                equipment_id = excluded.equipment_id,
                updated_at   = excluded.updated_at;
            """, [.text(workoutID), .text(userID), .text(equipmentID), .date(Date())])
    }

    /// Zurueck zur automatischen Zuordnung.
    func clearEquipmentOverride(workoutID: String,
                                userID: String = HealthPitUser.local) throws {
        try database.run(
            "DELETE FROM equipment_usage WHERE workout_id = ? AND user_id = ?;",
            [.text(workoutID), .text(userID)])
    }
}

extension Equipment {
    nonisolated init?(row: SQLRow) {
        guard let id = row.string("equipment_id"),
              let kindRaw = row.string("kind"),
              let from = row.double("in_use_from") else {
            return nil
        }
        self.init(id: id,
                  kind: EquipmentKind(rawValue: kindRaw) ?? .other,
                  name: row.string("name") ?? "",
                  inUseFrom: Date(timeIntervalSince1970: from),
                  retiredAt: row.double("retired_at").map(Date.init(timeIntervalSince1970:)),
                  isAutomatic: (row.int("is_automatic") ?? 1) != 0,
                  replaceAfterKm: row.double("replace_after_km"),
                  replaceAfterDays: row.int("replace_after_days"),
                  serviceEveryKm: row.double("service_every_km"),
                  lastServiceKm: row.double("last_service_km") ?? 0,
                  lastServiceAt: row.double("last_service_at").map(Date.init(timeIntervalSince1970:)),
                  notes: row.string("notes") ?? "")
    }
}


extension EquipmentComponent {
    nonisolated init?(row: SQLRow) {
        guard let id = row.string("component_id"),
              let equipmentID = row.string("equipment_id"),
              let kindRaw = row.string("kind") else {
            return nil
        }
        // Erst anlegen, dann die Intervalle setzen: der Initialisierer setzt
        // fehlende Intervalle auf den Vorschlag der Art, und ein bewusst
        // abgewaehltes Intervall kaeme so beim Lesen zurueck.
        self.init(id: id,
                  equipmentID: equipmentID,
                  kind: ComponentKind(rawValue: kindRaw) ?? .custom,
                  name: row.string("name") ?? "",
                  action: row.string("action").flatMap(ComponentAction.init(rawValue:)),
                  lastDoneKm: row.double("last_done_km") ?? 0,
                  lastDoneAt: row.double("last_done_at").map(Date.init(timeIntervalSince1970:)),
                  notes: row.string("notes") ?? "")
        intervalKm = row.double("interval_km")
        intervalDays = row.int("interval_days")
    }
}
