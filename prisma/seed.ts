import { PrismaClient } from "@prisma/client"

const prisma = new PrismaClient()

async function main() {
  console.log("[v0] Iniciando seed de la base de datos...")

  const user = await prisma.user.upsert({
    where: { username: "agile" },
    update: {},
    create: {
      username: "agile",
      password: "12345", // En producción, esto debería estar hasheado
    },
  })

  console.log("[v0] Usuario creado:", user)

  const loan1 = await prisma.loan.create({
    data: {
      userId: user.id,
      bankName: "Banco de Crédito del Perú",
      loanType: "Personal",
      totalAmount: 5000,
      monthlyPayment: 500,
      dueDay: 15,
      startDate: new Date("2025-01-15"),
      endDate: new Date("2025-10-15"),
      isActive: true,
    },
  })

  console.log("[v0] Préstamo de ejemplo creado:", loan1)

  const installments = []
  const startDate = new Date(loan1.startDate)
  const endDate = new Date(loan1.endDate)
  const dueDay = loan1.dueDay

  const currentDate = new Date(startDate)
  currentDate.setDate(dueDay)

  let installmentNumber = 1
  const today = new Date()
  today.setHours(0, 0, 0, 0)

  while (currentDate <= endDate) {
    const dueDate = new Date(currentDate)
    const isOverdue = dueDate < today

    installments.push({
      loanId: loan1.id,
      installmentNumber,
      dueDate: dueDate,
      amount: loan1.monthlyPayment,
      isPaid: false,
      lateFee: isOverdue ? 50 : null, // Agregar mora si está vencido
      notes: isOverdue ? "Pago vencido" : null,
    })

    installmentNumber++
    currentDate.setMonth(currentDate.getMonth() + 1)
    currentDate.setDate(dueDay)
  }

  await prisma.installment.createMany({
    data: installments,
  })

  console.log(`[v0] ${installments.length} cuotas creadas para el préstamo de ejemplo`)
  console.log("[v0] Seed completado exitosamente!")
}

main()
  .catch((e) => {
    console.error("[v0] Error en seed:", e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  })
