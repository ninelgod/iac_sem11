const request = require("supertest");
const { createApp } = require("./server");

// ─── Inyección de dependencias: pool simulado ─────────────────────────────────
const mockQuery   = jest.fn();
const mockRelease = jest.fn();
const mockClientQuery = jest.fn();
const mockPool = {
  query:   mockQuery,
  connect: jest.fn(),
};

// createApp recibe el pool como dependencia — no se toca el módulo pg real
const app = createApp(mockPool);

beforeEach(() => {
  jest.clearAllMocks();
  mockQuery.mockResolvedValue({ rows: [] });
  mockClientQuery.mockResolvedValue({ rows: [] });
  mockPool.connect.mockResolvedValue({ query: mockClientQuery, release: mockRelease });
});

// ─── Tests 1-10: Servicio Usuarios ───────────────────────────────────────────

describe("Servicio Usuarios — Health", () => {
  test("1. GET /health retorna 200 con status ok y nombre del servicio", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok", service: "usuarios" });
  });
});

describe("Servicio Usuarios — POST /api/auth/login (validaciones)", () => {
  test("2. Sin body retorna 400 con mensaje de campos requeridos", async () => {
    const res = await request(app).post("/api/auth/login").send({});
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/requeridos/);
  });

  test("3. Solo con username, sin password, retorna 400", async () => {
    const res = await request(app).post("/api/auth/login").send({ username: "juan" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBeDefined();
  });

  test("4. Credenciales inválidas retorna 401", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username: "juan", password: "wrong" });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe("Credenciales inválidas");
  });

  test("5. Cuenta bloqueada retorna 429", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{
        id: 1, username: "juan", email: "j@test.com",
        full_name: "Juan", locked_until: new Date(Date.now() + 60_000),
      }],
    });
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username: "juan", password: "pass" });
    expect(res.status).toBe(429);
    expect(res.body.error).toMatch(/bloqueada/);
  });

  test("6. Login exitoso retorna 200 con datos del usuario", async () => {
    const fakeUser = {
      id: 1, username: "juan", email: "j@test.com",
      full_name: "Juan Pérez", locked_until: null,
    };
    mockQuery
      .mockResolvedValueOnce({ rows: [fakeUser] })  // SELECT user
      .mockResolvedValueOnce({ rows: [] });           // UPDATE failed_attempts
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username: "juan", password: "pass123" });
    expect(res.status).toBe(200);
    expect(res.body.user).toMatchObject({ id: 1, username: "juan", email: "j@test.com" });
    expect(res.body.user).not.toHaveProperty("password");
  });
});

describe("Servicio Usuarios — POST /api/auth/change-password (validaciones)", () => {
  test("7. Sin los 3 campos requeridos retorna 400", async () => {
    const res = await request(app)
      .post("/api/auth/change-password")
      .send({ userId: 1 });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Todos los campos son requeridos");
  });

  test("8. Contraseña actual incorrecta retorna 401", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/auth/change-password")
      .send({ userId: 1, currentPassword: "wrongOld", newPassword: "nuevo123" });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe("Contraseña actual incorrecta");
  });
});

describe("Servicio Usuarios — Auth misc", () => {
  test("9. POST /api/auth/request-password-reset siempre retorna 200", async () => {
    const res = await request(app)
      .post("/api/auth/request-password-reset")
      .send({ email: "j@test.com" });
    expect(res.status).toBe(200);
    expect(res.body.message).toBeDefined();
  });

  test("10. POST /api/auth/verify-reset-code retorna 400 (no disponible)", async () => {
    const res = await request(app)
      .post("/api/auth/verify-reset-code")
      .send({ code: "123456" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBeDefined();
  });
});
