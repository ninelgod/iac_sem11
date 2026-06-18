import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import { sql } from '@/lib/db'

export async function POST(request: NextRequest) {
  try {
    const { email, code } = await request.json()

    if (!email || !code) {
      return NextResponse.json({ error: 'Email y código son requeridos' }, { status: 400 })
    }

    // Buscar el código activo más reciente para este email
    const codeResult = await sql`
      SELECT id, code, attempts, blocked_until, expires_at
      FROM password_reset_codes
      WHERE email = ${email} AND used = false AND expires_at > NOW()
      ORDER BY created_at DESC LIMIT 1
    `

    if (codeResult.length === 0) {
      return NextResponse.json({ error: 'Código inválido o expirado' }, { status: 400 })
    }

    const resetCode = codeResult[0]

    // Verificar si está bloqueado
    if (resetCode.blocked_until && new Date(resetCode.blocked_until) > new Date()) {
      const remainingTime = Math.ceil((new Date(resetCode.blocked_until).getTime() - Date.now()) / 1000 / 60)
      return NextResponse.json({
        error: `Demasiados intentos fallidos. Intenta nuevamente en ${remainingTime} minutos`,
        attemptsLeft: 0
      }, { status: 429 })
    }

    // Verificar el código
    const isValidCode = await bcrypt.compare(code, resetCode.code)

    if (!isValidCode) {
      // Incrementar contador de intentos
      const newAttempts = resetCode.attempts + 1
      const clientIP = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || 'unknown'

      if (newAttempts >= 3) {
        // Bloquear por 2 minutos
        const blockedUntil = new Date(Date.now() + 2 * 60 * 1000)
        await sql`
          UPDATE password_reset_codes
          SET attempts = ${newAttempts}, blocked_until = ${blockedUntil}
          WHERE id = ${resetCode.id}
        `
        console.log(`[SECURITY] Código bloqueado para email: ${email}, IP: ${clientIP}, intentos: ${newAttempts}`)
        return NextResponse.json({
          error: 'Código incorrecto. Acceso bloqueado por 2 minutos',
          attemptsLeft: 0
        }, { status: 429 })
      } else {
        await sql`
          UPDATE password_reset_codes
          SET attempts = ${newAttempts}
          WHERE id = ${resetCode.id}
        `
        console.log(`[SECURITY] Intento fallido de verificación para email: ${email}, IP: ${clientIP}, intentos: ${newAttempts}`)
        return NextResponse.json({
          error: `Código incorrecto. Te quedan ${3 - newAttempts} intentos`,
          attemptsLeft: 3 - newAttempts
        }, { status: 400 })
      }
    }

    // Código válido - marcar como usado y resetear intentos
    await sql`
      UPDATE password_reset_codes
      SET used = true, attempts = 0
      WHERE id = ${resetCode.id}
    `

    const clientIP = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || 'unknown'
    console.log(`[SECURITY] Código verificado exitosamente para email: ${email}, IP: ${clientIP}`)

    return NextResponse.json({ message: 'Código verificado correctamente' })

  } catch (error) {
    console.error('Error en verify-reset-code:', error)
    return NextResponse.json({ error: 'Error interno del servidor' }, { status: 500 })
  }
}
