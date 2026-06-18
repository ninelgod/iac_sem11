import { type NextRequest, NextResponse } from "next/server"
import { sql } from "@/lib/db"

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get("userId")
    const month = searchParams.get("month")
    const year = searchParams.get("year")

    if (!userId) {
      return NextResponse.json({ error: "userId es requerido" }, { status: 400 })
    }

    let installments

    if (month && year) {
      const monthNum = Number.parseInt(month)
      const yearNum = Number.parseInt(year)
      const lastDay = new Date(yearNum, monthNum, 0).getDate()

      const startDate = `${year}-${String(month).padStart(2, "0")}-01`
      const endDate = `${year}-${String(month).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`

      console.log("[v0] Buscando cuotas del mes", month, "año", year)
      console.log("[v0] Rango:", startDate, "a", endDate)

      installments = await sql`
        SELECT
          i.*,
          CASE
            WHEN i.is_paid = true THEN 'Pagado'
            WHEN i.due_date < CURRENT_DATE THEN 'Vencido'
            ELSE 'Pendiente'
          END as status,
          json_build_object(
            'id', l.id,
            'bankName', l.bank_name,
            'loanType', l.loan_type
          ) as loan
        FROM installments i
        JOIN loans l ON i.loan_id = l.id
        WHERE l.user_id = ${Number.parseInt(userId)}
          AND l.is_active = true
          AND i.due_date >= ${startDate}
          AND i.due_date <= ${endDate}
        ORDER BY i.due_date ASC, l.bank_name ASC
      `
    } else {
      installments = await sql`
        SELECT
          i.*,
          CASE
            WHEN i.is_paid = true THEN 'Pagado'
            WHEN i.due_date < CURRENT_DATE THEN 'Vencido'
            ELSE 'Pendiente'
          END as status,
          json_build_object(
            'id', l.id,
            'bankName', l.bank_name,
            'loanType', l.loan_type
          ) as loan
        FROM installments i
        JOIN loans l ON i.loan_id = l.id
        WHERE l.user_id = ${Number.parseInt(userId)}
          AND l.is_active = true
        ORDER BY i.due_date ASC
      `
    }

    console.log("[v0] Cuotas encontradas:", installments.length)
    if (installments.length > 0) {
      console.log(
        "[v0] Fechas de cuotas:",
        installments.map((i: any) => i.due_date),
      )
    }

    return NextResponse.json({ installments })
  } catch (error) {
    console.error("Error fetching installments:", error)
    return NextResponse.json({ error: "Error al obtener cuotas" }, { status: 500 })
  }
}
