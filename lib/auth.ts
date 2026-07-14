export interface User {
  id: number
  username: string
  email: string
  fullName?: string
}

export interface AuthResult {
  user: User
  accessToken: string
}

export async function validateUser(username: string, password: string): Promise<AuthResult> {
  const serviceUrl = process.env.USUARIOS_SERVICE_URL || "http://localhost:3000"

  const response = await fetch(`${serviceUrl}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  })

  const data = await response.json()

  if (!response.ok) {
    throw new Error(data.error || "Credenciales inválidas")
  }

  return {
    user: data.user,
    accessToken: data.accessToken,
  }
}
