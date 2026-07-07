const request = require("supertest");
const { createApp } = require("./server");

// ─── Inyección de dependencias: pool simulado ─────────────────────────────────
const mockQuery       = jest.fn();
const mockRelease     = jest.fn();
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

// ─── Tests 11-19: Servicio Pagos ─────────────────────────────────────────────

describe("Servicio Pagos — Health", () => {
  test("11. GET /health retorna 200 con status ok y nombre del servicio", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok", service: "pagos" });
  });
});

describe("Servicio Pagos — GET /api/pagos/loans (validaciones)", () => {
  test("12. Sin userId retorna 400", async () => {
    const res = await request(app).get("/api/pagos/loans");
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/userId/);
  });

  test("13. Con userId válido retorna 200 con array de préstamos", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 1, user_id: 5, bank_name: "BCP", installments: [] }],
    });
    const res = await request(app).get("/api/pagos/loans?userId=5");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("loans");
    expect(Array.isArray(res.body.loans)).toBe(true);
  });
});

describe("Servicio Pagos — POST /api/pagos/loans (validaciones)", () => {
  test("14. Sin campos requeridos retorna 400", async () => {
    const res = await request(app).post("/api/pagos/loans").send({ userId: 1 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/requeridos/);
  });

  test("15. Con datos válidos crea el préstamo en transacción y retorna 201", async () => {
    const fakeLoan = { id: 1, user_id: 1, bank_name: "BCP", total_amount: "10000.00" };
    mockClientQuery
      .mockResolvedValueOnce({})                    // BEGIN
      .mockResolvedValueOnce({ rows: [fakeLoan] })  // INSERT loan
      .mockResolvedValueOnce({})                    // INSERT installment (1 cuota)
      .mockResolvedValueOnce({});                   // COMMIT
    const res = await request(app).post("/api/pagos/loans").send({
      userId: 1, bankName: "BCP", loanType: "Personal",
      totalAmount: 10000, installmentAmount: 1000,
      numberOfInstallments: 1, startDate: "2025-01-01", endDate: "2025-12-01",
    });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty("loan");
    expect(res.body.loan.bank_name).toBe("BCP");
  });
});

describe("Servicio Pagos — DELETE /api/pagos/loans/:id", () => {
  test("16. Desactiva el préstamo (soft delete) y retorna 200", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).delete("/api/pagos/loans/1");
    expect(res.status).toBe(200);
    expect(res.body.message).toMatch(/desactivado/);
  });
});

describe("Servicio Pagos — Cuotas (validaciones)", () => {
  test("17. GET /api/pagos/cuotas sin parámetros retorna 400", async () => {
    const res = await request(app).get("/api/pagos/cuotas");
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/loanId|userId/);
  });

  test("18. GET /api/pagos/cuotas con loanId retorna 200 con array de cuotas", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 1, loan_id: 3, installment_number: 1, amount: "500.00", is_paid: false }],
    });
    const res = await request(app).get("/api/pagos/cuotas?loanId=3");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("cuotas");
    expect(Array.isArray(res.body.cuotas)).toBe(true);
  });

  test("19. PATCH /api/pagos/cuotas/:id con cuota inexistente retorna 404", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).patch("/api/pagos/cuotas/999").send({ isPaid: true });
    expect(res.status).toBe(404);
    expect(res.body.error).toMatch(/no encontrada/);
  });
});
