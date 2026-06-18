import { type NextRequest, NextResponse } from "next/server"
import { sql } from "@/lib/db"

export async function GET(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const loanId = Number.parseInt(params.id)

    const loanResult = await sql`
      SELECT 
        l.*,
        (
          SELECT json_agg(i.* ORDER BY i.installment_number)
          FROM installments i
          WHERE i.loan_id = l.id
        ) as installments
      FROM loans l
      WHERE l.id = ${loanId}
    `

    if (loanResult.length === 0) {
      return NextResponse.json({ error: "Préstamo no encontrado" }, { status: 404 })
    }

    return NextResponse.json({ loan: loanResult[0] })
  } catch (error) {
    console.error("Error fetching loan:", error)
    return NextResponse.json({ error: "Error al obtener préstamo" }, { status: 500 })
  }
}

export async function PUT(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const loanId = Number.parseInt(params.id)
    const body = await request.json()
    const { bankName, loanType, totalAmount, installmentAmount, numberOfInstallments, dueDay, startDate, endDate } =
      body

    if (
      !bankName ||
      !loanType ||
      !totalAmount ||
      !installmentAmount ||
      !numberOfInstallments ||
      !dueDay ||
      !startDate ||
      !endDate
    ) {
      return NextResponse.json({ error: "Todos los campos son requeridos" }, { status: 400 })
    }

    const start = new Date(startDate)
    const end = new Date(endDate)

    if (end <= start) {
      return NextResponse.json(
        { error: "La fecha de finalización debe ser posterior a la fecha de inicio" },
        { status: 400 },
      )
    }

    // Eliminar cuotas existentes
    await sql`DELETE FROM installments WHERE loan_id = ${loanId}`

    // Actualizar préstamo
    await sql`
      UPDATE loans
      SET 
        bank_name = ${bankName},
        loan_type = ${loanType},
        total_amount = ${totalAmount},
        monthly_payment = ${installmentAmount},
        due_day = ${dueDay},
        start_date = ${startDate},
        end_date = ${endDate}
      WHERE id = ${loanId}
    `

    // Generar nuevas cuotas
    let currentDate = new Date(start.getFullYear(), start.getMonth(), dueDay)

    if (currentDate < start) {
      currentDate.setMonth(currentDate.getMonth() + 1)
    }

    for (let i = 1; i <= numberOfInstallments; i++) {
      if (currentDate > end) break

      const dueDateStr = currentDate.toISOString().split("T")[0]

      await sql`
        INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
        VALUES (${loanId}, ${i}, ${dueDateStr}, ${installmentAmount}, false)
      `

      currentDate = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, dueDay)
    }

    // Obtener préstamo actualizado con cuotas
    const loanResult = await sql`
      SELECT 
        l.*,
        (
          SELECT json_agg(i.* ORDER BY i.installment_number)
          FROM installments i
          WHERE i.loan_id = l.id
        ) as installments
      FROM loans l
      WHERE l.id = ${loanId}
    `

    return NextResponse.json({ loan: loanResult[0] })
  } catch (error) {
    console.error("Error updating loan:", error)
    return NextResponse.json({ error: "Error al actualizar préstamo" }, { status: 500 })
  }
}

export async function DELETE(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const loanId = Number.parseInt(params.id)

    await sql`DELETE FROM loans WHERE id = ${loanId}`

    return NextResponse.json({ message: "Préstamo eliminado exitosamente" })
  } catch (error) {
    console.error("Error deleting loan:", error)
    return NextResponse.json({ error: "Error al eliminar préstamo" }, { status: 500 })
  }
}
