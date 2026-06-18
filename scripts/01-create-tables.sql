-- Agregando tabla de cuotas (installments) que faltaba
-- Crear schema public si no existe
CREATE SCHEMA IF NOT EXISTS public;

-- Asegurar que estamos usando el schema public
SET search_path TO public;

-- Eliminar tablas existentes si existen
DROP TABLE IF EXISTS installments CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS loans CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Crear tabla de usuarios
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Crear tabla de préstamos
CREATE TABLE loans (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  bank_name VARCHAR(100) NOT NULL,
  loan_type VARCHAR(100) NOT NULL,
  total_amount DECIMAL(12, 2) NOT NULL,
  monthly_payment DECIMAL(12, 2) NOT NULL,
  due_day INTEGER NOT NULL CHECK (due_day >= 1 AND due_day <= 31),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Crear tabla de cuotas individuales
CREATE TABLE installments (
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

-- Crear índices para mejorar el rendimiento
CREATE INDEX idx_loans_user_id ON loans(user_id);
CREATE INDEX idx_loans_due_day ON loans(due_day);
CREATE INDEX idx_installments_loan_id ON installments(loan_id);
CREATE INDEX idx_installments_due_date ON installments(due_date);
CREATE INDEX idx_installments_is_paid ON installments(is_paid);
