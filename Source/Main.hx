package;

import haxe.Json;
import haxe.Timer;
import sys.thread.Thread;
import lime.app.Application;
import lime.ui.WindowAttributes;
import lime.ui.Window;
import snake.http.HTTPStatus;
import snake.http.BaseHTTPRequestHandler;
import sidewinder.interfaces.IWebServer;
import sidewinder.interfaces.IUserService;
import sidewinder.interfaces.IUserServiceHandler;
import sidewinder.interfaces.IAuthService;
import sidewinder.interfaces.ICacheService;
import sidewinder.interfaces.IMessageBroker;
import sidewinder.interfaces.IStreamBroker;
import sidewinder.interfaces.INotificationService;
import sidewinder.interfaces.IStripeService;
import sidewinder.interfaces.IStripeWebhookService;
import sidewinder.interfaces.IStripeBillingStore;
import sidewinder.interfaces.IJobStore;
import sidewinder.interfaces.IDatabaseService;
import sidewinder.interfaces.IslandManager;
import sidewinder.interfaces.InMemoryJobStore;
import sidewinder.interfaces.ICookieJar;
import sidewinder.services.UserService;
import sidewinder.services.AuthService;
import sidewinder.services.SqliteDatabaseService;
import sidewinder.interfaces.InMemoryCacheService;
import sidewinder.services.StripeService;
import sidewinder.data.StripeBillingStore;
import hx.injection.ServiceType;
import sidewinder.core.WebServerFactory.WebServerType;
import sidewinder.services.StripeWebhookService;
import sidewinder.services.SendGridNotificationService;
import sidewinder.services.EmailTemplateEngine;
import sidewinder.messaging.PollingMessageBroker;
import sidewinder.messaging.LocalStreamBroker;
import sidewinder.core.DI;
import sidewinder.core.App;
import sidewinder.core.MultipartParser;
import sidewinder.core.WebServerFactory;
import sidewinder.core.GenericJobWorker;
import sidewinder.adapters.HxWellAdapter;
import sidewinder.adapters.CivetWebAdapter;
import sidewinder.routing.Router;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.routing.SideWinderRequestHandler;
import sidewinder.routing.WebSocketRouter;
import sidewinder.routing.AutoRouter;
import sidewinder.logging.HybridLogger;
import sidewinder.logging.FileLogProvider;
import sidewinder.logging.ConsoleLogProvider;
import sidewinder.logging.SqliteLogProvider;
import sidewinder.messaging.StreamBrokerDemo;
import sidewinder.messaging.EmailTemplateStreamConsumer;
import sidewinder.demo.ExampleAuthApp;
import sidewinder.demo.DesktopAppExample;
import sidewinder.demo.PollingClientDemo;
import sidewinder.demo.StreamTest;
import sidewinder.data.JobStatus;
import sidewinder.logging.HybridLogger.LogLevel;
import sidewinder.data.OAuthConfigSetup;
import sidewinder.data.SecureTokenStorage;
import sidewinder.data.PersistentCookieJar;

using hx.injection.ServiceExtensions;
import sidewinder.data.CookieJar;
import sidewinder.controllers.StripeSubscriptionController;
import sidewinder.controllers.MagicLinkController;
import sidewinder.controllers.AdminController;

using hx.injection.ServiceExtensions;

class Main extends Application {
	private static final DEFAULT_PROTOCOL = "HTTP/1.0"; // snake-server needs more work for 1.1 connections
	private static final DEFAULT_ADDRESS = "127.0.0.1";
	private static final DEFAULT_PORT = 8001;

	private var webServer:IWebServer;

	public static var router = sidewinder.routing.Router.instance;

	public var cache:ICacheService;

	public function new() {
		super();

		// Initialize logger with minimum level
		HybridLogger.init(LogLevel.DEBUG);

		// Add logging providers
		// Console logging for terminal output
		HybridLogger.addProvider(new ConsoleLogProvider());
		
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

		var directory:String = "static";

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

			c.addSingleton(IUserService, UserService);
			c.addSingleton(IAuthService, AuthService);
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

			c.addSingleton(IJobStore, InMemoryJobStore);
		});

		// Run database migrations after DI is configured
		var db = DI.get(IDatabaseService);
		db.runMigrations();

		cache = DI.get(ICacheService);
		var jobStore = DI.get(IJobStore);
		var streamBroker = DI.get(IStreamBroker);
		var messageBroker = DI.get(IMessageBroker);

		// Start the background job worker
		GenericJobWorker.start(streamBroker, jobStore, messageBroker);

		// Create singleton cookieJar for all async clients
		var cookieJar:ICookieJar = new CookieJar();

		// Create web server using factory pattern
		// Can switch between SnakeServer, CivetWeb, and HxWell implementations
		var serverTypeStr = Sys.getEnv("SIDEWINDER_SERVER");
		var serverType = WebServerType.HxWell;
		if (serverTypeStr == "civetweb") {
			serverType = WebServerType.CivetWeb;
		} else if (serverTypeStr == "snake") {
			serverType = WebServerType.SnakeServer;
		}

		var numIslandsStr = Sys.getEnv("SIDEWINDER_ISLANDS");
		var numIslands = numIslandsStr != null ? Std.parseInt(numIslandsStr) : 4;
		if (numIslands == null || numIslands < 1) numIslands = 4;

		var islandManager = new IslandManager(numIslands);

		webServer = WebServerFactory.create(serverType, DEFAULT_ADDRESS, DEFAULT_PORT, SideWinderRequestHandler, directory, islandManager);
		HybridLogger.info('[Main] Server initialized with $numIslands logic islands (shared-state workers)');

		// Setup WebSocket support if using CivetWeb
		// Using WebSocketRouter to support multiple handlers on a single endpoint
		// Client sends {"handler": "echo|chat|broadcast|auth"} as first message
		if (Std.isOfType(webServer, CivetWebAdapter)) {
			var civetAdapter:CivetWebAdapter = cast webServer;

			// Use the WebSocket router for multi-handler support
			var wsRouter = new WebSocketRouter(civetAdapter);
			civetAdapter.setWebSocketHandler(wsRouter);

			HybridLogger.info('[Main] WebSocket router enabled with handlers: echo, chat, broadcast, auth');
			HybridLogger.info('[Main] Connect to ws://localhost:$DEFAULT_PORT/ws');
			HybridLogger.info('[Main] Send {"handler": "<name>"} to select handler');
			HybridLogger.info('[Main] Test pages:');
			HybridLogger.info('[Main]   Echo: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/websocket_test.html');
			HybridLogger.info('[Main]   Chat: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/chatroom_demo.html');
			HybridLogger.info('[Main]   Broadcast: http://$DEFAULT_ADDRESS:$DEFAULT_PORT/broadcast_demo.html');
		} else if (Std.isOfType(webServer, HxWellAdapter)) {
			var hxwellAdapter:HxWellAdapter = cast webServer;
			hxwellAdapter.router = SideWinderRequestHandler.router;
			var wsRouter = new WebSocketRouter(hxwellAdapter);
			hxwellAdapter.setWebSocketHandler(wsRouter);

			HybridLogger.info('[Main] HxWell WebSocket router enabled with handlers: echo, chat, broadcast, auth');
		}

		// Web server will be started at the end of constructor to avoid blocking route registration
		// webServer.start();
		
		// Ensure request handling happens even if main loop update isn't consistent (headless mode)
		var requestTimer = new haxe.Timer(16); // ~60fps
		requestTimer.run = function() {
			webServer.handleRequest();
		};

		AutoRouter.build(router, sidewinder.interfaces.IUserServiceHandler, function() {
			return DI.get(IUserService);
		}, DI.get(ICacheService));

		AutoRouter.build(router, sidewinder.controllers.IAdminService, function() {
			return new AdminController(DI.get(IUserService));
		}, DI.get(ICacheService));

		// Add file upload test route
		router.add("POST", "/upload", function(req:Request, res:Response) {
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

		// Initialize Magic Link routes
		var magicLinkController:MagicLinkController = null;
		var getMagicLinkController = function() {
			if (magicLinkController == null) {
				var notifyService:INotificationService = null;
				try {
					notifyService = DI.get(INotificationService);
				} catch (e:Dynamic) {}
				
				magicLinkController = new MagicLinkController(DI.get(IAuthService), notifyService);
			}
			return magicLinkController;
		};

		App.post("/auth/magic-link", (req, res) -> getMagicLinkController().requestLink(req, res));
		App.get("/auth/magic-link/verify", (req, res) -> getMagicLinkController().verifyLink(req, res));

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

		// --- Non-Blocking Job Demo Routes ---
		
		// Dispatch a job: POST /job/dispatch { "type": "delay", "data": { "seconds": 5 } }
		App.post("/job/dispatch", (req, res) -> {
			var type = Reflect.field(req.jsonBody, "type");
			if (type == null) type = "delay";
			
			var jobId = Std.string(Math.floor(Math.random() * 1000000000)) + "_" + Std.string(Date.now().getTime());
			var clientId = req.cookies.get("session_id"); // Use session ID as clientId for notifications
			
			// 1. Create entry in JobStore
			var store = DI.get(IJobStore);
			store.create(jobId, type);
			
			// 2. Dispatch to stream
			var broker = DI.get(IStreamBroker);
			broker.xadd(GenericJobWorker.DEFAULT_STREAM, {
				id: jobId,
				type: type,
				clientId: clientId,
				data: req.jsonBody.data
			});
			
			// 3. Return 202 immediately
			res.sendResponse(snake.http.HTTPStatus.ACCEPTED);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(haxe.Json.stringify({
				status: "Pending",
				jobId: jobId,
				message: "Job dispatched successfully. Use /job/status/" + jobId + " to check progress."
			}));
			res.end();
		});

		// Check job status: GET /job/status/:id
		App.get("/job/status/:id", (req, res) -> {
			var jobId = req.params.get("id");
			var store = DI.get(IJobStore);
			var job = store.get(jobId);
			
			if (job == null) {
				res.sendError(snake.http.HTTPStatus.NOT_FOUND);
				res.end();
				return;
			}
			
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(haxe.Json.stringify(job));
			res.end();
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


		// Example: Broadcast a test message every 10 seconds
		HybridLogger.info("[Main] Initialization complete, starting web server...");
		webServer.start();
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

