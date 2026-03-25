package sidewinder.services;

import sidewinder.interfaces.ILogDatabaseService;

/**
 * SQLite implementation of the log database service.
 * Points to logs.db by default.
 */
class SqliteLogDatabaseService extends SqliteDatabaseService implements ILogDatabaseService {
    public function new(config:core.IServerConfig) {
        if (this.dbPath == null) {
            this.dbPath = Sys.getEnv("LOG_DATABASE_PATH");
            if (this.dbPath == null) {
                // Heuristic for project structure
                if (sys.FileSystem.exists("Export/hl/bin")) {
                    this.dbPath = "Export/hl/bin/logs.db";
                } else {
                    this.dbPath = "logs.db";
                }
            }
        }
        super(config);
    }
}
