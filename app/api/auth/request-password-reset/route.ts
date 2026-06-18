import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import { sql } from '@/lib/db'
import { sendPasswordResetCode } from '@/lib/email'

export async function POST(request: NextRequest) {
  try {
    const { email, oldPassword } = await request.json()

    if (!email || !oldPassword) {
      return NextResponse.json({ error: 'Email y contraseña antigua son requeridos' }, { status: 400 })
    }

    // Validar formato de email
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(email)) {
      return NextResponse.json({ error: 'Formato de email inválido' }, { status: 400 })
    }

    // Verificar que el usuario existe y la contraseña es correcta
    const userResult = await sql`
      SELECT id, password FROM users WHERE email = ${email}
    `

    if (userResult.length === 0) {
      // No revelar si el email existe por seguridad, pero validar formato
      return NextResponse.json({ error: 'Email o contraseña incorrectos' }, { status: 401 })
    }

    const user = userResult[0]
    const isValidPassword = await bcrypt.compare(oldPassword, user.password)

    if (!isValidPassword) {
      // Log intento fallido
      const clientIP = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || 'unknown'
      console.log(`[SECURITY] Intento de cambio de contraseña fallido para email: ${email}, IP: ${clientIP}`)
      return NextResponse.json({ error: 'Email o contraseña incorrectos' }, { status: 401 })
    }

    // Verificar si hay códigos activos no expirados para este email
    const activeCodeResult = await sql`
      SELECT id, attempts, blocked_until FROM password_reset_codes
      WHERE email = ${email} AND used = false AND expires_at > NOW()
      ORDER BY created_at DESC LIMIT 1
    `

    if (activeCodeResult.length > 0) {
      const activeCode = activeCodeResult[0]

      // Verificar si está bloqueado
      if (activeCode.blocked_until && new Date(activeCode.blocked_until) > new Date()) {
        const remainingTime = Math.ceil((new Date(activeCode.blocked_until).getTime() - Date.now()) / 1000 / 60)
        return NextResponse.json({
          error: `Demasiados intentos fallidos. Intenta nuevamente en ${remainingTime} minutos`
        }, { status: 429 })
      }
    }

    // Generar código de 6 dígitos
    const code = Math.floor(100000 + Math.random() * 900000).toString()

    // Hash del código para almacenamiento
    const hashedCode = await bcrypt.hash(code, 10)

    // Crear registro en la base de datos
    const clientIP = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || 'unknown'
    await sql`
      INSERT INTO password_reset_codes (email, code, expires_at, ip_address)
      VALUES (${email}, ${hashedCode}, NOW() + INTERVAL '5 minutes', ${clientIP})
    `

    // Log del intento
    console.log(`[SECURITY] Código de reset enviado a: ${email}, IP: ${clientIP}`)

    // Enviar email
    try {
      await sendPasswordResetCode(email, code)
    } catch (emailError) {
      console.error('Error enviando email:', emailError)
      return NextResponse.json({ error: 'Error enviando el código de verificación' }, { status: 500 })
    }

    return NextResponse.json({ message: 'Código de verificación enviado al email' })

  } catch (error) {
    console.error('Error en request-password-reset:', error)
    return NextResponse.json({ error: 'Error interno del servidor' }, { status: 500 })
  }
}
