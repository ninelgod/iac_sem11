import { sql } from "./db"
import bcrypt from 'bcryptjs'

export interface User {
  id: number
  username: string
  email: string
}

export async function validateUser(username: string, password: string): Promise<User | null> {
  try {
    const result = await sql`
      SELECT id, username, password, email, failed_login_attempts, login_blocked_until
      FROM users
      WHERE username = ${username}
      LIMIT 1
    `

    if (result.length === 0) {
      return null
    }

    const user = result[0]

    const isValidPassword = await bcrypt.compare(password, user.password)

    if (!isValidPassword) {
      // Incrementar contador de intentos fallidos
      const newAttempts = user.failed_login_attempts + 1
      const clientIP = 'unknown' // En un entorno real, obtendrías la IP del request

      await sql`
        UPDATE users
        SET failed_login_attempts = ${newAttempts}
        WHERE id = ${user.id}
      `
      const remainingAttempts = 3 - newAttempts
      console.log(`[SECURITY] Intento fallido de login para: ${username}, IP: ${clientIP}, intentos restantes: ${remainingAttempts}`)
      throw new Error(`Contraseña incorrecta. Te quedan ${remainingAttempts} intentos.`)
    }

    // Resetear contador de intentos fallidos en login exitoso
    if (user.failed_login_attempts > 0) {
      await sql`
        UPDATE users
        SET failed_login_attempts = 0, login_blocked_until = NULL
        WHERE id = ${user.id}
      `
    }

    return {
      id: user.id,
      username: user.username,
      email: user.email,
    }
  } catch (error) {
    console.error("Error validating user:", error)
    throw error
  }
}
