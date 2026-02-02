-- Stripe subscription fields
ALTER TABLE users ADD COLUMN stripe_customer_id TEXT;
ALTER TABLE users ADD COLUMN stripe_subscription_id TEXT;
ALTER TABLE users ADD COLUMN subscription_status TEXT;
ALTER TABLE users ADD COLUMN subscription_current_period_end INTEGER;

-- Recurring billing logs
CREATE TABLE IF NOT EXISTS recurring_billing_logs (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER,
	stripe_event_id TEXT,
	event_type TEXT,
	subscription_id TEXT,
	invoice_id TEXT,
	amount INTEGER,
	currency TEXT,
	status TEXT,
	raw_payload TEXT,
	created_at DATETIME DEFAULT (datetime('now')),
	FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_users_stripe_customer_id ON users(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_users_stripe_subscription_id ON users(stripe_subscription_id);
CREATE INDEX IF NOT EXISTS idx_recurring_billing_logs_user_id ON recurring_billing_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_recurring_billing_logs_event_id ON recurring_billing_logs(stripe_event_id);
