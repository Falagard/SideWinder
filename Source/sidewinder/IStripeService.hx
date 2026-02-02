package sidewinder;

import hx.injection.Service;

typedef StripeCustomer = {
	var id:String;
	var email:String;
}

typedef StripeCheckoutSession = {
	var id:String;
	var url:String;
	var customer:String;
	var subscription:Null<String>;
}

typedef StripeSubscription = {
	var id:String;
	var status:String;
	var current_period_end:Null<Int>;
}

interface IStripeService extends Service {
	public function createCustomer(email:String, userId:Int):StripeCustomer;
	public function createSubscriptionCheckoutSession(customerId:String, priceId:String, successUrl:String, cancelUrl:String, userId:Int):StripeCheckoutSession;
	public function retrieveSubscription(subscriptionId:String):StripeSubscription;
	public function cancelSubscription(subscriptionId:String):StripeSubscription;
}
