package sidewinder.services;

import sidewinder.interfaces.ILogDatabaseService;

/**
 * SQLite implementation of the log database service.
 * Points to logs.db by default.
 */
class SqliteLogDatabaseService extends SqliteDatabaseService implements ILogDatabaseService {
    public function new() {
        this.dbPath = "logs.db";
        super();
    }
}
