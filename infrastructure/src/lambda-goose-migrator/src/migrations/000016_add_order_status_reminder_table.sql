-- +goose Up
CREATE TYPE reminder_status AS ENUM
(
  'SCHEDULED',
  'QUEUED',
  'FAILED',
  'CANCELLED'
);

CREATE TABLE
IF NOT EXISTS order_status_reminder
(
  reminder_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_uid uuid NOT NULL REFERENCES test_order
  (order_uid) ON
  DELETE CASCADE,
  trigger_status varchar(50)
  NOT NULL REFERENCES status_type
  (status_code),
  reminder_number smallint NOT NULL CHECK
  (reminder_number >= 1),
  status reminder_status NOT NULL,
  triggered_at timestamp
  with time zone NOT NULL,
  sent_at timestamp
  with time zone,
  created_at timestamp
  with time zone NOT NULL DEFAULT current_timestamp,
  CONSTRAINT uq_order_status_reminder
  UNIQUE
  (order_uid, trigger_status, reminder_number)
);

CREATE INDEX
IF NOT EXISTS idx_order_status_reminder_status_triggered_at
ON order_status_reminder
(status, triggered_at);


-- +goose Down
DROP INDEX IF EXISTS idx_order_status_reminder_status_triggered_at;
DROP TABLE IF EXISTS order_status_reminder;
DROP TYPE IF EXISTS reminder_status;
