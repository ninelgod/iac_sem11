const {
  CognitoIdentityProviderClient,
  InitiateAuthCommand,
  AdminCreateUserCommand,
  AdminSetUserPasswordCommand,
} = require("@aws-sdk/client-cognito-identity-provider");

const cognito = new CognitoIdentityProviderClient({
  region: process.env.AWS_REGION || "us-east-2",
});

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
        // Obtener email del usuario en la BD local (Cognito usa email como identificador)
        const r = await pool.query(
          "SELECT id, username, email, full_name FROM users WHERE username = $1",
          [username]
        );

        if (r.rows.length === 0)
          return res.status(401).json({ error: "Credenciales inválidas" });

        const user = r.rows[0];

        if (!user.email)
          return res.status(401).json({ error: "Credenciales inválidas" });

        // Autenticar contra Cognito con email + password
        const authResult = await cognito.send(new InitiateAuthCommand({
          AuthFlow: "USER_PASSWORD_AUTH",
          ClientId: process.env.COGNITO_CLIENT_ID,
          AuthParameters: {
            USERNAME: user.email,
            PASSWORD: password,
          },
        }));

        const tokens = authResult.AuthenticationResult;

        return res.json({
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            fullName: user.full_name,
          },
          accessToken: tokens.AccessToken,
          idToken: tokens.IdToken,
          refreshToken: tokens.RefreshToken,
        });
      } catch (err) {
        if (err.name === "NotAuthorizedException" || err.name === "UserNotFoundException") {
          return res.status(401).json({ error: "Credenciales inválidas" });
        }
        console.error("Login error:", err.message);
        return res.status(500).json({ error: "Error interno del servidor" });
      }
    },

    async changePassword(req, res) {
      const { userId, currentPassword, newPassword } = req.body || {};
      if (!userId || !currentPassword || !newPassword)
        return res.status(400).json({ error: "Todos los campos son requeridos" });

      try {
        // Verificar password actual via Cognito
        const userRow = await pool.query(
          "SELECT email FROM users WHERE id = $1",
          [userId]
        );

        if (userRow.rows.length === 0)
          return res.status(404).json({ error: "Usuario no encontrado" });

        const email = userRow.rows[0].email;

        // Verificar contraseña actual con Cognito
        await cognito.send(new InitiateAuthCommand({
          AuthFlow: "USER_PASSWORD_AUTH",
          ClientId: process.env.COGNITO_CLIENT_ID,
          AuthParameters: { USERNAME: email, PASSWORD: currentPassword },
        }));

        // Cambiar contraseña en Cognito
        await cognito.send(new AdminSetUserPasswordCommand({
          UserPoolId: process.env.COGNITO_USER_POOL_ID,
          Username: email,
          Password: newPassword,
          Permanent: true,
        }));

        return res.json({ message: "Contraseña actualizada correctamente" });
      } catch (err) {
        if (err.name === "NotAuthorizedException") {
          return res.status(401).json({ error: "Contraseña actual incorrecta" });
        }
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
      if (!username || !password || !email)
        return res.status(400).json({ error: "Usuario, contraseña y email son requeridos" });

      try {
        // Crear usuario en Cognito (email como identificador)
        await cognito.send(new AdminCreateUserCommand({
          UserPoolId: process.env.COGNITO_USER_POOL_ID,
          Username: email,
          UserAttributes: [
            { Name: "email", Value: email },
            { Name: "email_verified", Value: "true" },
          ],
          MessageAction: "SUPPRESS",
        }));

        // Establecer contraseña permanente (saltarse el flujo de contraseña temporal)
        await cognito.send(new AdminSetUserPasswordCommand({
          UserPoolId: process.env.COGNITO_USER_POOL_ID,
          Username: email,
          Password: password,
          Permanent: true,
        }));

        // Insertar en BD local para mantener el user_id entero que usa la tabla loans
        const r = await pool.query(
          `INSERT INTO users (username, password, email, full_name)
           VALUES ($1, $2, $3, $4)
           RETURNING id, username, email, full_name, created_at`,
          [username, password, email, fullName || null]
        );

        return res.status(201).json({ usuario: r.rows[0] });
      } catch (err) {
        if (err.code === "23505")
          return res.status(409).json({ error: "El usuario ya existe" });
        if (err.name === "UsernameExistsException")
          return res.status(409).json({ error: "El email ya está registrado" });
        console.error("Create usuario error:", err.message);
        return res.status(500).json({ error: "Error al crear usuario" });
      }
    },
  };
}

module.exports = { createUsuariosController };
