import { type NextRequest, NextResponse } from "next/server"
import { sql } from "@/lib/db"

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const body = await request.json()
    const { isPaid, lateFee, notes } = body
    const installmentId = Number.parseInt(params.id)

    // Construir la consulta de actualización dinámicamente
    const updates: string[] = []
    const values: any[] = []

    if (isPaid !== undefined) {
      updates.push(`is_paid = ${isPaid}`)
      updates.push(`paid_date = ${isPaid ? "CURRENT_DATE" : "NULL"}`)
    }

    if (lateFee !== undefined) {
      updates.push(`late_fee = ${lateFee}`)
    }

    if (notes !== undefined) {
      values.push(notes)
      updates.push(`notes = $${values.length}`)
    }

    if (updates.length === 0) {
      return NextResponse.json({ error: "No hay campos para actualizar" }, { status: 400 })
    }

    const installment = await sql`
      UPDATE installments
      SET ${sql(updates.join(", "))}
      WHERE id = ${installmentId}
      RETURNING *
    `

    console.log("[v0] Cuota actualizada:", installmentId, { isPaid, lateFee, notes })

    return NextResponse.json({ installment: installment[0] })
  } catch (error) {
    console.error("Error updating installment:", error)
    return NextResponse.json({ error: "Error al actualizar cuota" }, { status: 500 })
  }
}
