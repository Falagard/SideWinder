package sidewinder;

import haxe.Json;
import sidewinder.Router.Request;
import sidewinder.Router.Response;
import snake.http.HTTPStatus;

class StripeSubscriptionController {
	private var stripeService:IStripeService;
	private var billingStore:IStripeBillingStore;
	private var webhookService:IStripeWebhookService;

	public function new(stripeService:IStripeService, billingStore:IStripeBillingStore, webhookService:IStripeWebhookService) {
		this.stripeService = stripeService;
		this.billingStore = billingStore;
		this.webhookService = webhookService;
	}

	/**
	 * POST /stripe/checkout-session
	 * Body: { userId, priceId?, successUrl, cancelUrl }
	 */
	public function createCheckoutSession(req:Request, res:Response):Void {
		try {
			var userId = parseRequiredInt(req, "userId");
			if (userId == null) {
				sendJson(res, HTTPStatus.BAD_REQUEST, {error: "userId is required"});
				return;
			}

			var priceId = getValue(req, "priceId");
			if (priceId == null || priceId == "") {
				priceId = Sys.getEnv("STRIPE_PRICE_ID");
			}
			if (priceId == null || priceId == "") {
				sendJson(res, HTTPStatus.BAD_REQUEST, {error: "priceId is required"});
				return;
			}

			var successUrl = getValue(req, "successUrl");
			var cancelUrl = getValue(req, "cancelUrl");
			if (successUrl == null || cancelUrl == null) {
				sendJson(res, HTTPStatus.BAD_REQUEST, {error: "successUrl and cancelUrl are required"});
				return;
			}

			var billing = billingStore.getUserBilling(userId);
			if (billing == null) {
				sendJson(res, HTTPStatus.NOT_FOUND, {error: "User not found"});
				return;
			}

			var customerId = billing.stripeCustomerId;
			if (customerId == null || customerId == "") {
				var customer = stripeService.createCustomer(billing.email, userId);
				customerId = customer.id;
				billingStore.setStripeCustomerId(userId, customerId);
			}

			var session = stripeService.createSubscriptionCheckoutSession(customerId, priceId, successUrl, cancelUrl, userId);
			sendJson(res, HTTPStatus.OK, {
				id: session.id,
				url: session.url,
				customerId: session.customer,
				subscriptionId: session.subscription
			});
		} catch (e:Dynamic) {
			sendJson(res, HTTPStatus.INTERNAL_SERVER_ERROR, {error: Std.string(e)});
		}
	}

	/**
	 * GET /stripe/subscription/:userId
	 */
	public function getSubscription(req:Request, res:Response):Void {
		var userId = parseInt(req.params.get("userId"));
		if (userId == null) {
			sendJson(res, HTTPStatus.BAD_REQUEST, {error: "userId is required"});
			return;
		}

		try {
			var billing = billingStore.getUserBilling(userId);
			if (billing == null || billing.stripeSubscriptionId == null || billing.stripeSubscriptionId == "") {
				sendJson(res, HTTPStatus.NOT_FOUND, {error: "No subscription found"});
				return;
			}

			var subscription = stripeService.retrieveSubscription(billing.stripeSubscriptionId);
			sendJson(res, HTTPStatus.OK, {
				id: subscription.id,
				status: subscription.status,
				currentPeriodEnd: subscription.current_period_end
			});
		} catch (e:Dynamic) {
			sendJson(res, HTTPStatus.INTERNAL_SERVER_ERROR, {error: Std.string(e)});
		}
	}

	/**
	 * POST /stripe/cancel-subscription
	 * Body: { userId }
	 */
	public function cancelSubscription(req:Request, res:Response):Void {
		var userId = parseRequiredInt(req, "userId");
		if (userId == null) {
			sendJson(res, HTTPStatus.BAD_REQUEST, {error: "userId is required"});
			return;
		}

		try {
			var billing = billingStore.getUserBilling(userId);
			if (billing == null || billing.stripeSubscriptionId == null || billing.stripeSubscriptionId == "") {
				sendJson(res, HTTPStatus.NOT_FOUND, {error: "No subscription found"});
				return;
			}

			var subscription = stripeService.cancelSubscription(billing.stripeSubscriptionId);
			billingStore.setSubscription(userId, subscription.id, subscription.status, subscription.current_period_end);
			sendJson(res, HTTPStatus.OK, {
				id: subscription.id,
				status: subscription.status,
				currentPeriodEnd: subscription.current_period_end
			});
		} catch (e:Dynamic) {
			sendJson(res, HTTPStatus.INTERNAL_SERVER_ERROR, {error: Std.string(e)});
		}
	}

	/**
	 * POST /stripe/webhooks
	 */
	public function handleWebhook(req:Request, res:Response):Void {
		var signature = req.headers.get("Stripe-Signature");
		var result = webhookService.handleWebhook(req.body, signature);
		sendJson(res, cast result.status, result.body);
	}

	private function getValue(req:Request, key:String):Null<String> {
		if (req.jsonBody != null) {
			var value = Reflect.field(req.jsonBody, key);
			if (value != null)
				return Std.string(value);
		}
		if (req.formBody != null && req.formBody.exists(key)) {
			return req.formBody.get(key);
		}
		return null;
	}

	private function parseRequiredInt(req:Request, key:String):Null<Int> {
		return parseInt(getValue(req, key));
	}

	private function parseInt(value:Null<String>):Null<Int> {
		if (value == null || value == "")
			return null;
		return Std.parseInt(value);
	}

	private function sendJson(res:Response, status:HTTPStatus, body:Dynamic):Void {
		res.sendResponse(status);
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		res.write(Json.stringify(body));
		res.end();
	}
}
