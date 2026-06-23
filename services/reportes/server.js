const express = require("express");

const app = express();
const port = process.env.PORT || 3002;

app.use(express.json());

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", service: "reportes" });
});

app.get("/reportes", (req, res) => {
  res.status(200).json({
    service: "reportes",
    db_host: process.env.DB_HOST || null,
    db_name: process.env.DB_NAME || null,
    resumen: {
      total_prestamos: 25,
      total_pagado: 4500.75,
      total_pendiente: 1200.0,
    },
  });
});

app.listen(port, () => {
  console.log(`reportes service listening on port ${port}`);
});
