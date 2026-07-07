const request = require("supertest");
const { createApp } = require("./server");

// ─── Inyección de dependencias: pool simulado ─────────────────────────────────
const mockQuery = jest.fn();
const mockPool  = {
  query:   mockQuery,
  connect: jest.fn(),
};

// createApp recibe el pool como dependencia — no se toca el módulo pg real
const app = createApp(mockPool);

const LOANS_ROW = { rows: [{ total: "3", monto_total: "30000.00" }] };
const INST_ROW  = {
  rows: [{
    total_cuotas:    "12",
    total_monto:     "12000.00",
    total_pagado:    "4000.00",
    total_pendiente: "8000.00",
  }],
};

beforeEach(() => {
  jest.clearAllMocks();
});

// ─── Tests 20-25: Servicio Reportes ──────────────────────────────────────────

describe("Servicio Reportes — Health", () => {
  test("20. GET /health retorna 200 con status ok y nombre del servicio", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok", service: "reportes" });
  });
});

describe("Servicio Reportes — GET /api/reportes/resumen", () => {
  test("21. Sin userId retorna 200 con estructura completa de prestamos y cuotas", async () => {
    mockQuery
      .mockResolvedValueOnce(LOANS_ROW)
      .mockResolvedValueOnce(INST_ROW);
    const res = await request(app).get("/api/reportes/resumen");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("prestamos");
    expect(res.body).toHaveProperty("cuotas");
    expect(res.body.prestamos.total).toBe(3);
    expect(res.body.cuotas.total).toBe(12);
    expect(res.body.cuotas.total_pendiente).toBe(8000);
  });

  test("22. Con userId filtra por usuario y pasa el id como parámetro a la query", async () => {
    mockQuery
      .mockResolvedValueOnce(LOANS_ROW)
      .mockResolvedValueOnce(INST_ROW);
    const res = await request(app).get("/api/reportes/resumen?userId=1");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("prestamos");
    expect(mockQuery).toHaveBeenCalledTimes(2);
    expect(mockQuery.mock.calls[0][1]).toEqual([1]);
  });
});

describe("Servicio Reportes — GET /api/reportes/prestamos", () => {
  test("23. Sin userId retorna 200 con todos los préstamos", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 1, bank_name: "BCP", cuotas_pendientes: "2", monto_pendiente: "2000.00" }],
    });
    const res = await request(app).get("/api/reportes/prestamos");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("prestamos");
    expect(Array.isArray(res.body.prestamos)).toBe(true);
    expect(res.body.prestamos).toHaveLength(1);
  });

  test("24. Con userId filtra y pasa el id como parámetro a la query", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).get("/api/reportes/prestamos?userId=99");
    expect(res.status).toBe(200);
    expect(res.body.prestamos).toEqual([]);
    expect(mockQuery).toHaveBeenCalledWith(
      expect.stringContaining("$1"),
      [99],
    );
  });
});

describe("Servicio Reportes — GET /api/reportes/cuotas-vencidas", () => {
  test("25. Retorna 200 con cuotas no pagadas cuya fecha de vencimiento ya pasó", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 5, loan_id: 1, is_paid: false, due_date: "2024-01-01", bank_name: "BCP" }],
    });
    const res = await request(app).get("/api/reportes/cuotas-vencidas");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("cuotas_vencidas");
    expect(Array.isArray(res.body.cuotas_vencidas)).toBe(true);
    expect(res.body.cuotas_vencidas[0].is_paid).toBe(false);
  });
});
