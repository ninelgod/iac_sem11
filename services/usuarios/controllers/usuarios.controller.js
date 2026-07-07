function createUsuariosController(pool) {
  return {
    health(_req, res) {
      res.json({ status: "ok", service: "usuarios" });
    },

    async login(req, res) {
      const { username, password } = req.body || {};
      if (!username || !password)
        return res.status(400).json({ error: "Usuario y contraseña son requeridos" });

      try {
        const r = await pool.query(
          `SELECT id, username, email, full_name, locked_until
           FROM users WHERE username = $1 AND password = $2`,
          [username, password]
        );
        if (r.rows.length === 0)
          return res.status(401).json({ error: "Credenciales inválidas" });

        const user = r.rows[0];
        if (user.locked_until && new Date(user.locked_until) > new Date())
          return res.status(429).json({ error: "Cuenta bloqueada temporalmente" });

        await pool.query(
          "UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = $1",
          [user.id]
        );
        return res.json({
          user: { id: user.id, username: user.username, email: user.email, fullName: user.full_name },
        });
      } catch (err) {
        console.error("Login error:", err.message);
        return res.status(500).json({ error: "Error interno del servidor" });
      }
    },

    async changePassword(req, res) {
      const { userId, currentPassword, newPassword } = req.body || {};
      if (!userId || !currentPassword || !newPassword)
        return res.status(400).json({ error: "Todos los campos son requeridos" });

      try {
        const check = await pool.query(
          "SELECT id FROM users WHERE id = $1 AND password = $2",
          [userId, currentPassword]
        );
        if (check.rows.length === 0)
          return res.status(401).json({ error: "Contraseña actual incorrecta" });

        await pool.query("UPDATE users SET password = $1 WHERE id = $2", [newPassword, userId]);
        return res.json({ message: "Contraseña actualizada correctamente" });
      } catch (err) {
        console.error("Change password error:", err.message);
        return res.status(500).json({ error: "Error interno del servidor" });
      }
    },

    requestPasswordReset(_req, res) {
      res.json({ message: "Si el usuario existe, recibirá un correo con instrucciones" });
    },

    verifyResetCode(_req, res) {
      res.status(400).json({ error: "Funcionalidad no disponible en esta versión" });
    },

    async getAll(_req, res) {
      try {
        const r = await pool.query(
          "SELECT id, username, email, full_name, created_at FROM users ORDER BY id"
        );
        return res.json({ usuarios: r.rows });
      } catch (err) {
        console.error("Get usuarios error:", err.message);
        return res.status(500).json({ error: "Error al obtener usuarios" });
      }
    },

    async getById(req, res) {
      try {
        const r = await pool.query(
          "SELECT id, username, email, full_name, created_at FROM users WHERE id = $1",
          [req.params.id]
        );
        if (r.rows.length === 0)
          return res.status(404).json({ error: "Usuario no encontrado" });
        return res.json({ usuario: r.rows[0] });
      } catch (err) {
        console.error("Get usuario error:", err.message);
        return res.status(500).json({ error: "Error al obtener usuario" });
      }
    },

    async create(req, res) {
      const { username, password, email, fullName } = req.body || {};
      if (!username || !password)
        return res.status(400).json({ error: "Usuario y contraseña son requeridos" });

      try {
        const r = await pool.query(
          `INSERT INTO users (username, password, email, full_name)
           VALUES ($1, $2, $3, $4)
           RETURNING id, username, email, full_name, created_at`,
          [username, password, email || null, fullName || null]
        );
        return res.status(201).json({ usuario: r.rows[0] });
      } catch (err) {
        if (err.code === "23505")
          return res.status(409).json({ error: "El usuario ya existe" });
        console.error("Create usuario error:", err.message);
        return res.status(500).json({ error: "Error al crear usuario" });
      }
    },
  };
}

module.exports = { createUsuariosController };
