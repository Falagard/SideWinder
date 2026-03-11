# Environment Variables

This document lists all environment variables used by SideWinder and their purposes.

## Email Notifications (SendGrid)

### SENDGRID_API_KEY
- **Required for:** Email notification functionality
- **Description:** SendGrid API key for sending emails
- **Example:** `SG.xxxxxxxxxxxxxxxxxxxxxxxx`
- **Documentation:** See [NOTIFICATION_SYSTEM.md](NOTIFICATION_SYSTEM.md)

### SENDGRID_FROM_EMAIL
- **Required for:** Email notification functionality
- **Description:** Default "from" email address for outgoing emails
- **Example:** `noreply@yourdomain.com`
- **Documentation:** See [NOTIFICATION_SYSTEM.md](NOTIFICATION_SYSTEM.md)

## Stripe Subscriptions

### STRIPE_SECRET_KEY
- **Required for:** Stripe subscription API calls
- **Description:** Stripe secret API key
- **Example:** `your_stripe_secret_key`

### STRIPE_WEBHOOK_SECRET
- **Required for:** Stripe webhook signature verification
- **Description:** Stripe webhook signing secret
- **Example:** `your_stripe_webhook_secret`

### STRIPE_PRICE_ID
- **Required for:** Stripe Checkout session creation if not provided in request
- **Description:** Default Stripe price ID for subscription
- **Example:** `price_1XXXXXXXXXXXXXXX`

## OAuth Authentication

### Google OAuth

#### GOOGLE_CLIENT_ID
- **Required for:** Google OAuth integration
- **Description:** Google OAuth 2.0 client ID
- **Example:** `123456789-abcdefghijklmnop.apps.googleusercontent.com`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

#### GOOGLE_CLIENT_SECRET
- **Required for:** Google OAuth integration
- **Description:** Google OAuth 2.0 client secret
- **Example:** `GOCSPX-xxxxxxxxxxxxxxxxxxxxxxx`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

#### GOOGLE_REDIRECT_URI
- **Required for:** Google OAuth integration
- **Description:** OAuth callback URL for Google authentication
- **Default:** `http://localhost:8000/oauth/callback/google`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

### GitHub OAuth

#### GITHUB_CLIENT_ID
- **Required for:** GitHub OAuth integration
- **Description:** GitHub OAuth application client ID
- **Example:** `Iv1.abcdefghijklmnop`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

#### GITHUB_CLIENT_SECRET
- **Required for:** GitHub OAuth integration
- **Description:** GitHub OAuth application client secret
- **Example:** `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

#### GITHUB_REDIRECT_URI
- **Required for:** GitHub OAuth integration
- **Description:** OAuth callback URL for GitHub authentication
- **Default:** `http://localhost:8000/oauth/callback/github`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

### Microsoft OAuth

#### MICROSOFT_CLIENT_ID
- **Required for:** Microsoft OAuth integration
- **Description:** Microsoft Azure AD application (client) ID
- **Example:** `12345678-1234-1234-1234-123456789012`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

#### MICROSOFT_CLIENT_SECRET
- **Required for:** Microsoft OAuth integration
- **Description:** Microsoft Azure AD client secret
- **Example:** `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

#### MICROSOFT_REDIRECT_URI
- **Required for:** Microsoft OAuth integration
- **Description:** OAuth callback URL for Microsoft authentication
- **Default:** `http://localhost:8000/oauth/callback/microsoft`
- **Documentation:** See [AUTH_README.md](AUTH_README.md)

## Database Configuration

### DB_HOST
- **Required for:** MySQL database backend
- **Description:** MySQL server hostname or IP address
- **Default:** `localhost`
- **Documentation:** See [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md)

### DB_PORT
- **Required for:** MySQL database backend
- **Description:** MySQL server port number
- **Default:** `3306`
- **Documentation:** See [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md)

### DB_NAME
- **Required for:** MySQL database backend
- **Description:** MySQL database name
- **Default:** `sidewinder`
- **Documentation:** See [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md)

### DB_USER
- **Required for:** MySQL database backend
- **Description:** MySQL username for authentication
- **Default:** `root`
- **Documentation:** See [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md)

### DB_PASS
- **Required for:** MySQL database backend
- **Description:** MySQL password for authentication
- **Default:** (empty string)
- **Documentation:** See [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md)

## System Environment Variables

### APPDATA (Windows)
- **Used by:** SecureTokenStorage
- **Description:** Windows application data directory
- **Automatically set by:** Windows OS
- **Purpose:** Store secure OAuth tokens on Windows

### HOME (Linux/macOS)
- **Used by:** SecureTokenStorage
- **Description:** User's home directory
- **Automatically set by:** Linux/macOS OS
- **Purpose:** Store secure OAuth tokens on Unix-like systems

### XDG_DATA_HOME (Linux)
- **Used by:** SecureTokenStorage
- **Description:** XDG Base Directory for user data
- **Automatically set by:** Some Linux distributions
- **Purpose:** Alternative location for secure token storage on Linux

## Setting Environment Variables

### Linux/macOS

#### Temporary (current session only)
```bash
export SENDGRID_API_KEY="your-key-here"
export SENDGRID_FROM_EMAIL="noreply@yourdomain.com"
```

#### Permanent (add to ~/.bashrc or ~/.zshrc)
```bash
echo 'export SENDGRID_API_KEY="your-key-here"' >> ~/.bashrc
echo 'export SENDGRID_FROM_EMAIL="noreply@yourdomain.com"' >> ~/.bashrc
source ~/.bashrc
```

### Windows

#### Temporary (current session only)
```cmd
set SENDGRID_API_KEY=your-key-here
set SENDGRID_FROM_EMAIL=noreply@yourdomain.com
```

#### Permanent (System Properties)
1. Open System Properties → Advanced → Environment Variables
2. Add new user or system variables
3. Restart your terminal/IDE

### Using .env Files (Development)

While SideWinder doesn't automatically load `.env` files, you can create a helper script:

**set-env.sh** (Linux/macOS):
```bash
#!/bin/bash
source .env
export $(cut -d= -f1 .env)
lime test hl
```

**.env** file:
```bash
SENDGRID_API_KEY=your-key-here
SENDGRID_FROM_EMAIL=noreply@yourdomain.com
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
```

**Note:** Never commit `.env` files with sensitive data to version control!

## Checking Current Values

### Linux/macOS
```bash
echo $SENDGRID_API_KEY
printenv | grep SENDGRID
```

### Windows
```cmd
echo %SENDGRID_API_KEY%
set | findstr SENDGRID
```

## Related Documentation

- [AUTH_README.md](AUTH_README.md) - OAuth authentication setup
- [NOTIFICATION_SYSTEM.md](NOTIFICATION_SYSTEM.md) - Email notification configuration
- [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md) - Database configuration
- [OAUTH_QUICK_START.md](OAUTH_QUICK_START.md) - Quick OAuth setup guide
