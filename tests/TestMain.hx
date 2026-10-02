import utest.Runner;
import utest.ui.Report;

class TestMain {
	public static function main() {
		var runner = new Runner();
		runner.addCase(new sidewinder.http.HttpServerOptionsTest());
		runner.addCase(new sidewinder.http.WebSocketAdmissionPolicyTest());
		runner.addCase(new sidewinder.http.RequestScopeTest());
		runner.addCase(new sidewinder.routing.RouterMatchTest());
		runner.addCase(new sidewinder.websocket.WebSocketApplicationHandlerTest());
		runner.addCase(new sidewinder.services.SqlParameterBinderTest());
		runner.addCase(new sidewinder.http.StaticPathPolicyTest());
		runner.addCase(new sidewinder.logging.LogRedactionTest());
		Report.create(runner);
		runner.run();
	}
}
