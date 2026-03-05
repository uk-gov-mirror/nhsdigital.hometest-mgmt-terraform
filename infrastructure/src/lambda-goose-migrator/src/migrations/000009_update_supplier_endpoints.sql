-- +goose Up
ALTER TABLE supplier
ADD COLUMN IF NOT EXISTS results_path varchar(255);

UPDATE supplier
SET
  service_url = 'https://hometest-staging.prevx.io/',
  oauth_token_path = '/api/oauth/token',
  results_path = '/api/results'
WHERE supplier_id = '11111111-1111-4111-8111-111111111111';

UPDATE supplier
SET
  results_path = '/nhs_home_test/results',
  order_path = '/nhs_home_test/order'
WHERE supplier_id = '77777777-7777-4777-8777-777777777777';

-- +goose Down
UPDATE supplier
SET
  service_url = 'https://func-nhshometest-staging.azurewebsites.net/',
  oauth_token_path = '/api/oauth'
WHERE supplier_id = '11111111-1111-4111-8111-111111111111';

UPDATE supplier
SET
  order_path = '/order'
WHERE supplier_id = '77777777-7777-4777-8777-777777777777';

ALTER TABLE supplier
DROP COLUMN IF EXISTS results_path;
