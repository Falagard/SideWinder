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
		Report.create(runner);
		runner.run();
	}
}
