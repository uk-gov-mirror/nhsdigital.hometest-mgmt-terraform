-- +goose Up
ALTER TABLE order_status
DROP COLUMN IF EXISTS order_reference;


-- +goose Down
ALTER TABLE order_status
ADD COLUMN IF NOT EXISTS order_reference bigint;
