-- +goose Up
CREATE TABLE session
(
  session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refresh_token_id uuid NOT NULL,
  nhs_access_token text NOT NULL,
  issuer text NOT NULL,
  audience text NOT NULL,
  subject text NOT NULL,
  family_name varchar(255) NOT NULL,
  given_name varchar(255) NOT NULL,
  identity_proofing_level varchar(10) NOT NULL,
  email varchar(320) NOT NULL,
  email_verified boolean NOT NULL,
  phone_number_verified boolean NOT NULL,
  birth_date date NOT NULL,
  nhs_number varchar(10) NOT NULL,
  gp_ods_code varchar(20) NOT NULL,
  session_created_at timestamp with time zone NOT NULL DEFAULT current_timestamp,
  last_refresh_at timestamp with time zone NOT NULL DEFAULT current_timestamp,
  max_expires_at timestamp with time zone NOT NULL,
  CONSTRAINT uq_session_refresh_token_id UNIQUE (refresh_token_id),
  CONSTRAINT chk_session_nhs_number_format CHECK (nhs_number ~ '^[0-9]{10}$')
);

CREATE INDEX idx_session_max_expires_at
ON session (max_expires_at);


-- +goose Down
DROP INDEX IF EXISTS idx_session_max_expires_at;
DROP TABLE IF EXISTS session;
