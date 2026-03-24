package sidewinder.services;

import sidewinder.interfaces.ILogDatabaseService;

/**
 * SQLite implementation of the log database service.
 * Points to logs.db by default.
 */
class SqliteLogDatabaseService extends SqliteDatabaseService implements ILogDatabaseService {
    public function new(config:core.IServerConfig) {
        this.dbPath = "Export/hl/bin/logs.db";
        super(config);
    }
}
