package sidewinder.interfaces;
import sidewinder.interfaces.INotificationService.EmailOptions;
import sidewinder.interfaces.INotificationService.EmailAttachment;

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


/**
 * Interface for notification services (email, SMS, push notifications, etc.)
 */
import hx.injection.Service;

/**
 * Interface for notification services (email, SMS, push notifications, etc.)
 */
interface INotificationService extends Service {
	/**
	 * Send an email notification
	 * @param to Recipient email address
	 * @param subject Email subject
	 * @param body Email body (can be plain text or HTML)
	 * @param isHtml Whether the body is HTML (default: false)
	 * @param callback Optional callback function (error) -> Void
	 */
	function sendEmail(to:String, subject:String, body:String, ?isHtml:Bool, ?callback:(err:Dynamic) -> Void):Void;

	/**
	 * Send an email notification with CC and BCC support
	 * @param to Recipient email address
	 * @param subject Email subject
	 * @param body Email body
	 * @param options Additional options (cc, bcc, from, fromName, replyTo, attachments, etc.)
	 * @param callback Optional callback function (error) -> Void
	 */
	function sendEmailAdvanced(to:String, subject:String, body:String, options:EmailOptions, ?callback:(err:Dynamic) -> Void):Void;
}

/**
 * Email options for advanced sending
 */
typedef EmailOptions = {
	?cc:Array<String>,
	?bcc:Array<String>,
	?from:String,
	?fromName:String,
	?replyTo:String,
	?isHtml:Bool,
	?attachments:Array<EmailAttachment>
}

/**
 * Email attachment structure
 */
typedef EmailAttachment = {
	filename:String,
	content:String, // Base64 encoded content
	type:String, // MIME type
	?disposition:String // "attachment" or "inline"
}




