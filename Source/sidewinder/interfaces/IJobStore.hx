package sidewinder.interfaces;

import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;


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



