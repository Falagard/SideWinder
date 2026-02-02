package sidewinder;

import haxe.Json;
import haxe.crypto.Hmac;
import haxe.crypto.Sha256;
import haxe.io.Bytes;

class StripeWebhookService implements IStripeWebhookService {
	private static inline var SIGNATURE_TOLERANCE_SECONDS = 300;

	private var webhookSecret:String;
	private var billingStore:IStripeBillingStore;

	public function new() {
		webhookSecret = Sys.getEnv("STRIPE_WEBHOOK_SECRET");
		billingStore = DI.get(IStripeBillingStore);
	}

	public function handleWebhook(rawBody:String, signatureHeader:String):StripeWebhookResult {
		if (webhookSecret == null || webhookSecret == "") {
			return { status: 500, body: { error: "Stripe webhook secret not configured" } };
		}

		if (!validateSignature(rawBody, signatureHeader)) {
			return { status: 400, body: { error: "Invalid Stripe signature" } };
		}

		var event:Dynamic = null;
		try {
			event = Json.parse(rawBody);
		} catch (e:Dynamic) {
			return { status: 400, body: { error: "Invalid JSON payload" } };
		}

		var eventType = getString(event, "type");
		var eventId = getString(event, "id");
		var data = getField(event, "data");
		var obj = getField(data, "object");

		var customerId:Null<String> = getString(obj, "customer");
		var subscriptionId:Null<String> = null;
		var invoiceId:Null<String> = null;
		var amount:Null<Int> = null;
		var currency:Null<String> = null;
		var status:Null<String> = null;
		var userId:Null<Int> = null;

		switch (eventType) {
			case "checkout.session.completed":
				subscriptionId = getString(obj, "subscription");
				var clientReference = getString(obj, "client_reference_id");
				userId = parseInt(clientReference);
				if (userId == null) {
					var metadata = getField(obj, "metadata");
					userId = getInt(metadata, "user_id");
				}
				if (userId != null) {
					if (customerId != null) {
						billingStore.setStripeCustomerId(userId, customerId);
					}
					if (subscriptionId != null) {
						billingStore.setSubscription(userId, subscriptionId, null, null);
					}
				}

			case "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted":
				subscriptionId = getString(obj, "id");
				status = getString(obj, "status");
				var periodEnd = getInt(obj, "current_period_end");
				userId = billingStore.updateSubscriptionByCustomerId(customerId, subscriptionId, status, periodEnd);

			case "invoice.paid", "invoice.payment_failed":
				invoiceId = getString(obj, "id");
				subscriptionId = getString(obj, "subscription");
				amount = getInt(obj, "amount_paid");
				if (amount == null) amount = getInt(obj, "amount_due");
				currency = getString(obj, "currency");
				status = getString(obj, "payment_status");
				if (status == null) status = getString(obj, "status");
				userId = billingStore.findUserIdByCustomerId(customerId);

			default:
				// No-op for unhandled event types
		}

		var logEventId = eventId != null ? eventId : "unknown";
		var logEventType = eventType != null ? eventType : "unknown";
		billingStore.logBillingEvent(userId, logEventId, logEventType, subscriptionId, invoiceId, amount, currency, status, rawBody);

		return { status: 200, body: { received: true } };
	}

	private function validateSignature(rawBody:String, signatureHeader:String):Bool {
		if (signatureHeader == null || signatureHeader == "") return false;
		var timestamp:Null<String> = null;
		var signatures:Array<String> = [];

		for (part in signatureHeader.split(",")) {
			var kv = part.split("=");
			if (kv.length != 2) continue;
			var key = StringTools.trim(kv[0]);
			var value = StringTools.trim(kv[1]);
			switch (key) {
				case "t":
					timestamp = value;
				case "v1":
					signatures.push(value);
				default:
			}
		}

		if (timestamp == null || signatures.length == 0) return false;
		var timestampInt = Std.parseInt(timestamp);
		if (timestampInt == null) return false;
		var now = Std.int(Sys.time());
		if (Math.abs(now - timestampInt) > SIGNATURE_TOLERANCE_SECONDS) return false;

		var signedPayload = timestamp + "." + rawBody;
		var expectedSignature = computeSignature(signedPayload);
		for (sig in signatures) {
			if (timingSafeEquals(expectedSignature, sig)) return true;
		}
		return false;
	}

	private function computeSignature(payload:String):String {
		var hmac = new Hmac(new Sha256());
		var signatureBytes = hmac.make(Bytes.ofString(webhookSecret), Bytes.ofString(payload));
		return bytesToHex(signatureBytes);
	}

	private function bytesToHex(bytes:Bytes):String {
		var hex = new StringBuf();
		for (i in 0...bytes.length) {
			hex.add(StringTools.hex(bytes.get(i), 2).toLowerCase());
		}
		return hex.toString();
	}

	private function timingSafeEquals(a:String, b:String):Bool {
		if (a == null || b == null) return false;
		if (a.length != b.length) return false;
		var result = 0;
		for (i in 0...a.length) {
			result |= a.charCodeAt(i) ^ b.charCodeAt(i);
		}
		return result == 0;
	}

	private function getField(obj:Dynamic, field:String):Dynamic {
		if (obj == null) return null;
		return Reflect.hasField(obj, field) ? Reflect.field(obj, field) : null;
	}

	private function getString(obj:Dynamic, field:String):Null<String> {
		var value = getField(obj, field);
		if (value == null) return null;
		return Std.string(value);
	}

	private function getInt(obj:Dynamic, field:String):Null<Int> {
		var value = getField(obj, field);
		if (value == null) return null;
		return Std.parseInt(Std.string(value));
	}

	private function parseInt(value:Null<String>):Null<Int> {
		if (value == null || value == "") return null;
		return Std.parseInt(value);
	}
}
