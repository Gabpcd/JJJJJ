import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { numero_rpps, prenom, nom } = await req.json();

    if (!numero_rpps || !/^\d{11}$/.test(numero_rpps)) {
      return new Response(JSON.stringify({ error: 'Numéro RPPS invalide (11 chiffres requis)' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Fetch from Annuaire Santé API
    const url = `https://annuaire.sante.fr/web/site/professionnel-de-sante?rpps=${numero_rpps}`;
    
    let rppsData: { trouve: boolean; nom_api?: string; profession_api?: string } = { trouve: false };

    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'SoinDirect/1.0',
          'Accept': 'text/html,application/xhtml+xml',
        },
      });

      if (response.ok) {
        const html = await response.text();
        
        // Parse the HTML response to extract name and profession
        // The annuaire.sante.fr page contains structured data
        const nomMatch = html.match(/class="[^"]*nom[^"]*"[^>]*>([^<]+)</i);
        const prenomMatch = html.match(/class="[^"]*prenom[^"]*"[^>]*>([^<]+)</i);
        const professionMatch = html.match(/class="[^"]*profession[^"]*"[^>]*>([^<]+)</i);
        
        // Alternative parsing: look for typical patterns in the page
        const nomCompletMatch = html.match(/<h1[^>]*>([^<]+)<\/h1>/);
        const profMatch = html.match(/Profession\s*:\s*([^<]+)/i) || html.match(/profession[^>]*>([^<]+)/i);

        if (nomCompletMatch || nomMatch) {
          const nomRetourne = nomCompletMatch?.[1]?.trim() || `${prenomMatch?.[1]?.trim() || ''} ${nomMatch?.[1]?.trim() || ''}`.trim();
          const profRetournee = profMatch?.[1]?.trim() || professionMatch?.[1]?.trim() || '';

          if (nomRetourne && nomRetourne.length > 2) {
            // Check name correspondence (case-insensitive, partial match)
            const nomNormalise = nomRetourne.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
            const nomSoignant = `${prenom} ${nom}`.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
            const nomSeul = nom?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') || '';
            
            const correspond = nomNormalise.includes(nomSeul) || nomSeul.includes(nomNormalise.split(' ').pop() || '');

            rppsData = {
              trouve: true,
              nom_api: nomRetourne,
              profession_api: profRetournee,
            };

            return new Response(JSON.stringify({
              trouve: true,
              correspond,
              nom_api: nomRetourne,
              profession_api: profRetournee,
            }), {
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          }
        }
      }
    } catch (fetchError) {
      console.error('Erreur fetch annuaire:', fetchError);
    }

    // If direct fetch fails, try the search API
    try {
      const searchUrl = `https://annuaire.sante.fr/web/site/professionnel-de-sante/search?identifiant=${numero_rpps}`;
      const searchResponse = await fetch(searchUrl, {
        headers: { 'User-Agent': 'SoinDirect/1.0', 'Accept': 'application/json, text/html' },
      });

      if (searchResponse.ok) {
        const contentType = searchResponse.headers.get('content-type') || '';
        
        if (contentType.includes('json')) {
          const data = await searchResponse.json();
          if (data && (data.nom || data.results?.length > 0)) {
            const result = data.results?.[0] || data;
            const nomRetourne = result.nom || result.nomExercice || '';
            const profRetournee = result.profession || result.libelleProfession || '';
            const nomSeul = nom?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') || '';
            const nomApiNorm = nomRetourne.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
            
            return new Response(JSON.stringify({
              trouve: true,
              correspond: nomApiNorm.includes(nomSeul),
              nom_api: nomRetourne,
              profession_api: profRetournee,
            }), {
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          }
        }
      }
    } catch (searchError) {
      console.error('Erreur search annuaire:', searchError);
    }

    // RPPS not found
    return new Response(JSON.stringify({
      trouve: false,
      correspond: false,
      nom_api: null,
      profession_api: null,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Erreur verify-rpps:', error);
    return new Response(JSON.stringify({ error: 'Erreur interne', details: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
