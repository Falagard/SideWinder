package sidewinder.interfaces;

import hx.injection.Service;


import sys.db.Connection;
import sys.db.ResultSet;
import hx.injection.Service;

/**
 * Interface for database service implementations.
 * Supports different backends (SQLite, MySQL, PostgreSQL, etc.)
 */
interface IDatabaseService extends Service {
	/**
	 * Acquire a connection from the pool
	 * Deprecated: Use read/write instead.
	 */
	public function acquire():Connection;
	
	/**
	 * Release a connection back to the pool
	 * Deprecated: Use read/write instead.
	 */
	public function release(conn:Connection):Void;
	
	/**
	 * Execute a query with optional named parameters, returns ResultSet
	 */
	public function requestWithParams(sql:String, ?params:Map<String, Dynamic>):ResultSet;

	/**
	 * Optimized read operation
	 */
	public function requestRead(sql:String, ?params:Map<String, Dynamic>):ResultSet;

	/**
	 * Convenience alias for requestRead
	 */
	public function read(sql:String, ?params:Map<String, Dynamic>):ResultSet;

	/**
	 * Optimized write operation
	 */
	public function requestWrite(sql:String, ?params:Map<String, Dynamic>):ResultSet;

	/**
	 * Convenience alias for requestWrite
	 */
	public function write(sql:String, ?params:Map<String, Dynamic>):ResultSet;
	
	/**
	 * Execute a non-query (INSERT/UPDATE/DELETE)
	 */
	public function execute(sql:String, ?params:Map<String, Dynamic>):Void;

	/**
	 * Execute an INSERT and return the last insert ID
	 */
	public function executeAndGetId(sql:String, ?params:Map<String, Dynamic>):Int;

	/**
	 * Enqueue a non-query (INSERT/UPDATE/DELETE) for asynchronous execution.
	 * This is "fire-and-forget" and should only be used for non-critical 
	 * operations where immediate feedback or consistency is not required.
	 */
	public function enqueue(sql:String, ?params:Map<String, Dynamic>):Void;
	
	/**
	 * Run database migrations from the default path (migrations/sqlite)
	 */
	public function runMigrations():Void;

	/**
	 * Run database migrations from a custom directory
	 */
	public function runMigrationsWithPath(dir:String):Void;

	/**
	 * Block until all enqueued asynchronous operations are completed.
	 */
	public function flush():Void;
	
	/**
	 * Build an SQL string by substituting named parameters
	 */
	public function buildSql(sql:String, params:Map<String, Dynamic>):String;
	
	/**
	 * Escapes single quotes in a string for safe SQL usage
	 */
	public function escapeString(str:String):String;
	
	/**
	 * Quotes a string for safe SQL usage
	 */
	public function quoteString(str:String):String;
	
	/**
	 * Sanitizes input by trimming and escaping single quotes
	 */
	public function sanitize(str:String):String;
	
	/**
	 * Create a raw SQL passthrough value
	 */
	public function raw(v:String):RawSql;

	/**
	 * Begin a database transaction.
	 * In SQLite implementation, this locks the writer thread for exclusive use by the calling thread.
	 */
	public function beginTransaction():Void;

	/**
	 * Commit the current transaction.
	 */
	public function commit():Void;

	/**
	 * Roll back the current transaction.
	 */
	public function rollback():Void;
}

/** Represents raw SQL to be injected without quoting */
class RawSql {
	public var value:String;
	public function new(v:String) this.value = v;
}
