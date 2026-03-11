package sidewinder;

/**
 * Represents the current state of an asynchronous job.
 */
enum JobStatus {
	Pending;
	Processing;
	Completed;
	Failed(error:String);
}
