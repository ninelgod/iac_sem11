-- Crear tabla de cuotas individuales
CREATE TABLE IF NOT EXISTS installments (
  id SERIAL PRIMARY KEY,
  loan_id INTEGER REFERENCES loans(id) ON DELETE CASCADE,
  installment_number INTEGER NOT NULL,
  due_date DATE NOT NULL,
  amount DECIMAL(12, 2) NOT NULL,
  is_paid BOOLEAN DEFAULT false,
  paid_date DATE,
  late_fee DECIMAL(12, 2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Crear índices
CREATE INDEX IF NOT EXISTS idx_installments_loan_id ON installments(loan_id);
CREATE INDEX IF NOT EXISTS idx_installments_due_date ON installments(due_date);
CREATE INDEX IF NOT EXISTS idx_installments_is_paid ON installments(is_paid);
