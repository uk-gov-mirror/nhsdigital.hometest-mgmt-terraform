-- +goose Up
INSERT INTO la_supplier_offering (offering_id, supplier_id, test_code, la_code, effective_from)
VALUES
('a5e6f7a8-5678-4def-8abc-56789abcdefa', '11111111-1111-4111-8111-111111111111', '31676001', '1440', DATE '2026-03-06'),
('c7a8b9c0-7890-4fab-8cde-789abcdefabc', '77777777-7777-4777-8777-777777777777', '31676001', '4230', DATE '2026-03-06')
ON CONFLICT (la_code, supplier_id, test_code) DO NOTHING;

-- +goose Down
DELETE FROM la_supplier_offering
WHERE offering_id IN (
  'a5e6f7a8-5678-4def-8abc-56789abcdefa',
  'c7a8b9c0-7890-4fab-8cde-789abcdefabc'
);
