//
//  HealthPitStore.swift
//  HealthPitCore
//
//  Die Datenbank hinter dem neuen Modell: Metric Registry, Provider,
//  Mappings, Observations, externe Referenzen, Workouts und das Sync-Log.
//
//  Liegt in derselben SQLite-Datei wie der bisherige `cache_entries`-Cache,
//  damit die Migration die alten Daten ohne Dateijonglage lesen kann.
//

import Foundation

actor HealthPitStore {

    /// Schemastand. Wird ueber `PRAGMA user_version` gefuehrt; jede Erhoehung
    /// braucht einen Zweig in `migrateSchema`.
    static let schemaVersion: Int32 = 2

    private let database: SQLiteDatabase
    private(set) var metricRegistry: MetricRegistry
    private(set) var providerRegistry: ProviderRegistry

    init(path: String,
         metricRegistry: MetricRegistry = MetricRegistry(),
         providerRegistry: ProviderRegistry = ProviderRegistry()) throws {
        let database = try SQLiteDatabase(path: path)
        self.database = database
        self.metricRegistry = metricRegistry
        self.providerRegistry = providerRegistry
        // Schema und Registry stehen, bevor der erste Aufrufer den Store
        // sieht. Statische Helfer, weil der Actor-Init keine isolierten
        // Methoden aufrufen darf.
        try Self.migrateSchema(in: database)
        try Self.seed(metricRegistry.all, providers: providerRegistry.all, in: database)
    }

    /// Standardpfad der App: dieselbe Datei, die der bisherige Cache nutzt.
    static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appending(path: "Database", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "healthpit.sqlite3")
    }

    // MARK: - Schema

    private static func migrateSchema(in database: SQLiteDatabase) throws {
        let currentVersion = try database.query("PRAGMA user_version;").first?.int("user_version") ?? 0
        guard currentVersion < Int(Self.schemaVersion) else { return }

        if currentVersion < 1 {
            try database.execute(Self.schemaV1)
        }
        if currentVersion < 2 {
            try database.execute(Self.schemaV2)
        }
        try database.execute("PRAGMA user_version = \(Self.schemaVersion);")
    }

    private static let schemaV1 = """
    CREATE TABLE IF NOT EXISTS metric_definition (
        metric_id            TEXT PRIMARY KEY NOT NULL,
        category             TEXT NOT NULL,
        name                 TEXT NOT NULL,
        description          TEXT NOT NULL DEFAULT '',
        value_type           TEXT NOT NULL,
        canonical_unit       TEXT,
        allowed_codes        TEXT,
        is_proprietary       INTEGER NOT NULL DEFAULT 0,
        proprietary_provider TEXT,
        status               TEXT NOT NULL DEFAULT 'ACTIVE',
        version              INTEGER NOT NULL DEFAULT 1,
        created_at           REAL NOT NULL,
        updated_at           REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS provider (
        code                    TEXT PRIMARY KEY NOT NULL,
        name                    TEXT NOT NULL,
        kind                    TEXT NOT NULL,
        can_read                INTEGER NOT NULL DEFAULT 1,
        can_write               INTEGER NOT NULL DEFAULT 0,
        supports_sync_identifier INTEGER NOT NULL DEFAULT 0,
        has_stable_record_ids   INTEGER NOT NULL DEFAULT 1,
        is_implemented          INTEGER NOT NULL DEFAULT 0,
        created_at              REAL NOT NULL,
        updated_at              REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS provider_metric_mapping (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        provider        TEXT NOT NULL,
        source_metric   TEXT NOT NULL,
        metric_id       TEXT NOT NULL,
        source_unit     TEXT,
        canonical_unit  TEXT,
        conversion_rule TEXT,
        value_mapping   TEXT,
        can_read        INTEGER NOT NULL DEFAULT 1,
        can_write       INTEGER NOT NULL DEFAULT 0,
        can_update      INTEGER NOT NULL DEFAULT 0,
        can_delete      INTEGER NOT NULL DEFAULT 0,
        mapping_version INTEGER NOT NULL DEFAULT 1,
        status          TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at      REAL NOT NULL,
        updated_at      REAL NOT NULL,
        UNIQUE(provider, source_metric, mapping_version)
    );

    CREATE TABLE IF NOT EXISTS health_observation (
        observation_id      TEXT PRIMARY KEY NOT NULL,
        user_id             TEXT NOT NULL,
        metric_id           TEXT NOT NULL,
        value_type          TEXT NOT NULL,
        value_numeric       REAL,
        value_text          TEXT,
        value_code          TEXT,
        value_boolean       INTEGER,
        unit                TEXT,
        source_value        REAL,
        source_unit         TEXT,
        start_time          REAL NOT NULL,
        end_time            REAL NOT NULL,
        timezone            TEXT,
        aggregation         TEXT NOT NULL,
        period_type         TEXT NOT NULL,
        origin_provider     TEXT NOT NULL,
        ingest_provider     TEXT NOT NULL,
        origin_external_id  TEXT,
        source_metric       TEXT,
        source_app_id       TEXT,
        source_device_id    TEXT,
        source_device_model TEXT,
        workout_id          TEXT,
        session_id          TEXT,
        version             INTEGER NOT NULL DEFAULT 1,
        review_state        TEXT NOT NULL DEFAULT 'OK',
        content_hash        TEXT NOT NULL,
        heuristic_key       TEXT NOT NULL,
        received_at         REAL NOT NULL,
        created_at          REAL NOT NULL,
        updated_at          REAL NOT NULL,
        deleted_at          REAL,
        metadata            TEXT,
        raw_payload         TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_observation_metric_time
        ON health_observation(user_id, metric_id, start_time);
    CREATE INDEX IF NOT EXISTS idx_observation_heuristic
        ON health_observation(user_id, heuristic_key);
    CREATE INDEX IF NOT EXISTS idx_observation_origin_external
        ON health_observation(user_id, origin_provider, origin_external_id);
    CREATE INDEX IF NOT EXISTS idx_observation_workout
        ON health_observation(workout_id);

    CREATE TABLE IF NOT EXISTS workout (
        workout_id          TEXT PRIMARY KEY NOT NULL,
        user_id             TEXT NOT NULL,
        sport_type          TEXT NOT NULL,
        title               TEXT,
        notes               TEXT,
        start_time          REAL NOT NULL,
        end_time            REAL NOT NULL,
        timezone            TEXT,
        origin_provider     TEXT NOT NULL,
        ingest_provider     TEXT NOT NULL,
        source_record_id    TEXT,
        source_app_id       TEXT,
        source_device_id    TEXT,
        source_device_model TEXT,
        version             INTEGER NOT NULL DEFAULT 1,
        created_at          REAL NOT NULL,
        updated_at          REAL NOT NULL,
        deleted_at          REAL,
        metadata            TEXT,
        raw_payload         TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_workout_time ON workout(user_id, start_time);

    -- Gemeinsame Referenztabelle fuer Observations und Workouts.
    -- Kein Fremdschluessel auf entity_id, weil sie auf zwei Tabellen zeigen
    -- kann; die Pflege laeuft ueber den Store, nicht ueber die Datenbank.
    CREATE TABLE IF NOT EXISTS external_reference (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id               TEXT NOT NULL,
        entity_type           TEXT NOT NULL,
        entity_id             TEXT NOT NULL,
        provider              TEXT NOT NULL,
        external_record_id    TEXT,
        sync_identifier       TEXT,
        sync_version          INTEGER,
        status                TEXT NOT NULL DEFAULT 'ACTIVE',
        exported_content_hash TEXT,
        first_seen_at         REAL NOT NULL,
        last_seen_at          REAL NOT NULL,
        imported_at           REAL,
        exported_at           REAL,
        deleted_at            REAL,
        metadata              TEXT,
        UNIQUE(user_id, provider, external_record_id),
        UNIQUE(user_id, provider, sync_identifier)
    );

    CREATE INDEX IF NOT EXISTS idx_reference_entity
        ON external_reference(entity_type, entity_id);
    CREATE INDEX IF NOT EXISTS idx_reference_provider_entity
        ON external_reference(provider, entity_type, entity_id);

    CREATE TABLE IF NOT EXISTS sync_event (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type        TEXT NOT NULL,
        entity_id          TEXT,
        provider           TEXT NOT NULL,
        direction          TEXT NOT NULL,
        action             TEXT NOT NULL,
        status             TEXT NOT NULL,
        external_record_id TEXT,
        created_at         REAL NOT NULL,
        completed_at       REAL,
        error_code         TEXT,
        error_message      TEXT,
        metadata           TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_sync_event_entity ON sync_event(entity_type, entity_id);
    CREATE INDEX IF NOT EXISTS idx_sync_event_created ON sync_event(provider, created_at);

    -- Merker fuer einmalige Datenmigrationen (Altbestand).
    CREATE TABLE IF NOT EXISTS migration_state (
        key        TEXT PRIMARY KEY NOT NULL,
        value      TEXT,
        applied_at REAL NOT NULL
    );
    """

    /// Schema v2: Wer darf welche Metrik liefern.
    private static let schemaV2 = """
    CREATE TABLE IF NOT EXISTS metric_source_policy (
        user_id       TEXT NOT NULL,
        metric_id     TEXT NOT NULL,
        provider      TEXT NOT NULL,
        -- Leerer String heisst: gilt fuer alle Quellen dieses Anbieters.
        source_app_id TEXT NOT NULL DEFAULT '',
        enabled       INTEGER NOT NULL DEFAULT 1,
        updated_at    REAL NOT NULL,
        PRIMARY KEY (user_id, metric_id, provider, source_app_id)
    );

    CREATE INDEX IF NOT EXISTS idx_policy_metric ON metric_source_policy(user_id, metric_id);

    -- Der Katalog fragt nach Metrik und Quelle; ohne diesen Index waere das
    -- ein voller Durchlauf ueber alle Messwerte.
    CREATE INDEX IF NOT EXISTS idx_observation_source
        ON health_observation(user_id, metric_id, origin_provider, ingest_provider, source_app_id);
    """

    // MARK: - Registry

    private static func seed(_ metrics: [MetricDefinition],
                             providers: [ProviderDefinition],
                             in database: SQLiteDatabase) throws {
        let now = Date()
        try database.transaction {
            for definition in metrics {
                try upsert(definition, at: now, in: database)
            }
            for provider in providers {
                try upsert(provider, at: now, in: database)
            }
        }
    }

    private static func upsert(_ definition: MetricDefinition,
                               at date: Date,
                               in database: SQLiteDatabase) throws {
        try database.run("""
        INSERT INTO metric_definition
            (metric_id, category, name, description, value_type, canonical_unit, allowed_codes,
             is_proprietary, proprietary_provider, status, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(metric_id) DO UPDATE SET
            category = excluded.category,
            name = excluded.name,
            description = excluded.description,
            value_type = excluded.value_type,
            canonical_unit = excluded.canonical_unit,
            allowed_codes = excluded.allowed_codes,
            is_proprietary = excluded.is_proprietary,
            proprietary_provider = excluded.proprietary_provider,
            status = excluded.status,
            version = excluded.version,
            updated_at = excluded.updated_at;
        """, [
            .text(definition.metricID.rawValue),
            .text(definition.category.rawValue),
            .text(definition.name),
            .text(definition.description),
            .text(definition.valueType.rawValue),
            .text(definition.canonicalUnit?.rawValue),
            .text(definition.allowedCodes.isEmpty ? nil : definition.allowedCodes.joined(separator: ",")),
            .bool(definition.isProprietary),
            .text(definition.proprietaryProvider?.rawValue),
            .text(definition.status.rawValue),
            .int(definition.version),
            .date(date),
            .date(date)
        ])
    }

    private static func upsert(_ provider: ProviderDefinition,
                               at date: Date,
                               in database: SQLiteDatabase) throws {
        try database.run("""
        INSERT INTO provider
            (code, name, kind, can_read, can_write, supports_sync_identifier,
             has_stable_record_ids, is_implemented, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(code) DO UPDATE SET
            name = excluded.name,
            kind = excluded.kind,
            can_read = excluded.can_read,
            can_write = excluded.can_write,
            supports_sync_identifier = excluded.supports_sync_identifier,
            has_stable_record_ids = excluded.has_stable_record_ids,
            is_implemented = excluded.is_implemented,
            updated_at = excluded.updated_at;
        """, [
            .text(provider.code.rawValue),
            .text(provider.name),
            .text(provider.kind.rawValue),
            .bool(provider.canRead),
            .bool(provider.canWrite),
            .bool(provider.supportsSyncIdentifier),
            .bool(provider.hasStableRecordIDs),
            .bool(provider.isImplemented),
            .date(date),
            .date(date)
        ])
    }

    /// Neue Metrik zur Laufzeit aufnehmen – etwa ein proprietaerer Score, den
    /// ein Adapter mitbringt.
    func registerMetric(_ definition: MetricDefinition) throws {
        metricRegistry.register(definition)
        try Self.upsert(definition, at: Date(), in: database)
    }

    func registerProvider(_ definition: ProviderDefinition) throws {
        providerRegistry.register(definition)
        try Self.upsert(definition, at: Date(), in: database)
    }

    func metricDefinition(_ metricID: MetricID) -> MetricDefinition? {
        metricRegistry.definition(metricID)
    }

    func knownMetricIDs() throws -> [String] {
        try database.query("SELECT metric_id FROM metric_definition ORDER BY metric_id;")
            .compactMap { $0.string("metric_id") }
    }

    // MARK: - Provider Mapping

    func upsertMapping(_ mapping: ProviderMetricMapping) throws {
        let now = Date()
        try database.run("""
        INSERT INTO provider_metric_mapping
            (provider, source_metric, metric_id, source_unit, canonical_unit, conversion_rule,
             value_mapping, can_read, can_write, can_update, can_delete, mapping_version, status,
             created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(provider, source_metric, mapping_version) DO UPDATE SET
            metric_id = excluded.metric_id,
            source_unit = excluded.source_unit,
            canonical_unit = excluded.canonical_unit,
            conversion_rule = excluded.conversion_rule,
            value_mapping = excluded.value_mapping,
            can_read = excluded.can_read,
            can_write = excluded.can_write,
            can_update = excluded.can_update,
            can_delete = excluded.can_delete,
            status = excluded.status,
            updated_at = excluded.updated_at;
        """, [
            .text(mapping.provider.rawValue),
            .text(mapping.sourceMetric),
            .text(mapping.metricID.rawValue),
            .text(mapping.sourceUnit?.rawValue),
            .text(mapping.canonicalUnit?.rawValue),
            .text(mapping.conversionRule),
            .text(JSONColumn.encode(mapping.valueMapping)),
            .bool(mapping.canRead),
            .bool(mapping.canWrite),
            .bool(mapping.canUpdate),
            .bool(mapping.canDelete),
            .int(mapping.mappingVersion),
            .text(mapping.status.rawValue),
            .date(now),
            .date(now)
        ])
    }

    func mappings(for provider: ProviderCode) throws -> [ProviderMetricMapping] {
        try database.query("""
        SELECT * FROM provider_metric_mapping
        WHERE provider = ? AND status = 'ACTIVE'
        ORDER BY source_metric, mapping_version DESC;
        """, [.text(provider.rawValue)]).compactMap(ProviderMetricMapping.init(row:))
    }

    func mapping(provider: ProviderCode, sourceMetric: String) throws -> ProviderMetricMapping? {
        try database.query("""
        SELECT * FROM provider_metric_mapping
        WHERE provider = ? AND source_metric = ? AND status = 'ACTIVE'
        ORDER BY mapping_version DESC LIMIT 1;
        """, [.text(provider.rawValue), .text(sourceMetric)])
            .compactMap(ProviderMetricMapping.init(row:))
            .first
    }

    // MARK: - Observations

    func insert(_ observation: HealthObservation) throws {
        try database.run("""
        INSERT INTO health_observation
            (observation_id, user_id, metric_id, value_type, value_numeric, value_text, value_code,
             value_boolean, unit, source_value, source_unit, start_time, end_time, timezone,
             aggregation, period_type, origin_provider, ingest_provider, origin_external_id,
             source_metric, source_app_id, source_device_id, source_device_model, workout_id,
             session_id, version, review_state, content_hash, heuristic_key, received_at,
             created_at, updated_at, deleted_at, metadata, raw_payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?, ?, ?);
        """, observation.bindings)
    }

    func update(_ observation: HealthObservation) throws {
        try database.run("""
        UPDATE health_observation SET
            user_id = ?, metric_id = ?, value_type = ?, value_numeric = ?, value_text = ?,
            value_code = ?, value_boolean = ?, unit = ?, source_value = ?, source_unit = ?,
            start_time = ?, end_time = ?, timezone = ?, aggregation = ?, period_type = ?,
            origin_provider = ?, ingest_provider = ?, origin_external_id = ?, source_metric = ?,
            source_app_id = ?, source_device_id = ?, source_device_model = ?, workout_id = ?,
            session_id = ?, version = ?, review_state = ?, content_hash = ?, heuristic_key = ?,
            received_at = ?, created_at = ?, updated_at = ?, deleted_at = ?, metadata = ?,
            raw_payload = ?
        WHERE observation_id = ?;
        """, Array(observation.bindings.dropFirst()) + [.text(observation.observationID.rawValue)])
    }

    func observation(_ id: ObservationID) throws -> HealthObservation? {
        try database.query("SELECT * FROM health_observation WHERE observation_id = ? LIMIT 1;",
                           [.text(id.rawValue)])
            .compactMap(HealthObservation.init(row:))
            .first
    }

    /// Alle Observations einer Metrik in einem Zeitraum. Geloeschte bleiben
    /// aussen vor, solange nicht ausdruecklich gewuenscht.
    func observations(metricID: MetricID,
                      from start: Date? = nil,
                      to end: Date? = nil,
                      userID: String = HealthPitUser.local,
                      includeDeleted: Bool = false) throws -> [HealthObservation] {
        var sql = "SELECT * FROM health_observation WHERE user_id = ? AND metric_id = ?"
        var bindings: [SQLValue] = [.text(userID), .text(metricID.rawValue)]
        if let start {
            sql += " AND end_time >= ?"
            bindings.append(.date(start))
        }
        if let end {
            sql += " AND start_time <= ?"
            bindings.append(.date(end))
        }
        if !includeDeleted {
            sql += " AND deleted_at IS NULL"
        }
        sql += " ORDER BY start_time;"
        return try database.query(sql, bindings).compactMap(HealthObservation.init(row:))
    }

    func observations(workoutID: WorkoutID) throws -> [HealthObservation] {
        try database.query("""
        SELECT * FROM health_observation
        WHERE workout_id = ? AND deleted_at IS NULL ORDER BY start_time;
        """, [.text(workoutID.rawValue)]).compactMap(HealthObservation.init(row:))
    }

    func observationCount(includeDeleted: Bool = false) throws -> Int {
        let sql = includeDeleted
            ? "SELECT COUNT(*) AS count FROM health_observation;"
            : "SELECT COUNT(*) AS count FROM health_observation WHERE deleted_at IS NULL;"
        return try database.query(sql).first?.int("count") ?? 0
    }

    /// Wie viele Messwerte je Erzeuger vorliegen.
    ///
    /// Die Datensicherung soll vor dem Export zeigen, was von wem stammt.
    /// Dafuer den gesamten Bestand zu laden, waere Verschwendung – zaehlen
    /// kann die Datenbank selbst.
    func observationCountsByOrigin(userID: String = HealthPitUser.local) throws -> [ProviderCode: Int] {
        try countsByOrigin(table: "health_observation", userID: userID)
    }

    func workoutCountsByOrigin(userID: String = HealthPitUser.local) throws -> [ProviderCode: Int] {
        try countsByOrigin(table: "workout", userID: userID)
    }

    /// Geloeschte Zeilen bleiben aussen vor: Sie reisen in der Datei mit,
    /// aber als Bestand anzuzeigen waeren sie irrefuehrend.
    private func countsByOrigin(table: String, userID: String) throws -> [ProviderCode: Int] {
        let rows = try database.query("""
        SELECT origin_provider AS provider, COUNT(*) AS count FROM \(table)
        WHERE user_id = ? AND deleted_at IS NULL GROUP BY origin_provider;
        """, [.text(userID)])
        var counts: [ProviderCode: Int] = [:]
        for row in rows {
            guard let raw = row.string("provider"),
                  let provider = ProviderCode(validating: raw) else { continue }
            counts[provider] = row.int("count") ?? 0
        }
        return counts
    }

    /// Alles, was dieser Nutzer hat – Grundlage der Sicherung.
    func allObservations(userID: String = HealthPitUser.local,
                         includeDeleted: Bool = true) throws -> [HealthObservation] {
        let sql = includeDeleted
            ? "SELECT * FROM health_observation WHERE user_id = ? ORDER BY start_time;"
            : "SELECT * FROM health_observation WHERE user_id = ? AND deleted_at IS NULL ORDER BY start_time;"
        return try database.query(sql, [.text(userID)]).compactMap(HealthObservation.init(row:))
    }

    func allReferences(userID: String = HealthPitUser.local) throws -> [ExternalReference] {
        try database.query("SELECT * FROM external_reference WHERE user_id = ? ORDER BY id;",
                           [.text(userID)])
            .compactMap(ExternalReference.init(row:))
    }

    func observations(reviewState: ReviewState) throws -> [HealthObservation] {
        try database.query("SELECT * FROM health_observation WHERE review_state = ? ORDER BY start_time;",
                           [.text(reviewState.rawValue)])
            .compactMap(HealthObservation.init(row:))
    }

    /// Kandidaten fuer die heuristische Erkennung – nur exakte Treffer des
    /// Schluessels, alles Weitere entscheidet der Import.
    func observations(heuristicKey: String,
                      userID: String = HealthPitUser.local) throws -> [HealthObservation] {
        try database.query("""
        SELECT * FROM health_observation
        WHERE user_id = ? AND heuristic_key = ? AND deleted_at IS NULL;
        """, [.text(userID), .text(heuristicKey)]).compactMap(HealthObservation.init(row:))
    }

    /// Suche nach der Record-ID des urspruenglichen Erzeugers – Stufe 3 der
    /// Import-Reihenfolge.
    func observations(originProvider: ProviderCode,
                      originExternalID: String,
                      userID: String = HealthPitUser.local) throws -> [HealthObservation] {
        try database.query("""
        SELECT * FROM health_observation
        WHERE user_id = ? AND origin_provider = ? AND origin_external_id = ? AND deleted_at IS NULL;
        """, [.text(userID), .text(originProvider.rawValue), .text(originExternalID)])
            .compactMap(HealthObservation.init(row:))
    }

    // MARK: - Workouts

    func insert(_ workout: StoredWorkout) throws {
        try database.run("""
        INSERT INTO workout
            (workout_id, user_id, sport_type, title, notes, start_time, end_time, timezone,
             origin_provider, ingest_provider, source_record_id, source_app_id, source_device_id,
             source_device_model, version, created_at, updated_at, deleted_at, metadata, raw_payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, workout.bindings)
    }

    func update(_ workout: StoredWorkout) throws {
        try database.run("""
        UPDATE workout SET
            user_id = ?, sport_type = ?, title = ?, notes = ?, start_time = ?, end_time = ?,
            timezone = ?, origin_provider = ?, ingest_provider = ?, source_record_id = ?,
            source_app_id = ?, source_device_id = ?, source_device_model = ?, version = ?,
            created_at = ?, updated_at = ?, deleted_at = ?, metadata = ?, raw_payload = ?
        WHERE workout_id = ?;
        """, Array(workout.bindings.dropFirst()) + [.text(workout.workoutID.rawValue)])
    }

    func workout(_ id: WorkoutID) throws -> StoredWorkout? {
        try database.query("SELECT * FROM workout WHERE workout_id = ? LIMIT 1;", [.text(id.rawValue)])
            .compactMap(StoredWorkout.init(row:))
            .first
    }

    func workouts(from start: Date? = nil,
                  to end: Date? = nil,
                  userID: String = HealthPitUser.local,
                  includeDeleted: Bool = false) throws -> [StoredWorkout] {
        var sql = "SELECT * FROM workout WHERE user_id = ?"
        var bindings: [SQLValue] = [.text(userID)]
        if let start {
            sql += " AND end_time >= ?"
            bindings.append(.date(start))
        }
        if let end {
            sql += " AND start_time <= ?"
            bindings.append(.date(end))
        }
        if !includeDeleted {
            sql += " AND deleted_at IS NULL"
        }
        sql += " ORDER BY start_time DESC;"
        return try database.query(sql, bindings).compactMap(StoredWorkout.init(row:))
    }

    /// Workouts, die dieser Erzeuger unter dieser Record-ID fuehrt.
    ///
    /// Damit findet ein Training, das ueber einen Umweg hereinkommt, sein
    /// Original – etwa eine GymPit-Einheit, die als Kopie in Apple Health
    /// liegt und die GymPit-ID mitbringt.
    func workouts(originProvider: ProviderCode,
                  sourceRecordID: String,
                  userID: String = HealthPitUser.local) throws -> [StoredWorkout] {
        try database.query("""
        SELECT * FROM workout
        WHERE user_id = ? AND origin_provider = ? AND source_record_id = ? AND deleted_at IS NULL
        ORDER BY start_time DESC;
        """, [.text(userID), .text(originProvider.rawValue), .text(sourceRecordID)])
            .compactMap(StoredWorkout.init(row:))
    }

    /// Trainings, die sich zeitlich mit dem gegebenen Fenster ueberschneiden.
    ///
    /// Grundlage der Erkennung „dieselbe Einheit, andere Quelle“: Health Sync,
    /// die Huawei-App und Apple selbst schreiben denselben Lauf jeweils als
    /// eigenen Datensatz mit eigener UUID. Ueber Zeit und Dauer ist er
    /// wiederzuerkennen, ueber die IDs nicht.
    func workouts(overlapping start: Date,
                  end: Date,
                  userID: String = HealthPitUser.local) throws -> [StoredWorkout] {
        try database.query("""
        SELECT * FROM workout
        WHERE user_id = ? AND deleted_at IS NULL
          AND start_time < ? AND end_time > ?
        ORDER BY start_time;
        """, [.text(userID), .date(end), .date(start)])
            .compactMap(StoredWorkout.init(row:))
    }

    func workoutCount(includeDeleted: Bool = false) throws -> Int {
        let sql = includeDeleted
            ? "SELECT COUNT(*) AS count FROM workout;"
            : "SELECT COUNT(*) AS count FROM workout WHERE deleted_at IS NULL;"
        return try database.query(sql).first?.int("count") ?? 0
    }

    // MARK: - External References

    @discardableResult
    func upsert(_ reference: ExternalReference) throws -> ExternalReference {
        var stored = reference
        if let existing = try existingReference(for: reference) {
            stored.id = existing.id
            try database.run("""
            UPDATE external_reference SET
                user_id = ?, entity_type = ?, entity_id = ?, provider = ?, external_record_id = ?,
                sync_identifier = ?, sync_version = ?, status = ?, exported_content_hash = ?,
                first_seen_at = ?, last_seen_at = ?, imported_at = ?, exported_at = ?,
                deleted_at = ?, metadata = ?
            WHERE id = ?;
            """, stored.bindings + [.integer(existing.id ?? 0)])
        } else {
            let rowID = try database.run("""
            INSERT INTO external_reference
                (user_id, entity_type, entity_id, provider, external_record_id, sync_identifier,
                 sync_version, status, exported_content_hash, first_seen_at, last_seen_at,
                 imported_at, exported_at, deleted_at, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, stored.bindings)
            stored.id = rowID
        }
        return stored
    }

    /// Findet die Zeile, die durch die Unique Constraints ohnehin dieselbe
    /// waere – erst ueber die externe ID, dann ueber unseren Sync-Marker,
    /// zuletzt ueber die Kombination aus Entitaet und Provider.
    private func existingReference(for reference: ExternalReference) throws -> ExternalReference? {
        if let externalRecordID = reference.externalRecordID,
           let found = try self.reference(provider: reference.provider,
                                          externalRecordID: externalRecordID,
                                          userID: reference.userID) {
            return found
        }
        if let syncIdentifier = reference.syncIdentifier,
           let found = try self.reference(provider: reference.provider,
                                          syncIdentifier: syncIdentifier,
                                          userID: reference.userID) {
            return found
        }
        // Nur ohne eigene Kennung auf die Entitaet zurueckfallen.
        //
        // Mit Kennung ist eine nicht gefundene Zeile eine *weitere* Kopie:
        // Drei Apps koennen denselben Lauf nach Apple Health legen, und jede
        // fuehrt ihn unter eigener Record-ID. Faellt man hier zurueck,
        // ueberschreibt die zweite Kopie die Kennung der ersten – und beim
        // naechsten Import wird die erste nicht wiedererkannt und erneut
        // angelegt. Genau so entstehen die Duplikate zurueck.
        guard reference.externalRecordID == nil, reference.syncIdentifier == nil else {
            return nil
        }
        return try references(entityType: reference.entityType, entityID: reference.entityID)
            .first { $0.provider == reference.provider }
    }

    func reference(provider: ProviderCode,
                   externalRecordID: String,
                   userID: String = HealthPitUser.local) throws -> ExternalReference? {
        try database.query("""
        SELECT * FROM external_reference
        WHERE user_id = ? AND provider = ? AND external_record_id = ? LIMIT 1;
        """, [.text(userID), .text(provider.rawValue), .text(externalRecordID)])
            .compactMap(ExternalReference.init(row:))
            .first
    }

    func reference(provider: ProviderCode,
                   syncIdentifier: String,
                   userID: String = HealthPitUser.local) throws -> ExternalReference? {
        try database.query("""
        SELECT * FROM external_reference
        WHERE user_id = ? AND provider = ? AND sync_identifier = ? LIMIT 1;
        """, [.text(userID), .text(provider.rawValue), .text(syncIdentifier)])
            .compactMap(ExternalReference.init(row:))
            .first
    }

    func references(entityType: ReferenceEntity, entityID: String) throws -> [ExternalReference] {
        try database.query("""
        SELECT * FROM external_reference WHERE entity_type = ? AND entity_id = ? ORDER BY id;
        """, [.text(entityType.rawValue), .text(entityID)])
            .compactMap(ExternalReference.init(row:))
    }

    func reference(entityType: ReferenceEntity,
                   entityID: String,
                   provider: ProviderCode) throws -> ExternalReference? {
        try references(entityType: entityType, entityID: entityID)
            .first { $0.provider == provider }
    }

    func referenceCount() throws -> Int {
        try database.query("SELECT COUNT(*) AS count FROM external_reference;").first?.int("count") ?? 0
    }

    // MARK: - Quellenfreigaben

    /// Darf dieser Wert von dieser Quelle uebernommen werden?
    ///
    /// Reihenfolge: genaue Quelle → Anbieter insgesamt → erlaubt. Ohne Regel
    /// ist alles erlaubt; Abschalten ist eine bewusste Entscheidung.
    func isSourceEnabled(metricID: MetricID,
                         provider: ProviderCode,
                         sourceAppID: String? = nil,
                         userID: String = HealthPitUser.local) throws -> Bool {
        let rows = try database.query("""
        SELECT * FROM metric_source_policy
        WHERE user_id = ? AND metric_id = ? AND provider = ?;
        """, [.text(userID), .text(metricID.rawValue), .text(provider.rawValue)])
            .compactMap(MetricSourcePolicy.init(row:))

        if let appID = sourceAppID,
           let exact = rows.first(where: { $0.sourceAppID == appID }) {
            return exact.enabled
        }
        if let providerWide = rows.first(where: \.isProviderWide) {
            return providerWide.enabled
        }
        return true
    }

    func setSourcePolicy(metricID: MetricID,
                         provider: ProviderCode,
                         sourceAppID: String = "",
                         enabled: Bool,
                         userID: String = HealthPitUser.local) throws {
        try database.run("""
        INSERT INTO metric_source_policy (user_id, metric_id, provider, source_app_id, enabled, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id, metric_id, provider, source_app_id) DO UPDATE SET
            enabled = excluded.enabled,
            updated_at = excluded.updated_at;
        """, [
            .text(userID),
            .text(metricID.rawValue),
            .text(provider.rawValue),
            .text(sourceAppID),
            .bool(enabled),
            .date(Date())
        ])
    }

    /// Regel wieder entfernen – der Wert gilt dann wieder als erlaubt.
    func clearSourcePolicy(metricID: MetricID,
                           provider: ProviderCode,
                           sourceAppID: String = "",
                           userID: String = HealthPitUser.local) throws {
        try database.run("""
        DELETE FROM metric_source_policy
        WHERE user_id = ? AND metric_id = ? AND provider = ? AND source_app_id = ?;
        """, [.text(userID), .text(metricID.rawValue), .text(provider.rawValue), .text(sourceAppID)])
    }

    func sourcePolicies(userID: String = HealthPitUser.local) throws -> [MetricSourcePolicy] {
        try database.query("""
        SELECT * FROM metric_source_policy WHERE user_id = ? ORDER BY metric_id, provider, source_app_id;
        """, [.text(userID)]).compactMap(MetricSourcePolicy.init(row:))
    }

    // MARK: - Doppelte Zusammenfassungen finden

    /// Gruppen von Observations, die denselben abgeschlossenen Zeitraum
    /// beschreiben – also dieselbe Aussage in mehreren Staenden.
    func duplicatePeriodAggregates(userID: String = HealthPitUser.local) throws -> [[HealthObservation]] {
        let keys = try database.query("""
        SELECT metric_id, origin_provider, aggregation, period_type, start_time, end_time,
               COALESCE(workout_id, '') AS workout_key, COUNT(*) AS row_count
        FROM health_observation
        WHERE user_id = ?
          AND deleted_at IS NULL
          AND period_type IN ('HOUR', 'DAY', 'NIGHT', 'SESSION', 'WORKOUT')
        GROUP BY metric_id, origin_provider, aggregation, period_type, start_time, end_time, workout_key
        HAVING COUNT(*) > 1;
        """, [.text(userID)])

        var groups: [[HealthObservation]] = []
        for key in keys {
            guard let metricID = key.string("metric_id"),
                  let originProvider = key.string("origin_provider"),
                  let aggregation = key.string("aggregation"),
                  let periodType = key.string("period_type"),
                  let start = key.double("start_time"),
                  let end = key.double("end_time") else { continue }
            let workoutKey = key.string("workout_key") ?? ""

            let rows = try database.query("""
            SELECT * FROM health_observation
            WHERE user_id = ? AND deleted_at IS NULL
              AND metric_id = ? AND origin_provider = ? AND aggregation = ? AND period_type = ?
              AND start_time = ? AND end_time = ? AND COALESCE(workout_id, '') = ?
            ORDER BY updated_at DESC;
            """, [
                .text(userID), .text(metricID), .text(originProvider), .text(aggregation),
                .text(periodType), .real(start), .real(end), .text(workoutKey)
            ]).compactMap(HealthObservation.init(row:))

            if rows.count > 1 { groups.append(rows) }
        }
        return groups
    }

    /// Zusammengefuehrte Werte: was weich geloescht wurde und worin es
    /// aufgegangen ist.
    ///
    /// Ohne diese Liste waere „ich habe Duplikate verbunden“ eine Aussage,
    /// die niemand nachpruefen kann.
    func mergedObservations(userID: String = HealthPitUser.local) throws -> [MergedObservation] {
        let retired = try database.query("""
        SELECT * FROM health_observation
        WHERE user_id = ? AND deleted_at IS NOT NULL AND metadata LIKE '%merged_into%'
        ORDER BY deleted_at DESC;
        """, [.text(userID)]).compactMap(HealthObservation.init(row:))

        var result: [MergedObservation] = []
        for duplicate in retired {
            guard let survivorID = duplicate.metadata["merged_into"].flatMap({ ObservationID($0) }) else {
                continue
            }
            result.append(MergedObservation(duplicate: duplicate,
                                            survivor: try observation(survivorID),
                                            reason: duplicate.metadata["merge_reason"] ?? "duplicate"))
        }
        return result
    }

    /// Metriken, zu denen mehrere Quellen denselben Zeitraum beliefern.
    ///
    /// Das ist kein Fehler – aber wer solche Werte addiert, zaehlt doppelt.
    /// Deshalb gehoert es sichtbar gemacht, damit man eine Quelle abschalten
    /// kann.
    func overlappingSourceWarnings(userID: String = HealthPitUser.local) throws -> [OverlappingSourceWarning] {
        let rows = try database.query("""
        SELECT metric_id,
               period_type,
               COUNT(DISTINCT origin_provider) AS provider_count,
               COUNT(*)                        AS observation_count,
               GROUP_CONCAT(DISTINCT origin_provider) AS providers
        FROM health_observation
        WHERE user_id = ? AND deleted_at IS NULL
        GROUP BY metric_id, period_type
        HAVING COUNT(DISTINCT origin_provider) > 1
        ORDER BY metric_id;
        """, [.text(userID)])

        return rows.compactMap { row in
            guard let metricRaw = row.string("metric_id"),
                  let metricID = MetricID(validating: metricRaw),
                  let periodRaw = row.string("period_type"),
                  let period = PeriodType(rawValue: periodRaw) else { return nil }
            let providers = (row.string("providers") ?? "")
                .split(separator: ",")
                .compactMap { ProviderCode(validating: String($0)) }
            return OverlappingSourceWarning(metricID: metricID,
                                            periodType: period,
                                            providers: providers,
                                            observationCount: row.int("observation_count") ?? 0)
        }
    }

    /// Alles aus dem neuen Modell wegwerfen und von vorn anfangen.
    ///
    /// Fuer den Fall, dass eine fruehere Fassung Unsinn angelegt hat. Die
    /// alten Caches und Dateien bleiben unberuehrt – aus ihnen wird neu
    /// uebernommen.
    func resetObservationData() throws {
        try database.transaction {
            for table in ["health_observation", "workout", "external_reference", "sync_event"] {
                try database.run("DELETE FROM \(table);")
            }
            try database.run("DELETE FROM migration_state;")
        }
    }

    // MARK: - Entitaetenkatalog

    /// Welche Quelle liefert welche Metrik – aus den tatsaechlich
    /// gespeicherten Messwerten, nicht aus einer gepflegten Liste.
    func catalog(userID: String = HealthPitUser.local) throws -> [MetricSourceUsage] {
        try database.query("""
        SELECT metric_id,
               origin_provider,
               ingest_provider,
               source_app_id,
               MAX(source_device_model) AS source_device_model,
               COUNT(*)                 AS observation_count,
               MIN(start_time)          AS first_seen,
               MAX(start_time)          AS last_seen,
               MAX(unit)                AS unit
        FROM health_observation
        WHERE user_id = ? AND deleted_at IS NULL
        GROUP BY metric_id, origin_provider, ingest_provider, source_app_id
        ORDER BY metric_id, origin_provider, ingest_provider;
        """, [.text(userID)]).compactMap(MetricSourceUsage.init(row:))
    }

    // MARK: - Sync Events

    @discardableResult
    func append(_ event: SyncEvent) throws -> Int64 {
        try database.run("""
        INSERT INTO sync_event
            (entity_type, entity_id, provider, direction, action, status, external_record_id,
             created_at, completed_at, error_code, error_message, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(event.entityType.rawValue),
            .text(event.entityID),
            .text(event.provider.rawValue),
            .text(event.direction.rawValue),
            .text(event.action.rawValue),
            .text(event.status.rawValue),
            .text(event.externalRecordID),
            .date(event.createdAt),
            .date(event.completedAt),
            .text(event.errorCode),
            .text(event.errorMessage),
            .text(JSONColumn.encode(event.metadata))
        ])
    }

    func syncEvents(entityID: String? = nil, provider: ProviderCode? = nil) throws -> [SyncEvent] {
        var sql = "SELECT * FROM sync_event WHERE 1 = 1"
        var bindings: [SQLValue] = []
        if let entityID {
            sql += " AND entity_id = ?"
            bindings.append(.text(entityID))
        }
        if let provider {
            sql += " AND provider = ?"
            bindings.append(.text(provider.rawValue))
        }
        sql += " ORDER BY id;"
        return try database.query(sql, bindings).compactMap(SyncEvent.init(row:))
    }

    // MARK: - Migrations-Merker

    func migrationFlag(_ key: String) throws -> String? {
        try database.query("SELECT value FROM migration_state WHERE key = ? LIMIT 1;", [.text(key)])
            .first?
            .string("value")
    }

    func setMigrationFlag(_ key: String, value: String) throws {
        try database.run("""
        INSERT INTO migration_state (key, value, applied_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, applied_at = excluded.applied_at;
        """, [.text(key), .text(value), .date(Date())])
    }

    /// Zugriff auf den alten Key-Value-Cache derselben Datei. Nur die
    /// Migration braucht das.
    func legacyCacheEntry(key: String) throws -> Data? {
        let tables = try database.query("""
        SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cache_entries';
        """)
        guard !tables.isEmpty else { return nil }
        // Der Cache legt sein JSON als BLOB ab. `data(_:)` nimmt beides –
        // BLOB und Text –, damit auch aeltere Eintraege lesbar bleiben.
        return try database.query("SELECT payload FROM cache_entries WHERE key = ? LIMIT 1;",
                                  [.text(key)]).first?.data("payload")
    }

    func legacyCacheKeys() throws -> [String] {
        let tables = try database.query("""
        SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cache_entries';
        """)
        guard !tables.isEmpty else { return [] }
        return try database.query("SELECT key FROM cache_entries ORDER BY key;")
            .compactMap { $0.string("key") }
    }

    /// Nur fuer Tests und Wartung.
    func executeRaw(_ sql: String) throws {
        try database.execute(sql)
    }
}

// MARK: - Zeilenabbildung

extension HealthObservation {
    var bindings: [SQLValue] {
        [
            .text(observationID.rawValue),
            .text(userID),
            .text(metricID.rawValue),
            .text(valueType.rawValue),
            .double(valueNumeric),
            .text(valueText),
            .text(valueCode),
            .bool(valueBoolean),
            .text(unit?.rawValue),
            .double(sourceValue),
            .text(sourceUnit?.rawValue),
            .date(startTime),
            .date(endTime),
            .text(timezone),
            .text(aggregation.rawValue),
            .text(periodType.rawValue),
            .text(originProvider.rawValue),
            .text(ingestProvider.rawValue),
            .text(originExternalID),
            .text(sourceMetric),
            .text(sourceAppID),
            .text(sourceDeviceID),
            .text(sourceDeviceModel),
            .text(workoutID?.rawValue),
            .text(sessionID),
            .int(version),
            .text(reviewState.rawValue),
            .text(contentHash),
            .text(heuristicKey),
            .date(receivedAt),
            .date(createdAt),
            .date(updatedAt),
            .date(deletedAt),
            .text(JSONColumn.encode(metadata)),
            .text(rawPayload)
        ]
    }

    init?(row: SQLRow) {
        guard let idText = row.string("observation_id"),
              let observationID = ObservationID(idText),
              let metricRaw = row.string("metric_id"),
              let metricID = MetricID(validating: metricRaw),
              let start = row.date("start_time"),
              let end = row.date("end_time"),
              let originRaw = row.string("origin_provider"),
              let origin = ProviderCode(validating: originRaw),
              let ingestRaw = row.string("ingest_provider"),
              let ingest = ProviderCode(validating: ingestRaw) else {
            return nil
        }
        self.init(observationID: observationID,
                  userID: row.string("user_id") ?? HealthPitUser.local,
                  metricID: metricID,
                  valueType: row.string("value_type").flatMap(MetricValueType.init(rawValue:)) ?? .number,
                  valueNumeric: row.double("value_numeric"),
                  valueText: row.string("value_text"),
                  valueCode: row.string("value_code"),
                  valueBoolean: row.bool("value_boolean"),
                  unit: row.string("unit").map { UnitCode($0) },
                  sourceValue: row.double("source_value"),
                  sourceUnit: row.string("source_unit").map { UnitCode($0) },
                  startTime: start,
                  endTime: end,
                  timezone: row.string("timezone"),
                  aggregation: row.string("aggregation").flatMap(Aggregation.init(rawValue:)) ?? .raw,
                  periodType: row.string("period_type").flatMap(PeriodType.init(rawValue:)) ?? .instant,
                  originProvider: origin,
                  ingestProvider: ingest,
                  originExternalID: row.string("origin_external_id"),
                  sourceMetric: row.string("source_metric"),
                  sourceAppID: row.string("source_app_id"),
                  sourceDeviceID: row.string("source_device_id"),
                  sourceDeviceModel: row.string("source_device_model"),
                  workoutID: row.string("workout_id").flatMap { WorkoutID($0) },
                  sessionID: row.string("session_id"),
                  version: row.int("version") ?? 1,
                  reviewState: row.string("review_state").flatMap(ReviewState.init(rawValue:)) ?? .ok,
                  receivedAt: row.date("received_at") ?? start,
                  createdAt: row.date("created_at") ?? start,
                  updatedAt: row.date("updated_at") ?? start,
                  deletedAt: row.date("deleted_at"),
                  metadata: JSONColumn.decode(row.string("metadata")),
                  rawPayload: row.string("raw_payload"))
    }
}

extension StoredWorkout {
    var bindings: [SQLValue] {
        [
            .text(workoutID.rawValue),
            .text(userID),
            .text(sportType),
            .text(title),
            .text(notes),
            .date(startTime),
            .date(endTime),
            .text(timezone),
            .text(originProvider.rawValue),
            .text(ingestProvider.rawValue),
            .text(sourceRecordID),
            .text(sourceAppID),
            .text(sourceDeviceID),
            .text(sourceDeviceModel),
            .int(version),
            .date(createdAt),
            .date(updatedAt),
            .date(deletedAt),
            .text(JSONColumn.encode(metadata)),
            .text(rawPayload)
        ]
    }

    init?(row: SQLRow) {
        guard let idText = row.string("workout_id"),
              let workoutID = WorkoutID(idText),
              let sport = row.string("sport_type"),
              let start = row.date("start_time"),
              let end = row.date("end_time"),
              let originRaw = row.string("origin_provider"),
              let origin = ProviderCode(validating: originRaw),
              let ingestRaw = row.string("ingest_provider"),
              let ingest = ProviderCode(validating: ingestRaw) else {
            return nil
        }
        self.init(workoutID: workoutID,
                  userID: row.string("user_id") ?? HealthPitUser.local,
                  sportType: sport,
                  title: row.string("title"),
                  notes: row.string("notes"),
                  startTime: start,
                  endTime: end,
                  timezone: row.string("timezone"),
                  originProvider: origin,
                  ingestProvider: ingest,
                  sourceRecordID: row.string("source_record_id"),
                  sourceAppID: row.string("source_app_id"),
                  sourceDeviceID: row.string("source_device_id"),
                  sourceDeviceModel: row.string("source_device_model"),
                  version: row.int("version") ?? 1,
                  createdAt: row.date("created_at") ?? start,
                  updatedAt: row.date("updated_at") ?? start,
                  deletedAt: row.date("deleted_at"),
                  metadata: JSONColumn.decode(row.string("metadata")),
                  rawPayload: row.string("raw_payload"))
    }
}

extension ExternalReference {
    var bindings: [SQLValue] {
        [
            .text(userID),
            .text(entityType.rawValue),
            .text(entityID),
            .text(provider.rawValue),
            .text(externalRecordID),
            .text(syncIdentifier),
            .int(syncVersion),
            .text(status.rawValue),
            .text(exportedContentHash),
            .date(firstSeenAt),
            .date(lastSeenAt),
            .date(importedAt),
            .date(exportedAt),
            .date(deletedAt),
            .text(JSONColumn.encode(metadata))
        ]
    }

    init?(row: SQLRow) {
        guard let entityRaw = row.string("entity_type"),
              let entityType = ReferenceEntity(rawValue: entityRaw),
              let entityID = row.string("entity_id"),
              let providerRaw = row.string("provider"),
              let provider = ProviderCode(validating: providerRaw) else {
            return nil
        }
        self.init(id: row.int64("id"),
                  userID: row.string("user_id") ?? HealthPitUser.local,
                  entityType: entityType,
                  entityID: entityID,
                  provider: provider,
                  externalRecordID: row.string("external_record_id"),
                  syncIdentifier: row.string("sync_identifier"),
                  syncVersion: row.int("sync_version"),
                  status: row.string("status").flatMap(ReferenceStatus.init(rawValue:)) ?? .active,
                  exportedContentHash: row.string("exported_content_hash"),
                  firstSeenAt: row.date("first_seen_at") ?? Date(),
                  lastSeenAt: row.date("last_seen_at") ?? Date(),
                  importedAt: row.date("imported_at"),
                  exportedAt: row.date("exported_at"),
                  deletedAt: row.date("deleted_at"),
                  metadata: JSONColumn.decode(row.string("metadata")))
    }
}

extension SyncEvent {
    init?(row: SQLRow) {
        guard let entityRaw = row.string("entity_type"),
              let entityType = ReferenceEntity(rawValue: entityRaw),
              let providerRaw = row.string("provider"),
              let provider = ProviderCode(validating: providerRaw),
              let directionRaw = row.string("direction"),
              let direction = SyncDirection(rawValue: directionRaw),
              let actionRaw = row.string("action"),
              let action = SyncAction(rawValue: actionRaw) else {
            return nil
        }
        self.init(id: row.int64("id"),
                  entityType: entityType,
                  entityID: row.string("entity_id"),
                  provider: provider,
                  direction: direction,
                  action: action,
                  status: row.string("status").flatMap(SyncStatus.init(rawValue:)) ?? .ok,
                  externalRecordID: row.string("external_record_id"),
                  createdAt: row.date("created_at") ?? Date(),
                  completedAt: row.date("completed_at"),
                  errorCode: row.string("error_code"),
                  errorMessage: row.string("error_message"),
                  metadata: JSONColumn.decode(row.string("metadata")))
    }
}
