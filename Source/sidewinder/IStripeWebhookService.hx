package sidewinder;

import hx.injection.Service;

typedef StripeWebhookResult = {
	var status:Int;
	var body:Dynamic;
}

interface IStripeWebhookService extends Service {
	public function handleWebhook(rawBody:String, signatureHeader:String):StripeWebhookResult;
}
