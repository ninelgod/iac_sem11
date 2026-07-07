const { Router } = require("express");
const { createPagosController } = require("../controllers/pagos.controller");

function createRouter(pool) {
  const router = Router();
  const ctrl = createPagosController(pool);

  router.get("/health", ctrl.health);
  router.get("/api/pagos/loans", ctrl.getLoans);
  router.post("/api/pagos/loans", ctrl.createLoan);
  router.delete("/api/pagos/loans/:id", ctrl.deleteLoan);
  router.get("/api/pagos/cuotas", ctrl.getInstallments);
  router.patch("/api/pagos/cuotas/:id", ctrl.updateInstallment);

  return router;
}

module.exports = { createRouter };
