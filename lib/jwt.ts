import { createRemoteJWKSet, jwtVerify } from "jose"
import type { NextRequest } from "next/server"

export async function verifyRequestJWT(request: NextRequest): Promise<boolean> {
  const poolId = process.env.COGNITO_USER_POOL_ID
  const region = process.env.AWS_REGION || "us-east-2"

  if (!poolId) return true // Sin Cognito configurado (dev local), permitir

  const token = request.cookies.get("accessToken")?.value
  if (!token) return false

  try {
    const JWKS = createRemoteJWKSet(
      new URL(`https://cognito-idp.${region}.amazonaws.com/${poolId}/.well-known/jwks.json`)
    )
    await jwtVerify(token, JWKS, {
      issuer: `https://cognito-idp.${region}.amazonaws.com/${poolId}`,
    })
    return true
  } catch {
    return false
  }
}
