const express = require("express");

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", service: "usuarios" });
});

app.get("/usuarios", (req, res) => {
  res.status(200).json({
    service: "usuarios",
    db_host: process.env.DB_HOST || null,
    db_name: process.env.DB_NAME || null,
    usuarios: [
      { id: 1, nombre: "Juan Perez", email: "juan@example.com" },
      { id: 2, nombre: "Maria Lopez", email: "maria@example.com" },
    ],
  });
});

app.listen(port, () => {
  console.log(`usuarios service listening on port ${port}`);
});
