package sidewinder;

class StripeBillingStore implements IStripeBillingStore {
	private var db:IDatabaseService;

	public function new() {
		db = DI.get(IDatabaseService);
	}

	public function getUserBilling(userId:Int):Null<UserBilling> {
		var params = new Map<String, Dynamic>();
		params.set("id", userId);
		var rs = db.requestWithParams("SELECT id, email, stripe_customer_id, stripe_subscription_id, subscription_status, subscription_current_period_end FROM users WHERE id = @id", params);
		var rec = rs.next();
		if (rec == null) return null;
		return {
			userId: rec.id,
			email: rec.email,
			stripeCustomerId: rec.stripe_customer_id,
			stripeSubscriptionId: rec.stripe_subscription_id,
			subscriptionStatus: rec.subscription_status,
			subscriptionCurrentPeriodEnd: parseInt(rec.subscription_current_period_end)
		};
	}

	public function setStripeCustomerId(userId:Int, customerId:String):Void {
		var params = new Map<String, Dynamic>();
		params.set("id", userId);
		params.set("stripe_customer_id", customerId);
		db.execute("UPDATE users SET stripe_customer_id = @stripe_customer_id WHERE id = @id", params);
	}

	public function setSubscription(userId:Int, subscriptionId:String, status:Null<String>, currentPeriodEnd:Null<Int>):Void {
		var params = new Map<String, Dynamic>();
		params.set("id", userId);
		params.set("stripe_subscription_id", subscriptionId);
		params.set("subscription_status", status);
		params.set("subscription_current_period_end", currentPeriodEnd);
		db.execute("UPDATE users SET stripe_subscription_id = @stripe_subscription_id, subscription_status = @subscription_status, subscription_current_period_end = @subscription_current_period_end WHERE id = @id", params);
	}

	public function findUserIdByCustomerId(customerId:String):Null<Int> {
		if (customerId == null || customerId == "") return null;
		var params = new Map<String, Dynamic>();
		params.set("stripe_customer_id", customerId);
		var rs = db.requestWithParams("SELECT id FROM users WHERE stripe_customer_id = @stripe_customer_id", params);
		var rec = rs.next();
		if (rec == null) return null;
		return rec.id;
	}

	public function updateSubscriptionByCustomerId(customerId:String, subscriptionId:String, status:Null<String>, currentPeriodEnd:Null<Int>):Null<Int> {
		var userId = findUserIdByCustomerId(customerId);
		if (userId == null) return null;
		setSubscription(userId, subscriptionId, status, currentPeriodEnd);
		return userId;
	}

	public function logBillingEvent(userId:Null<Int>, stripeEventId:String, eventType:String, subscriptionId:Null<String>, invoiceId:Null<String>, amount:Null<Int>, currency:Null<String>, status:Null<String>, rawPayload:String):Void {
		var params = new Map<String, Dynamic>();
		params.set("user_id", userId);
		params.set("stripe_event_id", stripeEventId);
		params.set("event_type", eventType);
		params.set("subscription_id", subscriptionId);
		params.set("invoice_id", invoiceId);
		params.set("amount", amount);
		params.set("currency", currency);
		params.set("status", status);
		params.set("raw_payload", rawPayload);
		db.execute("INSERT INTO recurring_billing_logs (user_id, stripe_event_id, event_type, subscription_id, invoice_id, amount, currency, status, raw_payload) VALUES (@user_id, @stripe_event_id, @event_type, @subscription_id, @invoice_id, @amount, @currency, @status, @raw_payload)", params);
	}

	private function parseInt(value:Dynamic):Null<Int> {
		if (value == null) return null;
		return Std.parseInt(Std.string(value));
	}
}
