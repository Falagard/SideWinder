-- Stripe subscription fields
ALTER TABLE users ADD COLUMN stripe_customer_id VARCHAR(255);
ALTER TABLE users ADD COLUMN stripe_subscription_id VARCHAR(255);
ALTER TABLE users ADD COLUMN subscription_status VARCHAR(64);
ALTER TABLE users ADD COLUMN subscription_current_period_end BIGINT;

-- Recurring billing logs
CREATE TABLE IF NOT EXISTS recurring_billing_logs (
	id INT AUTO_INCREMENT PRIMARY KEY,
	user_id INT NULL,
	stripe_event_id VARCHAR(255),
	event_type VARCHAR(255),
	subscription_id VARCHAR(255),
	invoice_id VARCHAR(255),
	amount INT,
	currency VARCHAR(16),
	status VARCHAR(64),
	raw_payload TEXT,
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_users_stripe_customer_id ON users(stripe_customer_id);
CREATE INDEX idx_users_stripe_subscription_id ON users(stripe_subscription_id);
CREATE INDEX idx_recurring_billing_logs_user_id ON recurring_billing_logs(user_id);
CREATE INDEX idx_recurring_billing_logs_event_id ON recurring_billing_logs(stripe_event_id);
