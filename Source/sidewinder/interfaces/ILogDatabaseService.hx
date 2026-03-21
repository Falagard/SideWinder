package sidewinder.interfaces;

/**
 * Specialized database service for logging and auditing.
 * Separated to allow isolation of high-volume write traffic.
 */
interface ILogDatabaseService extends IDatabaseService {}
