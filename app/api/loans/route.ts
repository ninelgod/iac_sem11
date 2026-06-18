import { type NextRequest, NextResponse } from "next/server"
import { sql } from "@/lib/db"

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get("userId")

    if (!userId) {
      return NextResponse.json({ error: "userId es requerido" }, { status: 400 })
    }

    const loans = await sql`
      SELECT
        l.*,
        (
          SELECT json_agg(i.*)
          FROM (
            SELECT * FROM installments
            WHERE loan_id = l.id AND is_paid = false
            ORDER BY due_date ASC
            LIMIT 1
          ) i
        ) as installments
      FROM loans l
      WHERE l.user_id = ${Number.parseInt(userId)} AND l.is_active = true
      ORDER BY l.payment_type ASC
    `

    console.log("[v0] Préstamos encontrados:", loans.length)

    return NextResponse.json({ loans })
  } catch (error) {
    console.error("Error fetching loans:", error)
    return NextResponse.json({ error: "Error al obtener préstamos" }, { status: 500 })
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const {
      userId,
      loanCode,
      bankName,
      loanType,
      totalAmount,
      installmentAmount,
      numberOfInstallments,
      paymentType,
      interestRate,
      startDate,
      endDate,
    } = body

    if (
      !userId ||
      !bankName ||
      !loanType ||
      !totalAmount ||
      !installmentAmount ||
      !numberOfInstallments ||
      !paymentType ||
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

    console.log("[v0] Creando préstamo con", numberOfInstallments, "cuotas")

    // Calcular el total final usando la fórmula correcta (installmentAmount * numberOfInstallments)
    const finalTotalAmount = installmentAmount * numberOfInstallments

    // Crear el préstamo
    const loanResult = await sql`
      INSERT INTO loans (user_id, loan_code, bank_name, loan_type, total_amount, final_total_amount, monthly_payment, payment_type, interest_rate, start_date, end_date, is_active)
      VALUES (${Number.parseInt(userId)}, ${loanCode}, ${bankName}, ${loanType}, ${totalAmount}, ${finalTotalAmount}, ${installmentAmount}, ${paymentType}, ${interestRate}, ${startDate}, ${endDate}, true)
      RETURNING *
    `

    const loan = loanResult[0]
    console.log("[v0] Préstamo creado con ID:", loan.id)

    // Crear cuotas basadas en el tipo de pago especificado
    let cuotasCreadas = 0
    let currentDate = new Date(start)

    for (let i = 1; i <= numberOfInstallments; i++) {
      // Verificar que no exceda la fecha de fin
      if (currentDate > end) {
        console.log("[v0] Fecha excede el fin del préstamo, deteniendo en cuota", i)
        break
      }

      let dueDate: Date

      if (paymentType.includes("Plazo fijo")) {
        // Extraer el día del mes del string "Plazo fijo (día X)"
        const match = paymentType.match(/día (\d+)/);
        const dueDay = match ? parseInt(match[1]) : 15;

        // Calcular la fecha de pago para este mes
        dueDate = new Date(currentDate.getFullYear(), currentDate.getMonth(), dueDay);

        // Si el día de pago ya pasó en el mes actual, mover al siguiente mes
        if (dueDate < currentDate) {
          dueDate.setMonth(dueDate.getMonth() + 1);
        }

        // Para la siguiente iteración, avanzar al siguiente mes
        currentDate = new Date(dueDate);
        currentDate.setMonth(currentDate.getMonth() + 1);
      } else if (paymentType.includes("Plazo de acuerdo a días")) {
        // Extraer el intervalo de días del string "Plazo de acuerdo a días (cada X días)"
        const match = paymentType.match(/cada (\d+) días/);
        const daysInterval = match ? parseInt(match[1]) : 30;

        dueDate = new Date(currentDate);
        // Para la siguiente iteración, avanzar el intervalo
        currentDate.setDate(currentDate.getDate() + daysInterval);
      } else if (paymentType === "Fin de mes") {
        // Para fin de mes, calcular el último día del mes actual
        dueDate = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 0); // Último día del mes

        // Para la siguiente iteración, avanzar al siguiente mes
        currentDate.setMonth(currentDate.getMonth() + 1);
      } else {
        // Fallback: asumir mensual
        dueDate = new Date(currentDate);
        currentDate.setMonth(currentDate.getMonth() + 1);
      }

      const dueDateStr = dueDate.toISOString().split("T")[0]

      await sql`
        INSERT INTO installments (loan_id, installment_number, due_date, amount, is_paid)
        VALUES (${loan.id}, ${i}, ${dueDateStr}, ${installmentAmount}, false)
      `

      console.log("[v0] Cuota", i, "creada para:", dueDateStr, "tipo de pago:", paymentType)
      cuotasCreadas++
    }

    console.log("[v0] Total de cuotas creadas:", cuotasCreadas)

    // Obtener el préstamo con sus cuotas
    const loanWithInstallments = await sql`
      SELECT 
        l.*,
        (
          SELECT json_agg(i.* ORDER BY i.installment_number)
          FROM installments i
          WHERE i.loan_id = l.id
        ) as installments
      FROM loans l
      WHERE l.id = ${loan.id}
    `

    return NextResponse.json({ loan: loanWithInstallments[0] })
  } catch (error) {
    console.error("Error creating loan:", error)
    return NextResponse.json({ error: "Error al crear préstamo" }, { status: 500 })
  }
}
