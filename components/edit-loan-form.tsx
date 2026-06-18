"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Skeleton } from "@/components/ui/skeleton"
import { ArrowLeft, Save } from "lucide-react"

interface User {
  id: number
  username: string
}

interface EditLoanFormProps {
  loanId: string
}

export function EditLoanForm({ loanId }: EditLoanFormProps) {
  const router = useRouter()
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [isFetching, setIsFetching] = useState(true)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState(false)

  const [formData, setFormData] = useState({
    bankName: "",
    loanType: "",
    totalAmount: "",
    monthlyPayment: "",
    installments: "",
    dueDay: "",
    startDate: "",
    endDate: "",
  })

  // Función para calcular TEM (Tasa Efectiva Mensual) desde TEA
  const calculateTEM = (tea: number): number => {
    return Math.pow(1 + tea / 100, 1 / 12) - 1
  }

  // Función para calcular la cuota mensual usando sistema francés
  const calculateMonthlyPayment = (principal: number, tea: number, numInstallments: number): number => {
    const tem = calculateTEM(tea)
    const numerator = principal * tem
    const denominator = 1 - Math.pow(1 + tem, -numInstallments)
    return numerator / denominator
  }

  useEffect(() => {
    const userStr = localStorage.getItem("user")
    if (!userStr) {
      router.push("/login")
      return
    }
    setUser(JSON.parse(userStr))

    // Cargar datos del préstamo
    loadLoanData()
  }, [router, loanId])

  const loadLoanData = async () => {
    try {
      const response = await fetch(`/api/loans/${loanId}`)
      const data = await response.json()

      if (!response.ok) {
        setError(data.error || "Error al cargar préstamo")
        setIsFetching(false)
        return
      }

      const loan = data.loan
      setFormData({
        bankName: loan.bank_name,
        loanType: loan.loan_type,
        totalAmount: loan.total_amount.toString(),
        monthlyPayment: loan.monthly_payment.toString(),
        installments: Math.ceil(
          (new Date(loan.end_date).getTime() - new Date(loan.start_date).getTime()) / (1000 * 60 * 60 * 24 * 30),
        ).toString(),
        dueDay: loan.due_day.toString(),
        startDate: loan.start_date.split("T")[0],
        endDate: loan.end_date.split("T")[0],
      })
      setIsFetching(false)
    } catch (err) {
      setError("Error de conexión")
      setIsFetching(false)
    }
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newFormData = {
      ...formData,
      [e.target.name]: e.target.value,
    }

    // Recalcular número de cuotas cuando cambian las fechas
    if (e.target.name === 'startDate' || e.target.name === 'endDate') {
      const startDate = new Date(newFormData.startDate)
      const endDate = new Date(newFormData.endDate)

      if (startDate && endDate && endDate > startDate) {
        const monthsDiff = (endDate.getFullYear() - startDate.getFullYear()) * 12 + (endDate.getMonth() - startDate.getMonth())
        newFormData.installments = Math.max(1, monthsDiff + 1).toString()
      }
    }

    setFormData(newFormData)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setIsLoading(true)

    if (!user) {
      setError("Usuario no autenticado")
      setIsLoading(false)
      return
    }

    if (
      !formData.bankName.trim() ||
      !formData.loanType.trim() ||
      !formData.totalAmount ||
      !formData.monthlyPayment ||
      !formData.installments ||
      !formData.dueDay ||
      !formData.startDate ||
      !formData.endDate
    ) {
      setError("Todos los campos son requeridos")
      setIsLoading(false)
      return
    }

    // Validar que la fecha de finalización sea después de la fecha de inicio
    const startDate = new Date(formData.startDate)
    const endDate = new Date(formData.endDate)

    if (endDate <= startDate) {
      setError("La fecha de finalización debe ser posterior a la fecha de inicio")
      setIsLoading(false)
      return
    }

    // Remover validación estricta del monto total para permitir ediciones flexibles
    // Solo validar que los valores sean positivos
    const totalAmount = Number.parseFloat(formData.totalAmount)
    const monthlyPayment = Number.parseFloat(formData.monthlyPayment)
    const installments = Number.parseInt(formData.installments)

    if (totalAmount <= 0 || monthlyPayment <= 0 || installments <= 0) {
      setError("Los montos deben ser valores positivos")
      setIsLoading(false)
      return
    }

    try {
      const response = await fetch(`/api/loans/${loanId}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          bankName: formData.bankName,
          loanType: formData.loanType,
          totalAmount: Number.parseFloat(formData.totalAmount),
          installmentAmount: Number.parseFloat(formData.monthlyPayment),
          numberOfInstallments: Number.parseInt(formData.installments),
          dueDay: Number.parseInt(formData.dueDay),
          startDate: formData.startDate,
          endDate: formData.endDate,
        }),
      })

      const data = await response.json()

      if (!response.ok) {
        setError(data.error || "Error al actualizar préstamo")
        setIsLoading(false)
        return
      }

      setSuccess(true)
      setTimeout(() => {
        router.push("/dashboard")
      }, 1500)
    } catch (err) {
      setError("Error de conexión. Intenta nuevamente.")
      setIsLoading(false)
    }
  }

  if (isFetching) {
    return (
      <Card>
        <CardHeader>
          <Skeleton className="h-8 w-64" />
        </CardHeader>
        <CardContent className="space-y-4">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => router.push("/dashboard")}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <div>
            <CardTitle>Editar Préstamo</CardTitle>
            <CardDescription>Actualiza la información de tu préstamo bancario</CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="bankName">Nombre del Banco</Label>
              <Input
                id="bankName"
                name="bankName"
                type="text"
                placeholder="Ej: Banco Nacional"
                value={formData.bankName}
                onChange={handleChange}
                required
                disabled={isLoading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="loanType">Tipo de Préstamo</Label>
              <Input
                id="loanType"
                name="loanType"
                type="text"
                placeholder="Ej: Personal, Hipotecario, Automotriz"
                value={formData.loanType}
                onChange={handleChange}
                required
                disabled={isLoading}
              />
            </div>
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="totalAmount">Monto Total del Préstamo (S/)</Label>
              <Input
                id="totalAmount"
                name="totalAmount"
                type="number"
                step="0.01"
                placeholder="50000.00"
                value={formData.totalAmount}
                onChange={handleChange}
                required
                disabled={isLoading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="monthlyPayment">Cuota Mensual (S/)</Label>
              <Input
                id="monthlyPayment"
                name="monthlyPayment"
                type="number"
                step="0.01"
                placeholder="2500.00"
                value={formData.monthlyPayment}
                onChange={handleChange}
                required
                disabled={isLoading}
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="installments">Número de Cuotas</Label>
            <Input
              id="installments"
              name="installments"
              type="number"
              min="1"
              placeholder="12"
              value={formData.installments}
              onChange={handleChange}
              required
              disabled={isLoading}
            />
            <p className="text-xs text-muted-foreground">
              Validación: {formData.installments} cuotas × S/ {formData.monthlyPayment || "0"} = S/{" "}
              {(
                Number.parseInt(formData.installments || "0") * Number.parseFloat(formData.monthlyPayment || "0")
              ).toFixed(2)}
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="dueDay">Día de Vencimiento (1-31)</Label>
            <Input
              id="dueDay"
              name="dueDay"
              type="number"
              min="1"
              max="31"
              placeholder="15"
              value={formData.dueDay}
              onChange={handleChange}
              required
              disabled={isLoading}
            />
            <p className="text-xs text-muted-foreground">El día del mes en que vence el pago</p>
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="startDate">Fecha de Inicio</Label>
              <Input
                id="startDate"
                name="startDate"
                type="date"
                value={formData.startDate}
                onChange={handleChange}
                required
                disabled={isLoading}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="endDate">Fecha de Finalización</Label>
              <Input
                id="endDate"
                name="endDate"
                type="date"
                value={formData.endDate}
                onChange={handleChange}
                required
                disabled={isLoading}
              />
              <p className="text-xs text-muted-foreground">Debe ser posterior a la fecha de inicio</p>
            </div>
          </div>

          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          {success && (
            <Alert className="bg-green-50 text-green-900 border-green-200 dark:bg-green-900/20 dark:text-green-100 dark:border-green-800">
              <AlertDescription>Préstamo actualizado exitosamente. Redirigiendo...</AlertDescription>
            </Alert>
          )}

          <div className="flex gap-4">
            <Button type="button" variant="outline" onClick={() => router.push("/dashboard")} disabled={isLoading}>
              Cancelar
            </Button>
            <Button type="submit" className="flex-1" disabled={isLoading}>
              <Save className="mr-2 h-4 w-4" />
              {isLoading ? "Guardando..." : "Guardar Cambios"}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )
}
