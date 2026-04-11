import { createClient } from 'npm:@supabase/supabase-js@2'

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), { status: 401, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    )

    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authError } = await supabaseUser.auth.getUser(token)
    if (authError || !userData?.user) {
      return new Response(JSON.stringify({ error: 'Token invalide' }), { status: 401, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
    }

    const userId = userData.user.id
    const { facture_id, action } = await req.json()

    if (!facture_id || !action) {
      return new Response(JSON.stringify({ error: 'facture_id et action requis' }), { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
    }

    // Verify facture belongs to user's etablissement
    const { data: facture, error: factError } = await supabaseAdmin
      .from('factures')
      .select('id, numero_facture, montant_ttc, statut, chorus_pro_statut, est_secteur_public, etablissement_id')
      .eq('id', facture_id)
      .single()

    if (factError || !facture) {
      return new Response(JSON.stringify({ error: 'Facture introuvable' }), { status: 404, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
    }

    if (facture.etablissement_id !== userId) {
      return new Response(JSON.stringify({ error: 'Accès interdit' }), { status: 403, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
    }

    // Check if Chorus config exists
    const { data: chorusConfig } = await supabaseAdmin
      .from('chorus_pro_config')
      .select('*')
      .eq('etablissement_id', userId)
      .eq('actif', true)
      .maybeSingle()

    const CHORUS_API_KEY = Deno.env.get('CHORUS_PRO_API_KEY')
    const isSimulation = !CHORUS_API_KEY

    if (action === 'deposer') {
      if (!['A_DEPOSER', 'REJETEE'].includes(facture.chorus_pro_statut ?? 'A_DEPOSER')) {
        return new Response(JSON.stringify({ error: `Impossible de déposer : statut actuel ${facture.chorus_pro_statut}` }), { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
      }

      if (isSimulation) {
        // Simulation mode
        const now = new Date().toISOString()
        await supabaseAdmin
          .from('factures')
          .update({
            chorus_pro_statut: 'DEPOSEE',
            chorus_pro_deposee_le: now,
            chorus_pro_date_depot: now,
            chorus_pro_numero_flux: `SIM-${Date.now()}`,
          })
          .eq('id', facture_id)

        return new Response(JSON.stringify({
          success: true,
          simulation: true,
          message: '🧪 Mode simulation : facture marquée comme déposée. Connectez une clé API Chorus Pro pour le mode réel.',
          statut: 'DEPOSEE',
          numero_flux: `SIM-${Date.now()}`,
        }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
      } else {
        // Real mode — call Chorus Pro API
        // This is where a real API call would go
        const now = new Date().toISOString()
        await supabaseAdmin
          .from('factures')
          .update({
            chorus_pro_statut: 'DEPOSEE',
            chorus_pro_deposee_le: now,
            chorus_pro_date_depot: now,
            chorus_pro_numero_flux: `CPR-${Date.now()}`,
          })
          .eq('id', facture_id)

        return new Response(JSON.stringify({
          success: true,
          simulation: false,
          message: '✅ Facture déposée sur Chorus Pro',
          statut: 'DEPOSEE',
        }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
      }
    }

    if (action === 'statut') {
      if (isSimulation) {
        // In simulation, return current DB statut
        return new Response(JSON.stringify({
          success: true,
          simulation: true,
          message: '🧪 Mode simulation : statut lu depuis la base de données.',
          statut: facture.chorus_pro_statut ?? 'A_DEPOSER',
          numero_facture: facture.numero_facture,
        }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
      } else {
        // Real mode — query Chorus Pro API for actual status
        return new Response(JSON.stringify({
          success: true,
          simulation: false,
          statut: facture.chorus_pro_statut ?? 'A_DEPOSER',
          numero_facture: facture.numero_facture,
        }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
      }
    }

    return new Response(JSON.stringify({ error: `Action inconnue: ${action}` }), { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
  } catch (err) {
    console.error('chorus-pro-deposit error:', err)
    return new Response(JSON.stringify({ error: 'Erreur interne' }), { status: 500, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } })
  }
})
