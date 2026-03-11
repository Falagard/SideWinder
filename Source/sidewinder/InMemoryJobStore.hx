package sidewinder;

import haxe.ds.StringMap;
import sidewinder.IJobStore.JobResult;

/**
 * In-memory implementation of IJobStore.
 */
class InMemoryJobStore implements IJobStore {
	private var jobs:StringMap<JobResult>;

	public function new() {
		jobs = new StringMap<JobResult>();
	}

	public function create(id:String, type:String):Void {
		var job:JobResult = {
			id: id,
			status: JobStatus.Pending,
			type: type,
			createdAt: Date.now().getTime()
		};
		jobs.set(id, job);
	}

	public function updateStatus(id:String, status:JobStatus, ?data:Dynamic):Void {
		var job = jobs.get(id);
		if (job != null) {
			job.status = status;
			job.updatedAt = Date.now().getTime();
			if (data != null) {
				job.data = data;
			}
			
			switch (status) {
				case Failed(err):
					job.error = err;
				default:
			}
		}
	}

	public function get(id:String):Null<JobResult> {
		return jobs.get(id);
	}

	public function getAll():Array<JobResult> {
		var result = [];
		for (job in jobs) {
			result.push(job);
		}
		return result;
	}

	public function delete(id:String):Bool {
		return jobs.remove(id);
	}
}
