import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import { sql } from '@/lib/db'

export async function POST(request: NextRequest) {
  try {
    const { email, code, newPassword } = await request.json()

    if (!email || !code || !newPassword) {
      return NextResponse.json({ error: 'Email, código y nueva contraseña son requeridos' }, { status: 400 })
    }

    if (newPassword.length < 6) {
      return NextResponse.json({ error: 'La contraseña debe tener al menos 6 caracteres' }, { status: 400 })
    }

    // Validar que contenga al menos una letra
    const hasLetter = /[a-zA-Z]/.test(newPassword)
    if (!hasLetter) {
      return NextResponse.json({ error: 'La contraseña debe contener al menos una letra' }, { status: 400 })
    }

    // Verificar que el código fue usado recientemente (últimos 5 minutos)
    const recentCodeResult = await sql`
      SELECT id FROM password_reset_codes
      WHERE email = ${email} AND used = true AND created_at > NOW() - INTERVAL '5 minutes'
      ORDER BY created_at DESC LIMIT 1
    `

    if (recentCodeResult.length === 0) {
      return NextResponse.json({ error: 'Código no verificado o expirado' }, { status: 400 })
    }

    // Hash de la nueva contraseña
    const hashedPassword = await bcrypt.hash(newPassword, 12)

    // Actualizar la contraseña del usuario
    const updateResult = await sql`
      UPDATE users SET password = ${hashedPassword} WHERE email = ${email}
    `

    // No devolver error si no se encuentra el usuario por seguridad

    const clientIP = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || 'unknown'
    console.log(`[SECURITY] Contraseña cambiada exitosamente para email: ${email}, IP: ${clientIP}`)

    return NextResponse.json({ message: 'Contraseña cambiada exitosamente' })

  } catch (error) {
    console.error('Error en change-password:', error)
    return NextResponse.json({ error: 'Error interno del servidor' }, { status: 500 })
  }
}
