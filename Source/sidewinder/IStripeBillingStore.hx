package sidewinder;

import hx.injection.Service;

typedef UserBilling = {
	var userId:Int;
	var email:String;
	var stripeCustomerId:Null<String>;
	var stripeSubscriptionId:Null<String>;
	var subscriptionStatus:Null<String>;
	var subscriptionCurrentPeriodEnd:Null<Int>;
}

interface IStripeBillingStore extends Service {
	public function getUserBilling(userId:Int):Null<UserBilling>;
	public function setStripeCustomerId(userId:Int, customerId:String):Void;
	public function setSubscription(userId:Int, subscriptionId:String, status:Null<String>, currentPeriodEnd:Null<Int>):Void;
	public function findUserIdByCustomerId(customerId:String):Null<Int>;
	public function updateSubscriptionByCustomerId(customerId:String, subscriptionId:String, status:Null<String>, currentPeriodEnd:Null<Int>):Null<Int>;
	public function logBillingEvent(userId:Null<Int>, stripeEventId:String, eventType:String, subscriptionId:Null<String>, invoiceId:Null<String>, amount:Null<Int>, currency:Null<String>, status:Null<String>, rawPayload:String):Void;
}
