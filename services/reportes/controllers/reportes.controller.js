function createReportesController(pool) {
  return {
    health(_req, res) {
      res.json({ status: "ok", service: "reportes" });
    },

    async getResumen(req, res) {
      const userId = req.query.userId ? Number.parseInt(req.query.userId) : null;
      try {
        let loansQ, instQ;
        if (userId) {
          loansQ = pool.query(
            "SELECT COUNT(*) AS total, COALESCE(SUM(total_amount),0) AS monto_total FROM loans WHERE user_id = $1 AND is_active = true",
            [userId]
          );
          instQ = pool.query(
            `SELECT
               COUNT(*) AS total_cuotas,
               COALESCE(SUM(amount),0) AS total_monto,
               COALESCE(SUM(amount) FILTER (WHERE is_paid),0) AS total_pagado,
               COALESCE(SUM(amount) FILTER (WHERE NOT is_paid),0) AS total_pendiente
             FROM installments i
             JOIN loans l ON l.id = i.loan_id
             WHERE l.user_id = $1 AND l.is_active = true`,
            [userId]
          );
        } else {
          loansQ = pool.query(
            "SELECT COUNT(*) AS total, COALESCE(SUM(total_amount),0) AS monto_total FROM loans WHERE is_active = true"
          );
          instQ = pool.query(
            `SELECT
               COUNT(*) AS total_cuotas,
               COALESCE(SUM(amount),0) AS total_monto,
               COALESCE(SUM(amount) FILTER (WHERE is_paid),0) AS total_pagado,
               COALESCE(SUM(amount) FILTER (WHERE NOT is_paid),0) AS total_pendiente
             FROM installments i
             JOIN loans l ON l.id = i.loan_id
             WHERE l.is_active = true`
          );
        }
        const [lr, ir] = await Promise.all([loansQ, instQ]);
        return res.json({
          prestamos: {
            total:       Number.parseInt(lr.rows[0].total),
            monto_total: Number.parseFloat(lr.rows[0].monto_total),
          },
          cuotas: {
            total:           Number.parseInt(ir.rows[0].total_cuotas),
            total_monto:     Number.parseFloat(ir.rows[0].total_monto),
            total_pagado:    Number.parseFloat(ir.rows[0].total_pagado),
            total_pendiente: Number.parseFloat(ir.rows[0].total_pendiente),
          },
        });
      } catch (err) {
        console.error("Resumen error:", err.message);
        return res.status(500).json({ error: "Error al obtener resumen" });
      }
    },

    async getPrestamos(req, res) {
      const userId = req.query.userId ? Number.parseInt(req.query.userId) : null;
      try {
        const params = userId ? [userId] : [];
        const where  = userId ? "WHERE l.user_id = $1" : "";
        const r = await pool.query(
          `SELECT l.*,
             COUNT(i.id) FILTER (WHERE NOT i.is_paid) AS cuotas_pendientes,
             COALESCE(SUM(i.amount) FILTER (WHERE NOT i.is_paid), 0) AS monto_pendiente
           FROM loans l
           LEFT JOIN installments i ON i.loan_id = l.id
           ${where}
           GROUP BY l.id
           ORDER BY l.created_at DESC`,
          params
        );
        return res.json({ prestamos: r.rows });
      } catch (err) {
        console.error("Prestamos report error:", err.message);
        return res.status(500).json({ error: "Error al obtener reporte de préstamos" });
      }
    },

    async getCuotasVencidas(req, res) {
      const userId = req.query.userId ? Number.parseInt(req.query.userId) : null;
      try {
        const params = userId ? [userId] : [];
        const extra  = userId ? "AND l.user_id = $1" : "";
        const r = await pool.query(
          `SELECT i.*, l.bank_name, l.loan_type
           FROM installments i
           JOIN loans l ON l.id = i.loan_id
           WHERE i.is_paid = false AND i.due_date < CURRENT_DATE ${extra}
           ORDER BY i.due_date ASC`,
          params
        );
        return res.json({ cuotas_vencidas: r.rows });
      } catch (err) {
        console.error("Cuotas vencidas error:", err.message);
        return res.status(500).json({ error: "Error al obtener cuotas vencidas" });
      }
    },
  };
}

module.exports = { createReportesController };
