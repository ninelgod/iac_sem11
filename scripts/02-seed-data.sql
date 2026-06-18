-- Insertar usuario inicial (agile con contraseña 12345)
INSERT INTO users (username, password) 
VALUES ('agile', '12345')
ON CONFLICT (username) DO NOTHING;

-- Agregando préstamo de ejemplo con cuotas generadas automáticamente
-- Insertar préstamo de ejemplo
INSERT INTO loans (user_id, bank_name, loan_type, total_amount, monthly_payment, due_day, start_date, end_date, is_active)
SELECT 
  u.id,
  'Banco Nacional',
  'Préstamo Personal',
  25000.00,
  2500.00,
  15,
  '2024-10-01',
  '2025-08-15',
  true
FROM users u WHERE u.username = 'agile'
ON CONFLICT DO NOTHING;

-- Generar cuotas para el préstamo de ejemplo (10 cuotas mensuales)
INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  1,
  '2024-10-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  2,
  '2024-11-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  3,
  '2024-12-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  4,
  '2025-01-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  5,
  '2025-02-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  6,
  '2025-03-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  7,
  '2025-04-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  8,
  '2025-05-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  9,
  '2025-06-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;

INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
SELECT 
  l.id,
  10,
  '2025-07-15',
  2500.00,
  false
FROM loans l 
JOIN users u ON l.user_id = u.id 
WHERE u.username = 'agile' AND l.bank_name = 'Banco Nacional'
ON CONFLICT DO NOTHING;
