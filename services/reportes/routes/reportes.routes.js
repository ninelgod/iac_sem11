const { Router } = require("express");
const { createReportesController } = require("../controllers/reportes.controller");

function createRouter(pool) {
  const router = Router();
  const ctrl = createReportesController(pool);

  router.get("/health", ctrl.health);
  router.get("/api/reportes/resumen", ctrl.getResumen);
  router.get("/api/reportes/prestamos", ctrl.getPrestamos);
  router.get("/api/reportes/cuotas-vencidas", ctrl.getCuotasVencidas);

  return router;
}

module.exports = { createRouter };
