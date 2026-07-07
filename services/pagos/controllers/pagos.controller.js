function createPagosController(pool) {
  return {
    health(_req, res) {
      res.json({ status: "ok", service: "pagos" });
    },

    async getLoans(req, res) {
      const { userId } = req.query;
      if (!userId)
        return res.status(400).json({ error: "userId es requerido" });

      try {
        const r = await pool.query(
          `SELECT l.*,
             (SELECT json_agg(i.* ORDER BY i.installment_number)
              FROM installments i WHERE i.loan_id = l.id AND i.is_paid = false) AS installments
           FROM loans l
           WHERE l.user_id = $1 AND l.is_active = true
           ORDER BY l.created_at DESC`,
          [Number.parseInt(userId)]
        );
        return res.json({ loans: r.rows });
      } catch (err) {
        console.error("Get loans error:", err.message);
        return res.status(500).json({ error: "Error al obtener préstamos" });
      }
    },

    async createLoan(req, res) {
      const {
        userId, loanCode, bankName, loanType, totalAmount,
        installmentAmount, numberOfInstallments, paymentType, interestRate,
        startDate, endDate,
      } = req.body || {};

      if (!userId || !bankName || !loanType || !totalAmount || !installmentAmount || !startDate || !endDate)
        return res.status(400).json({ error: "Todos los campos son requeridos" });

      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const n = Number.parseInt(numberOfInstallments) || 1;
        const finalTotal = Number.parseFloat(installmentAmount) * n;

        const loanResult = await client.query(
          `INSERT INTO loans (user_id, loan_code, bank_name, loan_type, total_amount,
             final_total_amount, monthly_payment, payment_type, interest_rate, start_date, end_date)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *`,
          [userId, loanCode || null, bankName, loanType, totalAmount, finalTotal,
           installmentAmount, paymentType || null, interestRate || null, startDate, endDate]
        );
        const loanId = loanResult.rows[0].id;

        const start = new Date(startDate);
        for (let i = 1; i <= n; i++) {
          const due = new Date(start);
          due.setMonth(due.getMonth() + (i - 1));
          await client.query(
            "INSERT INTO installments (loan_id, installment_number, due_date, amount) VALUES ($1,$2,$3,$4)",
            [loanId, i, due.toISOString().split("T")[0], installmentAmount]
          );
        }
        await client.query("COMMIT");
        return res.status(201).json({ loan: loanResult.rows[0] });
      } catch (err) {
        await client.query("ROLLBACK");
        console.error("Create loan error:", err.message);
        return res.status(500).json({ error: "Error al crear préstamo" });
      } finally {
        client.release();
      }
    },

    async deleteLoan(req, res) {
      try {
        await pool.query("UPDATE loans SET is_active = false WHERE id = $1", [req.params.id]);
        return res.json({ message: "Préstamo desactivado correctamente" });
      } catch (err) {
        console.error("Delete loan error:", err.message);
        return res.status(500).json({ error: "Error al eliminar préstamo" });
      }
    },

    async getInstallments(req, res) {
      const { loanId, userId } = req.query;
      try {
        let r;
        if (loanId) {
          r = await pool.query(
            "SELECT * FROM installments WHERE loan_id = $1 ORDER BY installment_number",
            [Number.parseInt(loanId)]
          );
        } else if (userId) {
          r = await pool.query(
            `SELECT i.* FROM installments i
             JOIN loans l ON l.id = i.loan_id
             WHERE l.user_id = $1 ORDER BY i.due_date`,
            [Number.parseInt(userId)]
          );
        } else {
          return res.status(400).json({ error: "loanId o userId es requerido" });
        }
        return res.json({ cuotas: r.rows });
      } catch (err) {
        console.error("Get installments error:", err.message);
        return res.status(500).json({ error: "Error al obtener cuotas" });
      }
    },

    async updateInstallment(req, res) {
      const { isPaid, notes } = req.body || {};
      try {
        const r = await pool.query(
          `UPDATE installments
           SET is_paid = $1, paid_at = $2, notes = COALESCE($3, notes)
           WHERE id = $4 RETURNING *`,
          [isPaid, isPaid ? new Date() : null, notes || null, req.params.id]
        );
        if (r.rows.length === 0)
          return res.status(404).json({ error: "Cuota no encontrada" });
        return res.json({ cuota: r.rows[0] });
      } catch (err) {
        console.error("Update installment error:", err.message);
        return res.status(500).json({ error: "Error al actualizar cuota" });
      }
    },
  };
}

module.exports = { createPagosController };
