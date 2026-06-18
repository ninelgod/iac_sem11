"use client"

import type React from "react"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"

export function LoginForm() {
  const router = useRouter()
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [error, setError] = useState("")
  const [isLoading, setIsLoading] = useState(false)

  // Estados para cambio de contraseña
  const [showPasswordReset, setShowPasswordReset] = useState(false)
  const [resetStep, setResetStep] = useState<'request' | 'verify' | 'change'>('request')
  const [resetEmail, setResetEmail] = useState("")
  const [resetOldPassword, setResetOldPassword] = useState("")
  const [resetCode, setResetCode] = useState("")
  const [resetNewPassword, setResetNewPassword] = useState("")
  const [resetError, setResetError] = useState("")
  const [resetSuccess, setResetSuccess] = useState("")
  const [resetLoading, setResetLoading] = useState(false)
  const [attemptsLeft, setAttemptsLeft] = useState(3)
  const [loginAttemptsLeft, setLoginAttemptsLeft] = useState(3)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setIsLoading(true)

    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      })

      const data = await response.json()

      if (!response.ok) {
        if (data.error.includes("Te quedan")) {
          const match = data.error.match(/Te quedan (\d+) intentos/)
          if (match) {
            setLoginAttemptsLeft(parseInt(match[1]))
          }
        } else if (data.error.includes("Cuenta bloqueada")) {
          setLoginAttemptsLeft(0)
        }
        setError(data.error || "Error al iniciar sesión")
        setIsLoading(false)
        return
      }

      // Guardar sesión en localStorage
      localStorage.setItem("user", JSON.stringify(data.user))
      setLoginAttemptsLeft(3) // Reset on successful login

      // Redirigir al dashboard
      router.push("/dashboard")
    } catch (err) {
      setError("Error de conexión. Intenta nuevamente.")
      setIsLoading(false)
    }
  }

  const handleRequestPasswordReset = async (e: React.FormEvent) => {
    e.preventDefault()
    setResetError("")
    setResetLoading(true)

    try {
      const response = await fetch("/api/auth/request-password-reset", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: resetEmail, oldPassword: resetOldPassword }),
      })

      const data = await response.json()

      if (!response.ok) {
        setResetError(data.error || "Error al solicitar código")
        setResetLoading(false)
        return
      }

      setResetSuccess("Código enviado al email. Revisa tu bandeja de entrada.")
      setResetStep('verify')
    } catch (err) {
      setResetError("Error de conexión. Intenta nuevamente.")
    } finally {
      setResetLoading(false)
    }
  }

  const handleVerifyCode = async (e: React.FormEvent) => {
    e.preventDefault()
    setResetError("")
    setResetLoading(true)

    try {
      const response = await fetch("/api/auth/verify-reset-code", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: resetEmail, code: resetCode }),
      })

      const data = await response.json()

      if (!response.ok) {
        if (data.attemptsLeft !== undefined) {
          setAttemptsLeft(data.attemptsLeft)
        }
        setResetError(data.error || "Código inválido")
        setResetLoading(false)
        return
      }

      setResetSuccess("Código verificado correctamente")
      setResetStep('change')
    } catch (err) {
      setResetError("Error de conexión. Intenta nuevamente.")
    } finally {
      setResetLoading(false)
    }
  }

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault()
    setResetError("")
    setResetLoading(true)

    try {
      const response = await fetch("/api/auth/change-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: resetEmail, code: resetCode, newPassword: resetNewPassword }),
      })

      const data = await response.json()

      if (!response.ok) {
        setResetError(data.error || "Error al cambiar contraseña")
        setResetLoading(false)
        return
      }

      setResetSuccess("Contraseña cambiada exitosamente")
      setTimeout(() => {
        setShowPasswordReset(false)
        setResetStep('request')
        setResetEmail("")
        setResetOldPassword("")
        setResetCode("")
        setResetNewPassword("")
        setResetError("")
        setResetSuccess("")
        setAttemptsLeft(3)
      }, 2000)
    } catch (err) {
      setResetError("Error de conexión. Intenta nuevamente.")
    } finally {
      setResetLoading(false)
    }
  }

  const resetPasswordDialog = () => (
    <Dialog open={showPasswordReset} onOpenChange={setShowPasswordReset}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Cambiar Contraseña</DialogTitle>
          <DialogDescription>
            {resetStep === 'request' && "Ingresa tu email y contraseña actual para recibir un código de verificación"}
            {resetStep === 'verify' && "Ingresa el código de 6 dígitos enviado a tu email"}
            {resetStep === 'change' && "Ingresa tu nueva contraseña"}
          </DialogDescription>
        </DialogHeader>

        {resetStep === 'request' && (
          <form onSubmit={handleRequestPasswordReset} className="space-y-4">
            <div className="mt-4 text-center">
              <Button
                variant="link"
                className="text-sm text-muted-foreground hover:text-primary"
                onClick={() => setShowPasswordReset(false)}
              >
                ← Volver al Login
              </Button>
            </div>
            <div className="space-y-2">
              <Label htmlFor="resetEmail">Email</Label>
              <Input
                id="resetEmail"
                type="email"
                placeholder="tu@email.com"
                value={resetEmail}
                onChange={(e) => setResetEmail(e.target.value)}
                required
                disabled={resetLoading}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="resetOldPassword">Contraseña Actual</Label>
              <Input
                id="resetOldPassword"
                type="password"
                placeholder="••••••"
                value={resetOldPassword}
                onChange={(e) => setResetOldPassword(e.target.value)}
                required
                disabled={resetLoading}
              />
            </div>
            {resetError && (
              <Alert variant="destructive">
                <AlertDescription>{resetError}</AlertDescription>
              </Alert>
            )}
            {resetSuccess && (
              <Alert className="bg-green-50 text-green-900 border-green-200 dark:bg-green-900/20 dark:text-green-100 dark:border-green-800">
                <AlertDescription>{resetSuccess}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" className="w-full" disabled={resetLoading}>
              {resetLoading ? "Enviando..." : "Enviar Código"}
            </Button>
          </form>
        )}

        {resetStep === 'verify' && (
          <>
            <div className="mt-4 text-center">
              <Button
                variant="link"
                className="text-sm text-muted-foreground hover:text-primary"
                onClick={() => setResetStep('request')}
              >
                ← Volver
              </Button>
            </div>
            <form onSubmit={handleVerifyCode} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="resetCode">Código de Verificación</Label>
              <Input
                id="resetCode"
                type="text"
                placeholder="123456"
                value={resetCode}
                onChange={(e) => setResetCode(e.target.value)}
                required
                disabled={resetLoading}
                maxLength={6}
              />
              <p className="text-xs text-muted-foreground">
                Te quedan {attemptsLeft} intentos
              </p>
            </div>
            {resetError && (
              <Alert variant="destructive">
                <AlertDescription>{resetError}</AlertDescription>
              </Alert>
            )}
            {resetSuccess && (
              <Alert className="bg-green-50 text-green-900 border-green-200 dark:bg-green-900/20 dark:text-green-100 dark:border-green-800">
                <AlertDescription>{resetSuccess}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" className="w-full" disabled={resetLoading}>
              {resetLoading ? "Verificando..." : "Verificar Código"}
            </Button>
            <Button
              type="button"
              variant="outline"
              className="w-full"
              onClick={() => setResetStep('request')}
              disabled={resetLoading}
            >
              Volver
            </Button>
          </form>
          </>
        )}

        {resetStep === 'change' && (
          <>
            <div className="mt-4 text-center">
              <Button
                variant="link"
                className="text-sm text-muted-foreground hover:text-primary"
                onClick={() => setResetStep('verify')}
              >
                ← Volver
              </Button>
            </div>
            <form onSubmit={handleChangePassword} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="resetNewPassword">Nueva Contraseña</Label>
              <Input
                id="resetNewPassword"
                type="password"
                placeholder="••••••"
                value={resetNewPassword}
                onChange={(e) => setResetNewPassword(e.target.value)}
                required
                disabled={resetLoading}
                minLength={6}
              />
              <p className="text-xs text-muted-foreground">
                Mínimo 6 caracteres
              </p>
            </div>
            {resetError && (
              <Alert variant="destructive">
                <AlertDescription>{resetError}</AlertDescription>
              </Alert>
            )}
            {resetSuccess && (
              <Alert className="bg-green-50 text-green-900 border-green-200 dark:bg-green-900/20 dark:text-green-100 dark:border-green-800">
                <AlertDescription>{resetSuccess}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" className="w-full" disabled={resetLoading}>
              {resetLoading ? "Cambiando..." : "Cambiar Contraseña"}
            </Button>
          </form>
          </>
        )}
      </DialogContent>
    </Dialog>
  )

  return (
    <Card>
      <CardHeader>
        <CardTitle>Iniciar Sesión</CardTitle>
        <CardDescription>Ingresa tus credenciales para acceder</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="username">Usuario</Label>
            <Input
              id="username"
              type="text"
              placeholder="agile"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
              disabled={isLoading}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Contraseña</Label>
            <Input
              id="password"
              type="password"
              placeholder="••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              disabled={isLoading}
            />
          </div>
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
          {loginAttemptsLeft < 3 && loginAttemptsLeft > 0 && (
            <Alert>
              <AlertDescription>
                Te quedan {loginAttemptsLeft} intentos antes de que tu cuenta sea bloqueada por 2 minutos.
              </AlertDescription>
            </Alert>
          )}
          <Button type="submit" className="w-full" disabled={isLoading}>
            {isLoading ? "Iniciando sesión..." : "Iniciar Sesión"}
          </Button>
        </form>

      </CardContent>
      {resetPasswordDialog()}
    </Card>
  )
}
