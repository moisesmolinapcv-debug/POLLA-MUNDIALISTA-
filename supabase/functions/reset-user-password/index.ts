// Supabase Edge Function — reset-user-password
// Archivo: supabase/functions/reset-user-password/index.ts
//
// INSTRUCCIONES DE DESPLIEGUE:
// 1. Instala Supabase CLI: https://supabase.com/docs/guides/cli
// 2. Ejecuta: supabase login
// 3. Ejecuta: supabase link --project-ref TU_PROJECT_REF
// 4. Ejecuta: supabase functions deploy reset-user-password
// 5. Ve a Supabase Dashboard → Edge Functions → reset-user-password → Settings
//    y agrega la variable de entorno: SUPABASE_SERVICE_ROLE_KEY (tu clave privada)
//
// VARIABLES DE ENTORNO REQUERIDAS (se configuran automáticamente en Supabase):
//   SUPABASE_URL          → URL de tu proyecto (automática)
//   SUPABASE_SERVICE_ROLE_KEY → Tu Service Role Key (debes agregarla manualmente)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  try {
    // 1. Leer el JWT del admin que llama la función
    const authHeader = req.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'No autorizado: falta token de autenticación' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    const callerToken = authHeader.replace('Bearer ', '')

    // 2. Crear cliente con el token del llamador para verificar si es admin
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const callerClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: `Bearer ${callerToken}` } }
    })

    // 3. Obtener el usuario que llama y verificar is_admin
    const { data: { user: callerUser }, error: authError } = await callerClient.auth.getUser(callerToken)
    if (authError || !callerUser) {
      return new Response(JSON.stringify({ error: 'Token inválido o sesión expirada' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 4. Verificar que el llamador tiene is_admin = true en profiles
    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: callerProfile, error: profileError } = await adminClient
      .from('profiles')
      .select('is_admin')
      .eq('id', callerUser.id)
      .single()

    if (profileError || !callerProfile || !callerProfile.is_admin) {
      return new Response(JSON.stringify({ error: 'Acceso denegado: no eres administrador' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 5. Leer el body de la petición
    const body = await req.json()
    const { cedula, new_password } = body

    if (!cedula || !new_password) {
      return new Response(JSON.stringify({ error: 'Faltan campos: cedula y new_password son requeridos' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (new_password.length < 6) {
      return new Response(JSON.stringify({ error: 'La contraseña debe tener mínimo 6 caracteres' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 6. Buscar el user_id del usuario target por cédula
    const { data: targetProfile, error: targetError } = await adminClient
      .from('profiles')
      .select('id, name, email')
      .eq('cedula', cedula)
      .single()

    if (targetError || !targetProfile) {
      return new Response(JSON.stringify({ error: `Usuario con cédula ${cedula} no encontrado` }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 7. Cambiar la contraseña usando el Admin Auth API (Service Role)
    const { error: resetError } = await adminClient.auth.admin.updateUserById(
      targetProfile.id,
      { password: new_password }
    )

    if (resetError) {
      console.error('Error resetting password:', resetError)
      return new Response(JSON.stringify({ error: `Error al cambiar la contraseña: ${resetError.message}` }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 8. Activar el flag must_change_password para que el usuario cambie su clave al ingresar
    const { error: flagError } = await adminClient
      .from('profiles')
      .update({ must_change_password: true })
      .eq('id', targetProfile.id)

    if (flagError) {
      // No es bloqueante, pero lo registramos
      console.warn('Warning: could not set must_change_password flag:', flagError)
    }

    // 9. Respuesta exitosa
    return new Response(JSON.stringify({
      success: true,
      message: `Contraseña restablecida para ${targetProfile.name} (${cedula})`,
      must_change_password_set: !flagError
    }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (err) {
    console.error('Unexpected error in reset-user-password:', err)
    return new Response(JSON.stringify({ error: 'Error interno del servidor' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
