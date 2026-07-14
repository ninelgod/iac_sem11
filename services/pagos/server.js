const express = require("express");
const morgan = require("morgan");
const jwt = require("jsonwebtoken");
const jwksClient = require("jwks-rsa");
const { Pool } = require("pg");
const { createRouter } = require("./routes/pagos.routes");

// Cliente JWKS para validar tokens de Cognito
let jwksInstance = null;
function getJwksClient() {
  if (!jwksInstance && process.env.COGNITO_USER_POOL_ID) {
    const region = process.env.AWS_REGION || "us-east-2";
    jwksInstance = jwksClient({
      jwksUri: `https://cognito-idp.${region}.amazonaws.com/${process.env.COGNITO_USER_POOL_ID}/.well-known/jwks.json`,
      cache: true,
      cacheMaxEntries: 5,
      cacheMaxAge: 600000,
    });
  }
  return jwksInstance;
}

function verifyJWT(req, res, next) {
  if (process.env.NODE_ENV === "test" || !process.env.COGNITO_USER_POOL_ID) {
    return next();
  }

  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Token de autenticación requerido" });
  }

  const token = authHeader.split(" ")[1];
  const client = getJwksClient();

  jwt.verify(
    token,
    (header, callback) => {
      client.getSigningKey(header.kid, (err, key) => {
        if (err) return callback(err);
        callback(null, key.getPublicKey());
      });
    },
    { algorithms: ["RS256"] },
    (err, decoded) => {
      if (err) return res.status(401).json({ error: "Token inválido o expirado" });
      req.cognitoUser = decoded;
      next();
    }
  );
}

function createApp(pool) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json());
  app.use(morgan(function(tokens, req, res) {
    return JSON.stringify({
      service: "pagos",
      method: tokens.method(req, res),
      url: tokens.url(req, res),
      status: Number(tokens.status(req, res)),
      responseTime: Number(tokens["response-time"](req, res))
    });
  }, { skip: (req) => req.url === "/health" }));
  app.use(verifyJWT);
  app.use("/", createRouter(pool));
  return app;
}

const PORT = Number.parseInt(process.env.PORT || "3001");

async function initSchema(pool) {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS loans (
        id                 SERIAL PRIMARY KEY,
        user_id            INTEGER NOT NULL,
        loan_code          VARCHAR(50),
        bank_name          VARCHAR(255) NOT NULL,
        loan_type          VARCHAR(100) NOT NULL,
        total_amount       DECIMAL(12,2) NOT NULL,
        final_total_amount DECIMAL(12,2),
        monthly_payment    DECIMAL(12,2) NOT NULL,
        payment_type       VARCHAR(100),
        interest_rate      DECIMAL(5,2),
        start_date         DATE NOT NULL,
        end_date           DATE NOT NULL,
        is_active          BOOLEAN DEFAULT true,
        created_at         TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS installments (
        id                 SERIAL PRIMARY KEY,
        loan_id            INTEGER NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
        installment_number INTEGER NOT NULL,
        due_date           DATE NOT NULL,
        amount             DECIMAL(12,2) NOT NULL,
        is_paid            BOOLEAN DEFAULT false,
        paid_at            TIMESTAMPTZ,
        late_fee           DECIMAL(12,2),
        notes              TEXT,
        created_at         TIMESTAMPTZ DEFAULT NOW()
      )
    `);
  } finally {
    client.release();
  }
}

if (require.main === module) {
  const pool = new Pool({
    host:     process.env.DB_HOST,
    database: process.env.DB_NAME,
    user:     process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    port:     5432,
    ssl:      { rejectUnauthorized: false },
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis:       30000,
    max: 10,
  });
  const app = createApp(pool);
  app.listen(PORT, () => {
    console.log(`pagos service listening on port ${PORT}`);
    initSchema(pool).catch((err) => console.warn(`Schema init failed: ${err.message}`));
  });
}

module.exports = { createApp };
