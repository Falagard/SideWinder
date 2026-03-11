package sidewinder.interfaces;
import sidewinder.interfaces.IStripeWebhookService.StripeWebhookResult;

import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;


import hx.injection.Service;

typedef StripeWebhookResult = {
	var status:Int;
	var body:Dynamic;
}

interface IStripeWebhookService extends Service {
	public function handleWebhook(rawBody:String, signatureHeader:String):StripeWebhookResult;
}




