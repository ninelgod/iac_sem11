import { type NextRequest, NextResponse } from "next/server"
import { validateUser } from "@/lib/auth"

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json()

    if (!username || !password) {
      return NextResponse.json({ error: "Usuario y contraseña son requeridos" }, { status: 400 })
    }

    const result = await validateUser(username, password)

    const response = NextResponse.json({ user: result.user })

    // JWT en cookie httpOnly — el browser lo envía automáticamente en cada request
    if (result.accessToken) {
      response.cookies.set("accessToken", result.accessToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax",
        maxAge: 3600, // 1 hora, igual que el access token de Cognito
        path: "/",
      })
    }

    return response
  } catch (error: any) {
    console.error("Login error:", error)

    if (error.message?.includes("Cuenta bloqueada") || error.message?.includes("Te quedan")) {
      return NextResponse.json({ error: error.message }, { status: 429 })
    }
    if (error.message?.includes("inválidas") || error.message?.includes("Credenciales")) {
      return NextResponse.json({ error: error.message }, { status: 401 })
    }

    return NextResponse.json({ error: "Error interno del servidor" }, { status: 500 })
  }
}
