import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const allowedOrigins = new Set([
  'https://arcstation.kr',
  'https://www.arcstation.kr',
  'https://arcgames.kr',
  'https://www.arcgames.kr',
  'https://loveseol716-ops.github.io',
])

function cors(origin: string) {
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://arcstation.kr',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
    'Content-Type': 'application/json',
  }
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: cors(origin) })
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) })
  if (req.method !== 'POST') return json({ ok: false, error: 'METHOD_NOT_ALLOWED' }, 405, origin)

  try {
    if (origin && !allowedOrigins.has(origin)) return json({ ok: false, error: 'ORIGIN_NOT_ALLOWED' }, 403, origin)

    const body = await req.json()
    if (String(body.website || '').trim()) return json({ ok: false, error: 'SIGNUP_FAILED' }, 400, origin)

    const email = String(body.email || '').trim().toLowerCase()
    const password = String(body.password || '')
    const displayName = String(body.display_name || '').trim().slice(0, 30)
    const fullName = String(body.full_name || '').trim().slice(0, 50)
    const phone = String(body.phone || '').trim()
    const phoneDigits = phone.replace(/[^0-9]/g, '')
    const termsConsent = body.terms_consent === true
    const privacyConsent = body.privacy_consent === true
    const marketingConsent = body.marketing_consent === true

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ ok: false, error: 'INVALID_EMAIL' }, 400, origin)
    if (!/^(?=.*[A-Za-z])(?=.*\d).{8,72}$/.test(password)) return json({ ok: false, error: 'INVALID_PASSWORD' }, 400, origin)
    if (displayName.length < 2) return json({ ok: false, error: 'INVALID_NICKNAME' }, 400, origin)
    if (fullName.length < 2) return json({ ok: false, error: 'INVALID_NAME' }, 400, origin)
    if (phoneDigits.length < 8 || phoneDigits.length > 15) return json({ ok: false, error: 'INVALID_PHONE' }, 400, origin)
    if (!termsConsent || !privacyConsent) return json({ ok: false, error: 'CONSENT_REQUIRED' }, 400, origin)

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    if (!supabaseUrl || !serviceRoleKey) return json({ ok: false, error: 'SERVER_CONFIG_ERROR' }, 500, origin)

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { signup_source: 'arc_games', display_name: displayName },
    })

    if (error) {
      const message = String(error.message || '').toLowerCase()
      if (message.includes('already') || message.includes('registered') || message.includes('exists')) {
        return json({ ok: false, error: 'EMAIL_EXISTS' }, 409, origin)
      }
      return json({ ok: false, error: 'CREATE_USER_FAILED' }, 400, origin)
    }

    const userId = data.user?.id
    if (!userId) return json({ ok: false, error: 'CREATE_USER_FAILED' }, 500, origin)

    const acceptedAt = new Date().toISOString()
    const { error: profileError } = await admin.from('arc_account_private').insert({
      user_id: userId,
      full_name: fullName,
      phone,
      terms_accepted_at: acceptedAt,
      privacy_accepted_at: acceptedAt,
      marketing_accepted_at: marketingConsent ? acceptedAt : null,
    })

    if (profileError) {
      await admin.auth.admin.deleteUser(userId)
      return json({ ok: false, error: 'PROFILE_CREATE_FAILED' }, 500, origin)
    }

    return json({ ok: true }, 200, origin)
  } catch (_error) {
    return json({ ok: false, error: 'SIGNUP_FAILED' }, 400, origin)
  }
})
