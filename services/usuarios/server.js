const express = require("express");
const { Pool } = require("pg");
const { createRouter } = require("./routes/usuarios.routes");

function createApp(pool) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json());
  app.use("/", createRouter(pool));
  return app;
}

const PORT = Number.parseInt(process.env.PORT || "3000");

async function initSchema(pool) {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id              SERIAL PRIMARY KEY,
        username        VARCHAR(100) UNIQUE NOT NULL,
        password        VARCHAR(255) NOT NULL,
        email           VARCHAR(255),
        full_name       VARCHAR(255),
        failed_attempts INTEGER DEFAULT 0,
        locked_until    TIMESTAMPTZ,
        created_at      TIMESTAMPTZ DEFAULT NOW()
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
    console.log(`usuarios service listening on port ${PORT}`);
    initSchema(pool).catch((err) => console.warn(`Schema init failed: ${err.message}`));
  });
}

module.exports = { createApp };
