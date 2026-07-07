const { Router } = require("express");
const { createUsuariosController } = require("../controllers/usuarios.controller");

function createRouter(pool) {
  const router = Router();
  const ctrl = createUsuariosController(pool);

  router.get("/health", ctrl.health);
  router.post("/api/auth/login", ctrl.login);
  router.post("/api/auth/change-password", ctrl.changePassword);
  router.post("/api/auth/request-password-reset", ctrl.requestPasswordReset);
  router.post("/api/auth/verify-reset-code", ctrl.verifyResetCode);
  router.get("/api/usuarios", ctrl.getAll);
  router.get("/api/usuarios/:id", ctrl.getById);
  router.post("/api/usuarios", ctrl.create);

  return router;
}

module.exports = { createRouter };
