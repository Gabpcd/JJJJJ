import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } }
  )

  const soignantId = '57d814fb-c09b-4528-b4e0-ed8369328bd3' // Gabrielle Picard
  const etabId = '8500dba5-2c73-4035-8383-b854d59a9864' // Clinique Test Jolene
  const results: string[] = []

  try {
    // ── 1. Create 3 TERMINEE missions with commission_facturee=false for Clinique Test Jolene ──
    const missions = [
      {
        intitule: 'IDE — Soins post-opératoires jour',
        description: 'Surveillance post-op et administration traitements',
        profession_requise: 'IDE',
        service: 'Chirurgie',
        debut_le: '2026-03-01T07:00:00+01:00',
        fin_le: '2026-03-01T19:00:00+01:00',
        taux_horaire_base: 24.05,
        total_brut: 288.60,
        net_a_payer: 270.13,
        montant_ifm: 28.86,
        montant_icp: 28.86,
        montant_commission_ht: 43.29,
        montant_commission_tva: 8.66,
        montant_commission_ttc: 51.95,
        taux_commission: 15,
        statut: 'TERMINEE',
        soignant_assigne_id: soignantId,
        etablissement_id: etabId,
        commission_facturee: false,
        est_urgente: false,
      },
      {
        intitule: 'IDE — Nuit urgences week-end',
        description: 'Garde de nuit service urgences',
        profession_requise: 'IDE',
        service: 'Urgences',
        debut_le: '2026-03-08T19:00:00+01:00',
        fin_le: '2026-03-09T07:00:00+01:00',
        duree_heures: 12,
        taux_horaire_base: 24.05,
        heures_nuit: 8,
        heures_dimanche: 12,
        montant_majoration_nuit: 48.10,
        montant_majoration_dimanche: 144.30,
        total_brut: 481.00,
        net_a_payer: 450.00,
        montant_ifm: 48.10,
        montant_icp: 48.10,
        montant_commission_ht: 72.15,
        montant_commission_tva: 14.43,
        montant_commission_ttc: 86.58,
        taux_commission: 15,
        statut: 'TERMINEE',
        soignant_assigne_id: soignantId,
        etablissement_id: etabId,
        commission_facturee: false,
        est_urgente: true,
        niveau_urgence: 2,
      },
      {
        intitule: 'IDE — Consultations matin',
        description: 'Consultations et bilans sanguins',
        profession_requise: 'IDE',
        service: 'Consultation',
        debut_le: '2026-03-12T08:00:00+01:00',
        fin_le: '2026-03-12T14:00:00+01:00',
        duree_heures: 6,
        taux_horaire_base: 24.05,
        total_brut: 144.30,
        net_a_payer: 135.00,
        montant_ifm: 14.43,
        montant_icp: 14.43,
        montant_commission_ht: 21.65,
        montant_commission_tva: 4.33,
        montant_commission_ttc: 25.98,
        taux_commission: 15,
        statut: 'TERMINEE',
        soignant_assigne_id: soignantId,
        etablissement_id: etabId,
        commission_facturee: false,
        est_urgente: false,
      },
    ]

    for (const m of missions) {
      const { error } = await supabaseAdmin.from('missions').insert(m as any)
      if (error) results.push(`❌ Mission "${m.intitule}": ${error.message}`)
      else results.push(`✅ Mission "${m.intitule}" créée`)
    }

    // ── 2. Create a presence + dispute for the first mission ──
    // First get the first inserted mission
    const { data: missionForDispute } = await supabaseAdmin
      .from('missions')
      .select('id')
      .eq('etablissement_id', etabId)
      .eq('soignant_assigne_id', soignantId)
      .eq('statut', 'TERMINEE')
      .eq('intitule', 'IDE — Soins post-opératoires jour')
      .single()

    if (missionForDispute) {
      // Create presence
      const { data: presence, error: presErr } = await supabaseAdmin.from('presences').insert({
        mission_id: missionForDispute.id,
        soignant_id: soignantId,
        pointage_arrivee_le: '2026-03-01T07:05:00+01:00',
        pointage_depart_le: '2026-03-01T18:45:00+01:00',
        arrivee_lat: 48.8566,
        arrivee_lng: 2.3522,
        depart_lat: 48.8566,
        depart_lng: 2.3522,
        distance_etablissement_m: 150,
        perimetre_gps_valide: true,
        valide_par_etablissement: true,
        valide_le: '2026-03-02T10:00:00+01:00',
        methode_pointage_arrivee: 'GPS',
        methode_pointage_depart: 'GPS',
      } as any).select().single()

      if (presErr) {
        results.push(`❌ Présence: ${presErr.message}`)
      } else {
        results.push(`✅ Présence créée`)

        // Create dispute
        const { error: litErr } = await supabaseAdmin.from('litiges').insert({
          mission_id: missionForDispute.id,
          soignant_id: soignantId,
          etablissement_id: etabId,
          presence_id: presence.id,
          initie_par: 'SOIGNANT',
          motif: 'Heures non comptabilisées : j\'ai travaillé de 7h00 à 19h15 mais le pointage indique 18h45. Il manque 30 minutes sur ma fiche de présence.',
          statut: 'OUVERT',
        } as any)

        if (litErr) results.push(`❌ Litige: ${litErr.message}`)
        else results.push(`✅ Litige créé (initié par soignant)`)
      }
    } else {
      results.push(`⚠️ Mission pour litige non trouvée`)
    }

    // ── 3. Activate emergency pool for demo caregivers ──
    const demoSoignants = [
      'c0000000-0000-0000-0000-000000000002', // Thomas Dubois
      'c0000000-0000-0000-0000-000000000003', // Fatima Benali
      'c0000000-0000-0000-0000-000000000005', // Sophie Roux
      'c0000000-0000-0000-0000-000000000006', // Amadou Diallo
      'c0000000-0000-0000-0000-000000000007', // Camille Petit
    ]

    for (const sid of demoSoignants) {
      const { error } = await supabaseAdmin.from('soignants').update({
        disponible_urgence: true,
        urgence_rayon_km: Math.floor(Math.random() * 30) + 10,
      }).eq('id', sid)

      if (error) results.push(`❌ Pool urgence ${sid}: ${error.message}`)
      else results.push(`✅ Soignant ${sid} ajouté au pool urgence`)
    }

    // Also add Gabrielle to the pool
    const { error: gpErr } = await supabaseAdmin.from('soignants').update({
      disponible_urgence: true,
      urgence_rayon_km: 25,
    }).eq('id', soignantId)
    if (gpErr) results.push(`❌ Pool Gabrielle: ${gpErr.message}`)
    else results.push(`✅ Gabrielle ajoutée au pool urgence`)

    return new Response(JSON.stringify({ success: true, results }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message, results }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
