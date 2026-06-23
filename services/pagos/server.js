const express = require("express");

const app = express();
const port = process.env.PORT || 3001;

app.use(express.json());

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", service: "pagos" });
});

app.get("/pagos", (req, res) => {
  res.status(200).json({
    service: "pagos",
    db_host: process.env.DB_HOST || null,
    db_name: process.env.DB_NAME || null,
    pagos: [
      { id: 1, prestamo_id: 10, monto: 150.0, estado: "pagado" },
      { id: 2, prestamo_id: 11, monto: 300.5, estado: "pendiente" },
    ],
  });
});

app.listen(port, () => {
  console.log(`pagos service listening on port ${port}`);
});
