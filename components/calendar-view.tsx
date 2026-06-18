"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import {
  ChevronLeft,
  ChevronRight,
  CheckCircle2,
  XCircle,
  AlertCircle,
  Pencil,
  Trash2,
  ChevronUp,
  ChevronDown,
  MoreHorizontal,
} from "lucide-react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"

interface Loan {
  id: number
  bank_name: string
  loan_type: string
  total_amount: number
  monthly_payment: number
  payment_type: string
  start_date: string
  end_date: string
  is_active: boolean
}

interface CalendarViewProps {
  userId: number
}

export function CalendarView({ userId }: CalendarViewProps) {
  const router = useRouter()
  const [currentDate, setCurrentDate] = useState(new Date())
  const [loans, setLoans] = useState<Loan[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState("")
  const [selectedDay, setSelectedDay] = useState<number | null>(null)
  const [dayDetailsOpen, setDayDetailsOpen] = useState(false)
  const [selectedMonth, setSelectedMonth] = useState(currentDate.getMonth())
  const [selectedYear, setSelectedYear] = useState(currentDate.getFullYear())

  useEffect(() => {
    loadLoans()
  }, [userId])

  const loadLoans = async () => {
    try {
      setIsLoading(true)
      const response = await fetch(`/api/loans?userId=${userId}`)
      const data = await response.json()

      if (!response.ok) {
        setError(data.error || "Error al cargar préstamos")
        setIsLoading(false)
        return
      }

      console.log("[v0] Préstamos cargados para calendario:", data.loans.length)
      setLoans(data.loans)
      setIsLoading(false)
    } catch (err) {
      setError("Error de conexión")
      setIsLoading(false)
    }
  }

  const getDaysInMonth = (date: Date) => {
    return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
  }

  const getFirstDayOfMonth = (date: Date) => {
    return new Date(date.getFullYear(), date.getMonth(), 1).getDay()
  }

  const getInstallmentsForDay = (day: number) => {
    const year = currentDate.getFullYear()
    const month = currentDate.getMonth() + 1 // 1-based for string
    const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`

    console.log(`[v0] Buscando cuotas para día ${day}, fecha objetivo: ${dateStr}`)

    const installments: any[] = []

    // Generar cuotas basadas en los préstamos y su tipo de pago
    loans.forEach((loan) => {
      const startDate = new Date(loan.start_date)
      const endDate = new Date(loan.end_date)
      const currentMonth = new Date(year, month - 1, day)

      // Verificar si estamos dentro del rango del préstamo
      if (currentMonth >= startDate && currentMonth <= endDate) {
        // Parsear el día de pago del payment_type
        let dueDay: number;
        if (typeof loan.payment_type === 'string') {
          if (loan.payment_type.includes('Plazo fijo')) {
            // Extraer el día del string "Plazo fijo (día X)"
            const match = loan.payment_type.match(/día (\d+)/);
            dueDay = match ? parseInt(match[1]) : 15;
          } else if (loan.payment_type.includes('Plazo de acuerdo a días')) {
            // Para pagos cada X días, calcular dinámicamente basado en la fecha de inicio
            const startDate = new Date(loan.start_date);
            const daysInterval = parseInt(loan.payment_type.match(/cada (\d+) días/)?.[1] || "30");

            // Calcular cuántos intervalos han pasado desde la fecha de inicio
            const currentDate = new Date(year, month - 1, day);
            const daysDiff = Math.floor((currentDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24));
            const intervalsPassed = Math.floor(daysDiff / daysInterval);

            // Calcular la fecha de pago esperada
            const expectedPaymentDate = new Date(startDate);
            expectedPaymentDate.setDate(startDate.getDate() + intervalsPassed * daysInterval);

            // Si coincide con el día actual, marcar como día de pago
            dueDay = expectedPaymentDate.getDate();
          } else if (loan.payment_type === 'Fin de mes') {
            // Para fin de mes, el día de pago es el último día del mes
            dueDay = new Date(year, month, 0).getDate(); // Último día del mes
          } else {
            // Fallback: extraer número del string
            dueDay = parseInt(loan.payment_type.match(/\d+/)?.[0] || "15");
          }
        } else {
          // Si es número, usar directamente
          dueDay = loan.payment_type;
        }

        // Verificar si el día coincide con el día de pago del préstamo
        if (day === dueDay) {
          // Calcular el número de cuota basado en la fecha
          const monthsDiff = (year - startDate.getFullYear()) * 12 + (month - 1 - startDate.getMonth())
          const installmentNumber = monthsDiff + 1

          // Solo incluir si es una cuota válida (no antes del inicio)
          if (installmentNumber >= 1) {
            const dueDate = new Date(year, month - 1, day)
            const today = new Date()
            today.setHours(0, 0, 0, 0)
            dueDate.setHours(0, 0, 0, 0)

            let status = 'Pendiente'
            if (dueDate < today) {
              status = 'Vencido'
            }

            installments.push({
              id: `${loan.id}-${installmentNumber}`, // ID único
              loan_id: loan.id,
              due_date: dateStr,
              is_paid: false, // Por ahora asumimos no pagado
              status: status,
              loan: {
                id: loan.id,
                bankName: loan.bank_name,
                loanType: loan.loan_type,
                monthlyPayment: loan.monthly_payment,
                totalAmount: loan.total_amount
              }
            })

            console.log(`[v0] ✓ Día ${day} tiene cuota: ${loan.bank_name} - ${status} (Cuota #${installmentNumber})`)
          }
        }
      }
    })

    console.log(`[v0] Día ${day} tiene ${installments.length} cuotas`)
    return installments
  }

  const navigateMonth = (direction: "prev" | "next") => {
    setCurrentDate((prev) => {
      const newDate = new Date(prev)
      if (direction === "prev") {
        newDate.setMonth(newDate.getMonth() - 1)
      } else {
        newDate.setMonth(newDate.getMonth() + 1)
      }
      return newDate
    })
  }

  const handleDayClick = (day: number) => {
    setSelectedDay(day)
    setDayDetailsOpen(true)
  }

  const handleMonthChange = (month: string) => {
    const monthIndex = parseInt(month)
    setSelectedMonth(monthIndex)
    setCurrentDate(new Date(selectedYear, monthIndex, 1))
  }

  const handleYearChange = (year: string) => {
    const yearValue = parseInt(year)
    setSelectedYear(yearValue)
    setCurrentDate(new Date(yearValue, selectedMonth, 1))
  }

  const renderCalendar = () => {
    const daysInMonth = getDaysInMonth(currentDate)
    const firstDay = getFirstDayOfMonth(currentDate)
    const days = []

    // Días vacíos al inicio
    for (let i = 0; i < firstDay; i++) {
      days.push(
        <div key={`empty-${i}`} className="h-20 w-full p-1">
          <div className="h-full w-full rounded-lg bg-gray-50 dark:bg-gray-900"></div>
        </div>
      )
    }

    // Días del mes
    for (let day = 1; day <= daysInMonth; day++) {
      const dayInstallments = getInstallmentsForDay(day)

      days.push(
        <div key={day} className={getDayClass(day)} onClick={() => handleDayClick(day)}>
          <div className="flex flex-col h-full">
            <div className="text-sm font-medium text-gray-900 dark:text-white mb-1">
              {day}
            </div>
            <div className="flex-1 space-y-1 overflow-hidden">
              {dayInstallments.slice(0, 2).map((inst, index) => (
                <Badge
                  key={inst.id}
                  variant={inst.status === 'Pagado' ? 'secondary' : inst.status === 'Vencido' ? 'destructive' : 'default'}
                  className="text-xs px-1 py-0 truncate block"
                >
                  {inst.loan.bankName}
                </Badge>
              ))}
              {dayInstallments.length > 2 && (
                <MoreHorizontal className="h-3 w-3 text-gray-500" />
              )}
            </div>
          </div>
        </div>
      )
    }

    return days
  }

  const getDayClass = (day: number) => {
    const dayInstallments = getInstallmentsForDay(day)
    const today = new Date()
    const isToday =
      today.getDate() === day &&
      today.getMonth() === currentDate.getMonth() &&
      today.getFullYear() === currentDate.getFullYear()

    let baseClass = "h-20 w-full p-1 border border-gray-200 dark:border-gray-700 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors cursor-pointer"

    if (isToday) {
      baseClass += " bg-blue-100 dark:bg-blue-900 border-blue-300 dark:border-blue-700"
    }

    return baseClass
  }

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Calendario de Pagos</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-center py-8">Cargando calendario...</div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle>
            Calendario de Pagos
          </CardTitle>
          <div className="flex gap-2">
            <Select value={selectedMonth.toString()} onValueChange={handleMonthChange}>
              <SelectTrigger className="w-30">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {[
                  "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
                ].map((month, index) => (
                  <SelectItem key={index} value={index.toString()}>
                    {month}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={selectedYear.toString()} onValueChange={handleYearChange}>
              <SelectTrigger className="w-22">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
              {Array.from({ length: 100 }, (_, i) => new Date().getFullYear() - 2 + i).map((year) => (
                <SelectItem key={year} value={year.toString()}>
                  {year}
                </SelectItem>
              ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-7 gap-1 mb-4">
          {["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"].map((day) => (
            <div key={day} className="text-center text-sm font-medium text-gray-500 dark:text-gray-400 py-2">
              {day}
            </div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {renderCalendar()}
        </div>
        <div className="mt-4 flex flex-wrap gap-4 text-sm">
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-blue-100 dark:bg-blue-900 border border-blue-300 dark:border-blue-700 rounded"></div>
            <span>Hoy</span>
          </div>
        </div>
      </CardContent>

      <Dialog open={dayDetailsOpen} onOpenChange={setDayDetailsOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Detalles del día {selectedDay} de {currentDate.toLocaleDateString("es-ES", { month: "long", year: "numeric" })}
            </DialogTitle>
            <DialogDescription>
              Cuotas programadas para este día
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {selectedDay && getInstallmentsForDay(selectedDay).map((inst) => (
              <div key={inst.id} className="flex items-center justify-between p-3 border rounded-lg">
                <div>
                  <p className="font-medium">{inst.loan.bankName}</p>
                  <p className="text-sm text-muted-foreground">{inst.loan.loanType}</p>
                  <p className="text-sm text-muted-foreground">Cuota mensual: S/ {Number(inst.loan.monthlyPayment)?.toFixed(2) || '0.00'}</p>
                  <p className="text-sm text-muted-foreground">Total: S/ {Number(inst.loan.totalAmount)?.toFixed(2) || '0.00'}</p>
                </div>
                <Badge variant={inst.status === 'Pagado' ? 'secondary' : inst.status === 'Vencido' ? 'destructive' : 'default'}>
                  {inst.status}
                </Badge>
              </div>
            ))}
            {selectedDay && getInstallmentsForDay(selectedDay).length > 0 && (
              <div className="flex justify-end pt-4 border-t">
                <div className="text-right">
                  <p className="text-lg font-semibold">
                    Total de pago: S/ {getInstallmentsForDay(selectedDay).reduce((sum, inst) => sum + (Number(inst.loan.monthlyPayment) || 0), 0).toFixed(2)}
                  </p>
                </div>
              </div>
            )}
            {selectedDay && getInstallmentsForDay(selectedDay).length === 0 && (
              <p className="text-center text-muted-foreground py-4">No hay cuotas programadas para este día</p>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </Card>
  )
}
