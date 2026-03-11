package sidewinder;

import hx.injection.Service;

/**
 * Result data for a job.
 */
typedef JobResult = {
	var id:String;
	var status:JobStatus;
	var type:String;
	@:optional var data:Dynamic;
	@:optional var error:String;
	var createdAt:Float;
	@:optional var updatedAt:Float;
}

/**
 * Service for tracking the status and results of background jobs.
 */
interface IJobStore extends Service {
	public function create(id:String, type:String):Void;
	public function updateStatus(id:String, status:JobStatus, ?data:Dynamic):Void;
	public function get(id:String):Null<JobResult>;
	public function getAll():Array<JobResult>;
	public function delete(id:String):Bool;
}
