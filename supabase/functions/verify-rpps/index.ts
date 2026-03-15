import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// createClient supprimé : verify-rpps est accessible sans JWT

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.soindirect.com" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app")
  ) {
    return origin;
  }
  return "https://app.soindirect.com";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

// Rate limiting simple en mémoire (par IP, 10 req/min)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW_MS = 60_000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return false;
  }
  entry.count++;
  return entry.count > RATE_LIMIT_MAX;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Rate limiting par IP
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (isRateLimited(clientIp)) {
    return new Response(JSON.stringify({ error: 'Trop de requêtes' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  // Vérification JWT désactivée pour permettre l'usage avant connexion (inscription)
  // La fonction ne retourne que des données publiques RPPS.

  try {
    const { numero_rpps, prenom, nom } = await req.json();

    if (!numero_rpps || !/^\d{11}$/.test(numero_rpps)) {
      return new Response(JSON.stringify({ error: 'Numéro RPPS invalide (11 chiffres requis)' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Fetch from Annuaire Santé API
    const url = `https://annuaire.sante.fr/web/site/professionnel-de-sante?rpps=${numero_rpps}`;
    
    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'SoinDirect/1.0',
          'Accept': 'text/html,application/xhtml+xml',
        },
      });

      if (response.ok) {
        const html = await response.text();
        
        const nomMatch = html.match(/class="[^"]*nom[^"]*"[^>]*>([^<]+)</i);
        const prenomMatch = html.match(/class="[^"]*prenom[^"]*"[^>]*>([^<]+)</i);
        const professionMatch = html.match(/class="[^"]*profession[^"]*"[^>]*>([^<]+)</i);
        
        const nomCompletMatch = html.match(/<h1[^>]*>([^<]+)<\/h1>/);
        const profMatch = html.match(/Profession\s*:\s*([^<]+)/i) || html.match(/profession[^>]*>([^<]+)/i);

        if (nomCompletMatch || nomMatch) {
          const nomRetourne = nomCompletMatch?.[1]?.trim() || `${prenomMatch?.[1]?.trim() || ''} ${nomMatch?.[1]?.trim() || ''}`.trim();
          const profRetournee = profMatch?.[1]?.trim() || professionMatch?.[1]?.trim() || '';

          if (nomRetourne && nomRetourne.length > 2) {
            const nomNormalise = nomRetourne.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
            const nomSeul = nom?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') || '';
            
            const correspond = nomNormalise.includes(nomSeul) || nomSeul.includes(nomNormalise.split(' ').pop() || '');

            return new Response(JSON.stringify({
              trouve: true,
              correspond,
              nom_api: nomRetourne,
              profession_api: profRetournee,
            }), {
              headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
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
              headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
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
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Erreur verify-rpps:', error);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
