package sidewinder;

import haxe.Http;
import haxe.Json;

class StripeService implements IStripeService {
	private var apiKey:String;
	private static inline var API_BASE = "https://api.stripe.com/v1";

	public function new() {
		apiKey = Sys.getEnv("STRIPE_SECRET_KEY");
		if (apiKey == null || apiKey == "") {
			throw "Stripe not configured. Set STRIPE_SECRET_KEY.";
		}
	}

	public function createCustomer(email:String, userId:Int):StripeCustomer {
		var params = [
			"email=" + StringTools.urlEncode(email),
			"metadata[user_id]=" + StringTools.urlEncode(Std.string(userId))
		];
		var response = postForm("/customers", params);
		return {
			id: response.id,
			email: response.email
		};
	}

	public function createSubscriptionCheckoutSession(customerId:String, priceId:String, successUrl:String, cancelUrl:String, userId:Int):StripeCheckoutSession {
		var params = [
			"mode=subscription",
			"success_url=" + StringTools.urlEncode(successUrl),
			"cancel_url=" + StringTools.urlEncode(cancelUrl),
			"customer=" + StringTools.urlEncode(customerId),
			"line_items[0][price]=" + StringTools.urlEncode(priceId),
			"line_items[0][quantity]=1",
			"client_reference_id=" + StringTools.urlEncode(Std.string(userId)),
			"subscription_data[metadata][user_id]=" + StringTools.urlEncode(Std.string(userId))
		];
		var response = postForm("/checkout/sessions", params);
		return {
			id: response.id,
			url: response.url,
			customer: response.customer,
			subscription: response.subscription
		};
	}

	public function retrieveSubscription(subscriptionId:String):StripeSubscription {
		var response = getJson("/subscriptions/" + StringTools.urlEncode(subscriptionId));
		return {
			id: response.id,
			status: response.status,
			current_period_end: toInt(response.current_period_end)
		};
	}

	public function cancelSubscription(subscriptionId:String):StripeSubscription {
		var response = postForm("/subscriptions/" + StringTools.urlEncode(subscriptionId) + "/cancel", []);
		return {
			id: response.id,
			status: response.status,
			current_period_end: toInt(response.current_period_end)
		};
	}

	private function postForm(path:String, params:Array<String>):Dynamic {
		return requestJson("POST", path, params);
	}

	private function getJson(path:String):Dynamic {
		return requestJson("GET", path, []);
	}

	private function requestJson(method:String, path:String, params:Array<String>):Dynamic {
		var url = API_BASE + path;
		var http = new Http(url);
		http.setHeader("Authorization", "Bearer " + apiKey);
		http.setHeader("Accept", "application/json");
		if (method == "POST") {
			http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		}

		var body = params.join("&");
		var result = "";
		var error = "";
		var statusCode = 0;

		http.onData = function(data:String) {
			result = data;
		};

		http.onError = function(err:String) {
			error = err;
		};

		http.onStatus = function(status:Int) {
			statusCode = status;
		};

		try {
			if (method == "POST") {
				http.setPostData(body);
				http.request(true);
			} else {
				http.request(false);
			}
		} catch (e:Dynamic) {
			throw "Stripe request failed: " + Std.string(e);
		}

		if (error != "") {
			throw "Stripe HTTP error: " + error;
		}

		if (result == "") {
			throw "Stripe response empty";
		}

		var parsed:Dynamic = Json.parse(result);
		var stripeError = Reflect.field(parsed, "error");
		if (stripeError != null) {
			var message = Std.string(Reflect.field(stripeError, "message"));
			throw "Stripe error: " + message;
		}

		if (statusCode >= 400) {
			throw "Stripe API error (status " + statusCode + ")";
		}

		return parsed;
	}

	private function toInt(value:Dynamic):Null<Int> {
		if (value == null) return null;
		var asString = Std.string(value);
		return Std.parseInt(asString);
	}
}
