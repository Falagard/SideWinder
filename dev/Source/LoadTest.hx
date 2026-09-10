import haxe.Http;
import haxe.Json;

class LoadTest {
    static function main() {
        for (i in 100...150) {
            var name = "Load Test " + i;
            var email = "loadtest" + i + "@example.com";
            var body = Json.stringify({name: name, email: email});
            
            var h = new Http("http://localhost:8000/users");
            h.setPostData(body);
            h.setHeader("Content-Type", "application/json");
            
            var done = false;
            h.onData = function(data) {
                trace("Request " + i + " success: " + data);
                done = true;
            };
            h.onError = function(msg) {
                trace("Request " + i + " error: " + msg);
                done = true;
            };
            
            h.request(true);
            
            // Wait for request (blocked on this target if not careful, but Http is usually sync on HL if not async)
            // On HashLink, h.request is synchronous.
        }
    }
}
