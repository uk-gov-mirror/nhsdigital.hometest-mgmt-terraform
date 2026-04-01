-- +goose Up
CREATE TABLE IF NOT EXISTS notification_audit
(
  audit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_reference uuid NOT NULL,
  notify_message_id varchar(255),
  event_code varchar(50) NOT NULL,
  routing_plan_id uuid,
  correlation_id uuid NOT NULL,
  status varchar(50) NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT current_timestamp,
  CONSTRAINT uq_notification_audit_message_reference_status
  UNIQUE (message_reference, status)
);

CREATE INDEX IF NOT EXISTS idx_notification_audit_message_reference_created_at
ON notification_audit (message_reference, created_at);


-- +goose Down
DROP INDEX IF EXISTS idx_notification_audit_message_reference_created_at;
DROP TABLE IF EXISTS notification_audit;
