# Notification System - SendGrid Email Integration

## Overview

The SideWinder notification system provides a flexible interface for sending notifications through various channels. Currently, it includes a SendGrid implementation for sending emails.

## Features

- **Email Notifications**: Send emails via SendGrid API v3
- **HTML Support**: Send both plain text and HTML emails
- **Advanced Options**: Support for CC, BCC, reply-to, custom from addresses, and attachments
- **Dependency Injection**: Integrated with SideWinder's DI system
- **Error Handling**: Comprehensive error handling and logging

## Setup

### 1. Get SendGrid API Key

1. Sign up for a [SendGrid account](https://sendgrid.com/)
2. Create an API key with "Mail Send" permissions
3. Verify a sender email address or domain

### 2. Configure Environment Variables

Set the following environment variables:

```bash
export SENDGRID_API_KEY="your-sendgrid-api-key-here"
export SENDGRID_FROM_EMAIL="noreply@yourdomain.com"
```

### 3. Run the Application

```bash
lime test hl
```

The notification service will be automatically registered in the DI container if the environment variables are set.

## Usage

### Basic Email Sending

```haxe
// Get the notification service from DI
var notificationService = DI.get(INotificationService);

// Send a plain text email
notificationService.sendEmail(
    "recipient@example.com",
    "Test Email",
    "This is a test email body",
    false, // isHtml
    function(err:Dynamic) {
        if (err != null) {
            trace("Error sending email: " + err);
        } else {
            trace("Email sent successfully!");
        }
    }
);
```

### HTML Email

```haxe
var htmlBody = '<html><body><h1>Welcome!</h1><p>This is an <strong>HTML</strong> email.</p></body></html>';

notificationService.sendEmail(
    "recipient@example.com",
    "HTML Email Test",
    htmlBody,
    true, // isHtml
    function(err:Dynamic) {
        if (err == null) {
            trace("HTML email sent!");
        }
    }
);
```

### Advanced Email Options

```haxe
var options:EmailOptions = {
    cc: ["cc1@example.com", "cc2@example.com"],
    bcc: ["bcc@example.com"],
    from: "custom@yourdomain.com",
    fromName: "Custom Sender Name",
    replyTo: "reply@yourdomain.com",
    isHtml: true,
    attachments: [
        {
            filename: "document.pdf",
            content: "base64EncodedContent...",
            type: "application/pdf",
            disposition: "attachment"
        }
    ]
};

notificationService.sendEmailAdvanced(
    "recipient@example.com",
    "Email with Attachments",
    "<h1>Check out this document</h1>",
    options,
    function(err:Dynamic) {
        if (err == null) {
            trace("Advanced email sent!");
        }
    }
);
```

## API Endpoint

### POST /send-email

Send an email via the HTTP API.

**Request Body:**
```json
{
    "to": "recipient@example.com",
    "subject": "Test Email",
    "body": "Email message body",
    "isHtml": false
}
```

**Success Response (200):**
```json
{
    "success": true,
    "message": "Email sent successfully"
}
```

**Error Response (400/500):**
```json
{
    "error": "Error description",
    "details": "Additional error details"
}
```

## Testing

### Using the Demo Page

1. Start the server: `lime test hl`
2. Open your browser to: `http://127.0.0.1:8000/email_demo.html`
3. Fill in the recipient, subject, and message
4. Click "Send Email"

### Using curl

```bash
curl -X POST http://127.0.0.1:8000/send-email \
  -H "Content-Type: application/json" \
  -d '{
    "to": "recipient@example.com",
    "subject": "Test from curl",
    "body": "This is a test email",
    "isHtml": false
  }'
```

### Using Postman

Import the `SideWinder.postman_collection.json` file and add a new request:

- **Method**: POST
- **URL**: `http://127.0.0.1:8000/send-email`
- **Headers**: `Content-Type: application/json`
- **Body** (raw JSON):
  ```json
  {
    "to": "recipient@example.com",
    "subject": "Test Email",
    "body": "Hello from Postman",
    "isHtml": false
  }
  ```

## Architecture

### Interface: INotificationService

Located in: `Source/sidewinder/INotificationService.hx`

Defines the contract for notification services:
- `sendEmail()`: Basic email sending
- `sendEmailAdvanced()`: Advanced email with full options

### Implementation: SendGridNotificationService

Located in: `Source/sidewinder/SendGridNotificationService.hx`

SendGrid implementation that:
- Uses SendGrid API v3
- Supports all SendGrid features (CC, BCC, attachments, etc.)
- Provides async callback support
- Includes comprehensive error handling
- Integrates with HybridLogger for monitoring

### Dependency Injection

The notification service is registered in `Main.hx`:

```haxe
DI.init(c -> {
    // ... other services ...
    
    var sendgridApiKey = Sys.getEnv("SENDGRID_API_KEY");
    var defaultFromEmail = Sys.getEnv("SENDGRID_FROM_EMAIL");
    if (sendgridApiKey != null && defaultFromEmail != null) {
        c.addSingleton(INotificationService, () -> new SendGridNotificationService(
            sendgridApiKey, 
            defaultFromEmail, 
            "SideWinder App",
            HybridLogger.instance()
        ));
    }
});
```

## Future Enhancements

Potential additions to the notification system:

1. **SMS Notifications**: Integrate Twilio or similar SMS provider
2. **Push Notifications**: Add Firebase Cloud Messaging or Apple Push Notification service
3. **Slack/Discord**: Webhook integrations for team notifications
4. **Email Templates**: Template engine for reusable email layouts
5. **Queue System**: Background job processing for bulk emails
6. **Rate Limiting**: Prevent spam and manage SendGrid quotas
7. **Email Tracking**: Open/click tracking integration
8. **Alternative Providers**: Support for Mailgun, AWS SES, etc.

## Troubleshooting

### Email Not Sending

1. **Check environment variables**: Ensure `SENDGRID_API_KEY` and `SENDGRID_FROM_EMAIL` are set
2. **Verify API key**: Test your API key at SendGrid dashboard
3. **Check sender verification**: Ensure the from email is verified in SendGrid
4. **Review logs**: Check logs in `Export/hl/bin/logs/` for errors
5. **Network access**: Ensure the server can reach `https://api.sendgrid.com`

### Service Not Available Error

If you get a 503 error, the notification service is not configured. Check:
- Environment variables are set before starting the server
- No typos in variable names
- API key has proper permissions

### SendGrid API Errors

Common SendGrid API errors:
- **401 Unauthorized**: Invalid API key
- **403 Forbidden**: API key lacks necessary permissions
- **400 Bad Request**: Invalid email address or malformed request

## Links

- [SendGrid API Documentation](https://docs.sendgrid.com/api-reference/mail-send/mail-send)
- [SendGrid Dashboard](https://app.sendgrid.com/)
- [SideWinder Project Documentation](./README.md)
