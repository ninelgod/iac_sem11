import { LoginForm } from "@/components/login-form"

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 dark:from-gray-900 dark:to-gray-800 p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-2">Gestor de Préstamos</h1>
          <p className="text-gray-600 dark:text-gray-400">Nunca más olvides un pago</p>
        </div>
        <LoginForm />
      </div>
    </div>
  )
}
