import { neon } from "@neondatabase/serverless"

// Crear cliente SQL de Neon
const sql = neon(process.env.DATABASE_URL!)

export { sql }
