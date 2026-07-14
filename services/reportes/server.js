const express = require("express");
const morgan = require("morgan");
const { Pool } = require("pg");
const { createRouter } = require("./routes/reportes.routes");

function createApp(pool) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json());
  app.use(morgan(function(tokens, req, res) {
    return JSON.stringify({
      service: "reportes",
      method: tokens.method(req, res),
      url: tokens.url(req, res),
      status: Number(tokens.status(req, res)),
      responseTime: Number(tokens["response-time"](req, res))
    });
  }, { skip: (req) => req.url === "/health" }));
  app.use("/", createRouter(pool));
  return app;
}

const PORT = Number.parseInt(process.env.PORT || "3002");

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
  app.listen(PORT, () => console.log(`reportes service listening on port ${PORT}`));
}

module.exports = { createApp };
