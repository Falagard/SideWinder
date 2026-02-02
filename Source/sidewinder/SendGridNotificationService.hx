package sidewinder;

import haxe.Http;
import haxe.Json;
import haxe.io.Bytes;

/**
 * SendGrid implementation of the notification service
 * Requires a SendGrid API key to be set via environment variable or configuration
 */
class SendGridNotificationService implements INotificationService {
    private var apiKey:String;
    private var defaultFrom:String;
    private var defaultFromName:String;
    private var logger:HybridLogger;
    
    /**
     * Constructor
     * @param apiKey SendGrid API key
     * @param defaultFrom Default sender email address
     * @param defaultFromName Default sender name
     * @param logger Logger instance
     */
    public function new(apiKey:String, defaultFrom:String, ?defaultFromName:String, ?logger:HybridLogger) {
        this.apiKey = apiKey;
        this.defaultFrom = defaultFrom;
        this.defaultFromName = defaultFromName != null ? defaultFromName : "SideWinder App";
        this.logger = logger;
        
        if (this.apiKey == null || this.apiKey == "") {
            throw "SendGrid API key is required";
        }
        if (this.defaultFrom == null || this.defaultFrom == "") {
            throw "Default sender email address is required";
        }
    }
    
    /**
     * Send an email notification
     */
    public function sendEmail(to:String, subject:String, body:String, ?isHtml:Bool, ?callback:(err:Dynamic)->Void):Void {
        var options:EmailOptions = {
            isHtml: isHtml != null ? isHtml : false
        };
        sendEmailAdvanced(to, subject, body, options, callback);
    }
    
    /**
     * Send an email notification with advanced options
     */
    public function sendEmailAdvanced(to:String, subject:String, body:String, options:EmailOptions, ?callback:(err:Dynamic)->Void):Void {
        try {
            var fromEmail = options.from != null ? options.from : defaultFrom;
            var fromName = options.fromName != null ? options.fromName : defaultFromName;
            var isHtml = options.isHtml != null ? options.isHtml : false;
            
            // Build SendGrid API v3 payload
            var payload:Dynamic = {
                personalizations: [
                    {
                        to: [{ email: to }]
                    }
                ],
                from: {
                    email: fromEmail,
                    name: fromName
                },
                subject: subject,
                content: [
                    {
                        type: isHtml ? "text/html" : "text/plain",
                        value: body
                    }
                ]
            };
            
            // Add CC if provided
            if (options.cc != null && options.cc.length > 0) {
                payload.personalizations[0].cc = [for (email in options.cc) { email: email }];
            }
            
            // Add BCC if provided
            if (options.bcc != null && options.bcc.length > 0) {
                payload.personalizations[0].bcc = [for (email in options.bcc) { email: email }];
            }
            
            // Add reply-to if provided
            if (options.replyTo != null) {
                payload.reply_to = { email: options.replyTo };
            }
            
            // Add attachments if provided
            if (options.attachments != null && options.attachments.length > 0) {
                payload.attachments = [
                    for (att in options.attachments) {
                        {
                            content: att.content,
                            filename: att.filename,
                            type: att.type,
                            disposition: att.disposition != null ? att.disposition : "attachment"
                        }
                    }
                ];
            }
            
            var jsonPayload = Json.stringify(payload);
            
            if (logger != null) {
                logger.info('Sending email via SendGrid to: $to, subject: $subject');
            }
            
            // Make HTTP request to SendGrid API
            var http = new Http("https://api.sendgrid.com/v3/mail/send");
            http.setHeader("Authorization", 'Bearer $apiKey');
            http.setHeader("Content-Type", "application/json");
            http.setPostData(jsonPayload);
            
            http.onError = function(error:String) {
                if (logger != null) {
                    logger.error('SendGrid API error: $error');
                }
                if (callback != null) {
                    callback(error);
                }
            };
            
            http.onStatus = function(status:Int) {
                if (status >= 200 && status < 300) {
                    if (logger != null) {
                        logger.info('Email sent successfully via SendGrid (status: $status)');
                    }
                    if (callback != null) {
                        callback(null);
                    }
                } else {
                    var errorMsg = 'SendGrid API returned status: $status';
                    if (logger != null) {
                        logger.error(errorMsg);
                    }
                    if (callback != null) {
                        callback(errorMsg);
                    }
                }
            };
            
            http.request(true); // POST request
            
        } catch (e:Dynamic) {
            if (logger != null) {
                logger.error('Exception sending email: $e');
            }
            if (callback != null) {
                callback(e);
            }
        }
    }
}
