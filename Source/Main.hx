// Legacy duplicate file. Implementation moved to sidewinder/Main.hx.
import hx.injection.ServiceCollection;
import haxe.Json;
import haxe.Http;
import haxe.Timer;
import sidewinder.Router.Response;
import sidewinder.Router.Request;
import sidewinder.MultipartParser;
import sys.thread.Thread;
import lime.app.Application;
import lime.ui.WindowAttributes;
import lime.ui.Window;
import snake.http.*;
import snake.socket.*;
import sys.net.Host;
import sys.net.Socket;
import snake.server.*;
import lime.ui.Gamepad;
import lime.ui.GamepadButton;
import Date;
import sidewinder.IDatabaseService;
import sidewinder.SqliteDatabaseService;
// import sidewinder.MySqlDatabaseService;
import hx.injection.Service;
import sidewinder.*;
import sidewinder.IWebServer;
import sidewinder.WebServerFactory;

using hx.injection.ServiceExtensions;

class Main extends Application {
	private static final DEFAULT_PROTOCOL = "HTTP/1.0"; // snake-server needs more work for 1.1 connections
	private static final DEFAULT_ADDRESS = "127.0.0.1";
	private static final DEFAULT_PORT = 8000;

	private var webServer:IWebServer;

	public static var router = SideWinderRequestHandler.router;

	public var cache:ICacheService;

	public function new() {
		super();

		// Initialize logger with minimum level
		HybridLogger.init(HybridLogger.LogLevel.DEBUG);

		// Add logging providers
		// File logging (daily rotation)
		HybridLogger.addProvider(new FileLogProvider("logs"));

		// SQLite logging (batched for performance)
		// HybridLogger.addProvider(new SqliteLogProvider("logs", 20, 5.0));

		// Seq logging (structured logging to Seq server)
		// Uncomment and configure if you have a Seq server running:
		// HybridLogger.addProvider(new SeqLogProvider("http://localhost:5341", null, 10));

		HybridLogger.info("SideWinder application starting");

		// Initialize upload directory for file uploads
		MultipartParser.setUploadDirectory("uploads");

		// Cache service will be resolved from DI

		var directory:String = null;

		// Configure SideWinderRequestHandler
		BaseHTTPRequestHandler.protocolVersion = DEFAULT_PROTOCOL;
		SideWinderRequestHandler.corsEnabled = false;
		SideWinderRequestHandler.cacheEnabled = true;
		SideWinderRequestHandler.silent = true;

		DI.init(c -> {
			// Database service - choose between SQLite and MySQL
			c.addSingleton(IDatabaseService, SqliteDatabaseService);
			// For MySQL, use:
			// c.addSingleton(IDatabaseService, MySqlDatabaseService);

			c.addScoped(IUserService, UserService);
			c.addSingleton(ICacheService, InMemoryCacheService);
			c.addSingleton(IMessageBroker, PollingMessageBroker);
			c.addSingleton(IStreamBroker, LocalStreamBroker);

			// Notification service - configure with SendGrid API key
			// API key retrieved from environment variables in service constructor
			var sendgridApiKey = Sys.getEnv("SENDGRID_API_KEY");
			if (sendgridApiKey != null && sendgridApiKey != "") {
				c.addSingleton(INotificationService, SendGridNotificationService);
			} else {
				HybridLogger.warn("SendGrid not configured - set SENDGRID_API_KEY and SENDGRID_FROM_EMAIL environment variables");
			}

			var stripeSecretKey = Sys.getEnv("STRIPE_SECRET_KEY");
			if (stripeSecretKey != null && stripeSecretKey != "") {
				c.addSingleton(IStripeService, StripeService);
				c.addSingleton(IStripeBillingStore, StripeBillingStore);
				c.addSingleton(IStripeWebhookService, StripeWebhookService);
			} else {
				HybridLogger.warn("Stripe not configured - set STRIPE_SECRET_KEY to enable Stripe services");
			}
		});

		// Run database migrations after DI is configured
		var db = DI.get(IDatabaseService);
		db.runMigrations();

		cache = DI.get(ICacheService);

		// Create singleton cookieJar for all async clients
		var cookieJar:ICookieJar = new CookieJar();

		// Create web server using factory pattern
		// Can switch between SnakeServer and CivetWeb implementations
		webServer = WebServerFactory.create(WebServerFactory.WebServerType.SnakeServer, DEFAULT_ADDRESS, DEFAULT_PORT, SideWinderRequestHandler, directory);

		// Setup WebSocket support if using CivetWeb
		// Choose which WebSocket handler to use:
		// - EchoWebSocketHandler: Simple echo server
		// - ChatRoomWebSocketHandler: Multi-user chat room
		// - BroadcastWebSocketHandler: Channel-based broadcasting
		// - AuthenticatedWebSocketHandler: Token-based authentication
		if (Std.isOfType(webServer, CivetWebAdapter)) {
			var civetAdapter:CivetWebAdapter = cast webServer;

			// Change this line to switch between different WebSocket handlers
			var wsHandlerType = "chat"; // Options: "echo", "chat", "broadcast", "auth"

			switch (wsHandlerType) {
				case "echo":
					var wsHandler = new EchoWebSocketHandler(civetAdapter);
					civetAdapter.setWebSocketHandler(wsHandler);
					HybridLogger.info('[Main] WebSocket echo handler enabled');
					HybridLogger.info('[Main] Test at: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/websocket_test.html');

				case "chat":
					var wsHandler = new ChatRoomWebSocketHandler(civetAdapter);
					civetAdapter.setWebSocketHandler(wsHandler);
					HybridLogger.info('[Main] WebSocket chat room handler enabled');
					HybridLogger.info('[Main] Test at: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/chatroom_demo.html');

				case "broadcast":
					var wsHandler = new BroadcastWebSocketHandler(civetAdapter);
					civetAdapter.setWebSocketHandler(wsHandler);
					HybridLogger.info('[Main] WebSocket broadcast handler enabled');
					HybridLogger.info('[Main] Test at: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/broadcast_demo.html');

				case "auth":
					var wsHandler = new AuthenticatedWebSocketHandler(civetAdapter, 30.0); // 30 second auth timeout
					civetAdapter.setWebSocketHandler(wsHandler);
					HybridLogger.info('[Main] WebSocket authenticated handler enabled');
					HybridLogger.info('[Main] Test at: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/auth_demo.html');
					HybridLogger.info('[Main] Demo tokens: "demo-token-123" (user), "admin-token-456" (admin)');

				default:
					HybridLogger.warn('[Main] Unknown WebSocket handler type: $wsHandlerType');
			}
		}

		webServer.start();

		AutoRouter.build(router, IUserService, function() {
			return DI.get(IUserService);
		});

		// Add file upload test route
		router.add("POST", "/upload", function(req:Router.Request, res:Router.Response) {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();

			var response = {
				message: "Files uploaded successfully",
				fileCount: req.files.length,
				files: req.files.map(f -> {
					return {
						fieldName: f.fieldName,
						originalName: f.fileName,
						savedPath: f.filePath,
						size: f.size,
						contentType: f.contentType
					};
				}),
				formFields: [for (k in req.formBody.keys()) {field: k, value: req.formBody.get(k)}]
			};

			res.write(haxe.Json.stringify(response, null, "  "));
			res.end();
		});

		var stripeSecretKey = Sys.getEnv("STRIPE_SECRET_KEY");
		if (stripeSecretKey != null && stripeSecretKey != "") {
			var stripeController:StripeSubscriptionController = null;
			var getStripeController = function() {
				if (stripeController == null) {
					stripeController = new StripeSubscriptionController(DI.get(IStripeService), DI.get(IStripeBillingStore), DI.get(IStripeWebhookService));
				}
				return stripeController;
			};

			App.post("/stripe/checkout-session", (req, res) -> getStripeController().createCheckoutSession(req, res));
			App.get("/stripe/subscription/:userId", (req, res) -> getStripeController().getSubscription(req, res));
			App.post("/stripe/cancel-subscription", (req, res) -> getStripeController().cancelSubscription(req, res));
			App.post("/stripe/webhooks", (req, res) -> getStripeController().handleWebhook(req, res));
		} else {
			HybridLogger.warn("Stripe endpoints not registered - set STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET to enable Stripe routes");
		}

		// Synchronous AutoClient example (legacy port 8080 kept for reference; server actually runs on DEFAULT_PORT)
		var userClient:IUserService = AutoClient.create(IUserService, "http://localhost:8080");

		// AutoClientAsync example: create async client pointed at the active server port and perform calls.
		// Each interface method getAll() becomes getAllAsync(onSuccess, onFailure).
		var userClientAsync = AutoClientAsync.create(IUserService, 'http://' + DEFAULT_ADDRESS + ':' + DEFAULT_PORT, cookieJar);

		// Delay invocation slightly to allow server startup.
		Timer.delay(() -> {
			userClientAsync.getAllAsync(function(users:Array<IUserService.User>) {
				HybridLogger.debug('AutoClientAsync getAll returned ' + (users == null ? 0 : users.length) + ' users');
			}, function(err:Dynamic) {
				HybridLogger.error('AutoClientAsync getAll failed: ' + Std.string(err));
			});
		}, 100);

		// Demonstrate createAsync + deleteAsync to verify DELETE handling (raw socket implementation in AutoClientAsync for DELETE).
		Timer.delay(() -> {
			userClientAsync.createAsync({id: 0, name: 'TempUser', email: 'tempuser@example.com'}, function(newUser:IUserService.User) {
				HybridLogger.debug('AutoClientAsync create returned id=' + newUser.id);
				userClientAsync.deleteAsync(newUser.id, function(result:Bool) {
					HybridLogger.debug('AutoClientAsync delete returned ' + result + ' for id=' + newUser.id);
				}, function(err:Dynamic) {
					HybridLogger.error('AutoClientAsync delete failed: ' + Std.string(err));
				});
			}, function(err:Dynamic) {
				HybridLogger.error('AutoClientAsync create failed: ' + Std.string(err));
			});
		}, 300);

		// Example middleware: logging
		App.use((req, res, next) -> {
			//
			HybridLogger.info('${req.method} ${req.path} ' + Sys.time());
			next();
		});

		// Example middleware: auth simulation
		App.use((req, res, next) -> {
			if (StringTools.startsWith(req.path, "/private")) {
				res.sendError(HTTPStatus.UNAUTHORIZED);
				res.setHeader("Content-Type", "text/plain");
				res.endHeaders();
				res.write("Unauthorized");
			} else
				next();
		});

		// Example route: /hello
		App.get("/hello", (req, res) -> {
			var html = "Hello, world!" + Sys.time();
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.setHeader('Content-Length', Std.string(html.length));
			res.endHeaders();
			res.write(html);
			res.end();
		});

		// New route: /goodbye
		App.get("/goodbye", (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Goodbye, world!");
			res.end();
		});

		App.get("/private", (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Private content accessed!");
			res.end();
		});

		App.get("/cookie", (req, res) -> {
			// Read a cookie from the request
			var sessionId = req.cookies.get("session_id");
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write(sessionId != null ? "Cookie: " + sessionId : "No session_id cookie found");
			res.end();
		});

		App.get("/async", (req, res) -> {
			// Requests run in their own thread, so we can block here.
			// In fact, async operations must block the request thread to avoid issues, because otherwise the request may finish before the async operation completes.

			// Simulate an asynchronous operation using AsyncBlockerPool, create a new thread aysncOperationSimulation which takes some time to complete and then calls the cb
			// callback with the result
			var html = AsyncBlockerPool.run(cb -> {
				// do some async work, call cb when done
				Thread.create(() -> {
					asyncOperationSimulation(function(result:String) {
						cb(result);
					}, function() {
						// failure callback simulation
						cb("<html><body><p>Async operation failed.</p></body></html>");
					});
				});
			});

			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/html");
			res.endHeaders();
			res.write(html);
			res.end();
		});

		// Email notification endpoint
		App.post("/send-email", (req, res) -> {
			try {
				// Parse the JSON body to get email parameters
				var to:String = Reflect.field(req.jsonBody, "to");
				var subject:String = Reflect.field(req.jsonBody, "subject");
				var body:String = Reflect.field(req.jsonBody, "body");
				var isHtml:Bool = Reflect.field(req.jsonBody, "isHtml");

				if (to == null || subject == null || body == null) {
					res.sendResponse(snake.http.HTTPStatus.BAD_REQUEST);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write(Json.stringify({error: "Missing required fields: to, subject, body"}));
					res.end();
					return;
				}

				// Get notification service from DI
				var notificationService:INotificationService = null;
				try {
					notificationService = DI.get(INotificationService);
				} catch (e:Dynamic) {
					HybridLogger.warn("Notification service not configured");
					res.sendResponse(snake.http.HTTPStatus.SERVICE_UNAVAILABLE);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write(Json.stringify({error: "Email service not configured. Please set SENDGRID_API_KEY and SENDGRID_FROM_EMAIL environment variables"}));
					res.end();
					return;
				}

				// Send email asynchronously
				notificationService.sendEmail(to, subject, body, isHtml, function(err:Dynamic) {
					if (err != null) {
						HybridLogger.error('Failed to send email: $err');
						res.sendResponse(snake.http.HTTPStatus.INTERNAL_SERVER_ERROR);
						res.setHeader("Content-Type", "application/json");
						res.endHeaders();
						res.write(Json.stringify({error: "Failed to send email", details: Std.string(err)}));
						res.end();
					} else {
						HybridLogger.info('Email sent successfully to: $to');
						res.sendResponse(snake.http.HTTPStatus.OK);
						res.setHeader("Content-Type", "application/json");
						res.endHeaders();
						res.write(Json.stringify({success: true, message: "Email sent successfully"}));
						res.end();
					}
				});
			} catch (e:Dynamic) {
				HybridLogger.error('Exception in /send-email endpoint: $e');
				res.sendResponse(snake.http.HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write(Json.stringify({error: "Internal server error", details: Std.string(e)}));
				res.end();
			}
		});

		// Polling endpoints for WebSocket-like messaging
		var messageBroker:IMessageBroker = DI.get(IMessageBroker);

		// Subscribe endpoint
		App.post("/poll/subscribe", (req, res) -> {
			try {
				var data:Dynamic = req.jsonBody;
				var clientId:String = data.clientId;

				if (clientId == null || clientId == "") {
					res.sendError(HTTPStatus.BAD_REQUEST);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write('{"error": "clientId required"}');
					res.end();
					return;
				}

				messageBroker.subscribe(clientId);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "subscribed", "clientId": "' + clientId + '"}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Subscribe error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Unsubscribe endpoint
		App.post("/poll/unsubscribe/:clientId", (req, res) -> {
			try {
				var clientId = req.params.get("clientId");
				messageBroker.unsubscribe(clientId);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "unsubscribed"}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Unsubscribe error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Long-polling endpoint
		App.get("/poll/:clientId", (req, res) -> {
			try {
				var clientId = req.params.get("clientId");

				if (!messageBroker.isSubscribed(clientId)) {
					res.sendError(HTTPStatus.NOT_FOUND);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write('{"error": "Client not subscribed"}');
					res.end();
					return;
				}

				// Long-polling: blocks until messages available or timeout
				var messages = messageBroker.getMessages(clientId, 30.0);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write(Json.stringify({messages: messages}));
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Poll error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Send message to specific client (for testing)
		App.post("/poll/send/:clientId", (req, res) -> {
			try {
				var clientId = req.params.get("clientId");
				var data:Dynamic = req.jsonBody;
				var message:String = data.message;

				if (message == null) {
					res.sendError(HTTPStatus.BAD_REQUEST);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write('{"error": "message required"}');
					res.end();
					return;
				}

				messageBroker.sendToClient(clientId, message);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "sent"}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Send error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Broadcast message to all clients (for testing)
		App.post("/poll/broadcast", (req, res) -> {
			try {
				var data:Dynamic = req.jsonBody;
				var message:String = data.message;

				if (message == null) {
					res.sendError(HTTPStatus.BAD_REQUEST);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write('{"error": "message required"}');
					res.end();
					return;
				}

				messageBroker.broadcast(message);
				var clientCount = messageBroker.getClientCount();

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "broadcast", "clientCount": ' + clientCount + '}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Broadcast error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// ===== Stream Broker Demo Routes =====
		var streamBroker:IStreamBroker = DI.get(IStreamBroker);

		// Email template stream consumer (background worker)
		try {
			var notificationService = DI.get(INotificationService);
			var templateEngine = new EmailTemplateEngine();
			EmailTemplateStreamConsumer.start(streamBroker, notificationService, templateEngine);
		} catch (e:Dynamic) {
			HybridLogger.warn('Email template consumer not started: ' + Std.string(e));
		}

		// Add message to stream (fire-and-forget)
		App.post("/stream/:streamName/add", (req, res) -> {
			try {
				var streamName = req.params.get("streamName");
				var data:Dynamic = req.jsonBody;

				if (data == null) {
					res.sendError(HTTPStatus.BAD_REQUEST);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write('{"error": "message data required"}');
					res.end();
					return;
				}

				var messageId = streamBroker.xadd(streamName, data);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "added", "messageId": "$messageId", "stream": "$streamName"}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Stream add error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Create consumer group
		App.post("/stream/:streamName/group/:groupName", (req, res) -> {
			try {
				var streamName = req.params.get("streamName");
				var groupName = req.params.get("groupName");
				var data:Dynamic = req.jsonBody;
				var startId:String = data != null && data.startId != null ? data.startId : "$";

				streamBroker.createGroup(streamName, groupName, startId);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "created", "stream": "$streamName", "group": "$groupName", "startId": "$startId"}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Create group error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Read messages from consumer group
		App.get("/stream/:streamName/group/:groupName/consumer/:consumerName", (req, res) -> {
			try {
				var streamName = req.params.get("streamName");
				var groupName = req.params.get("groupName");
				var consumerName = req.params.get("consumerName");
				var count:Int = req.query.exists("count") ? Std.parseInt(req.query.get("count")) : 1;
				var blockMs:Null<Int> = req.query.exists("block") ? Std.parseInt(req.query.get("block")) : 0;

				var messages = streamBroker.xreadgroup(groupName, consumerName, streamName, count, blockMs);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write(Json.stringify({
					stream: streamName,
					group: groupName,
					consumer: consumerName,
					count: messages.length,
					messages: messages
				}));
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Read group error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Acknowledge messages
		App.post("/stream/:streamName/group/:groupName/ack", (req, res) -> {
			try {
				var streamName = req.params.get("streamName");
				var groupName = req.params.get("groupName");
				var data:Dynamic = req.jsonBody;
				var messageIds:Array<String> = data.messageIds;

				if (messageIds == null || messageIds.length == 0) {
					res.sendError(HTTPStatus.BAD_REQUEST);
					res.setHeader("Content-Type", "application/json");
					res.endHeaders();
					res.write('{"error": "messageIds array required"}');
					res.end();
					return;
				}

				var acked = streamBroker.xack(streamName, groupName, messageIds);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"status": "acknowledged", "count": $acked}');
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Ack error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Get stream info
		App.get("/stream/:streamName/info", (req, res) -> {
			try {
				var streamName = req.params.get("streamName");
				var length = streamBroker.xlen(streamName);
				var groups = streamBroker.getGroupInfo(streamName);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write(Json.stringify({
					stream: streamName,
					length: length,
					groups: groups
				}));
				res.end();
			} catch (e:Dynamic) {
				HybridLogger.error('Info error: ' + Std.string(e));
				res.sendError(HTTPStatus.INTERNAL_SERVER_ERROR);
				res.setHeader("Content-Type", "application/json");
				res.endHeaders();
				res.write('{"error": "' + Std.string(e) + '"}');
				res.end();
			}
		});

		// Demo: Run StreamBrokerDemo examples in background
		Timer.delay(() -> {
			Thread.create(() -> {
				HybridLogger.info('[Main] Running Stream Broker demos...');
				var demo = new StreamBrokerDemo(streamBroker);
				demo.runAll();
				HybridLogger.info('[Main] Stream Broker demos completed');
			});
		}, 2000);

		// Example: Broadcast a test message every 10 seconds
		Timer.delay(() -> {
			var counter = 0;
			function broadcastLoop() {
				counter++;
				var testMessage = Json.stringify({
					type: "test",
					timestamp: Date.now().getTime(),
					counter: counter,
					message: "Hello from server! Message #" + counter
				});
				messageBroker.broadcast(testMessage);
				HybridLogger.info('Broadcast test message #' + counter + ' to ' + messageBroker.getClientCount() + ' clients');
				Timer.delay(broadcastLoop, 10000);
			}
			broadcastLoop();
		}, 5000);
	}

	private function asyncOperationSimulation(onSuccess:(String) -> Void, onFailure:() -> Void):Void {
		// Simulate a long-running operation
		Sys.sleep(3);

		// comment this out to simulate success
		return onSuccess("<html><body><p>This response was generated after a simulated async operation.</p></body></html>");

		// uncomment below to simulate failure
		// onFailure();
	}

	// Entry point
	public static function main() {
		var app:Main = new Main();
		app.exec();
	}

	// Override update to serve HTTP requests
	public override function update(deltaTime:Int):Void {
		webServer.handleRequest();
	}

	// Override createWindow to prevent Lime from creating a window
	override public function createWindow(attributes:WindowAttributes):Window {
		return null;
	}
}
