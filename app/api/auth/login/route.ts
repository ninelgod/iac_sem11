import { type NextRequest, NextResponse } from "next/server"
import { validateUser } from "@/lib/auth"

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json()

    if (!username || !password) {
      return NextResponse.json({ error: "Usuario y contraseña son requeridos" }, { status: 400 })
    }

    const user = await validateUser(username, password)

    if (!user) {
      return NextResponse.json({ error: "Credenciales inválidas" }, { status: 401 })
    }

    return NextResponse.json({ user })
  } catch (error: any) {
    console.error("Login error:", error)

    // Si es un error de rate limiting o bloqueo, devolver el mensaje específico
    if (error.message.includes('Cuenta bloqueada') || error.message.includes('Te quedan')) {
      return NextResponse.json({ error: error.message }, { status: 429 })
    }

    return NextResponse.json({ error: "Error interno del servidor" }, { status: 500 })
  }
}
