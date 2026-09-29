import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { corsHeaders } from '../_shared/cors.ts';
import { creerHandlerCopies, type AccesCopie } from './handler.ts';
import { verifierPdfOfficiel } from './pdf.ts';
import { authentifierCopie } from './auth.ts';

const url = Deno.env.get('SUPABASE_URL') || '';
const anon = Deno.env.get('SUPABASE_ANON_KEY') || '';
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const utilisateur = (req: Request) => createClient(url, anon, {
  ...options, global: { headers: { Authorization: req.headers.get('Authorization') || '' } },
});
// Création différée : une configuration absente rend un 503 expurgé.
const admin = () => createClient(url, service, options);

Deno.serve(creerHandlerCopies({
  cors: (req) => corsHeaders(req),
  async authentifier(req) {
    if (!url || !anon || !service) throw new Error('CONFIGURATION_ABSENTE');
    return authentifierCopie(req, (bearer) => utilisateur(req).auth.getUser(bearer), service);
  },
  async acces(req, id, action) {
    const { data, error } = await utilisateur(req).rpc('fn_acces_copie_bulletin', { p_copie_id: id, p_action: action });
    if (error) throw new Error(error.message);
    return data as AccesCopie;
  },
  async lire(path) {
    const { data, error } = await admin().storage.from('copies-bulletins-paie').download(path);
    if (error || !data) throw new Error('COPIE_FICHIER_ABSENT');
    if (data.size > 10485760) throw new Error('COPIE_PDF_INVALIDE');
    return new Uint8Array(await data.arrayBuffer());
  },
  verifierPdf: verifierPdfOfficiel,
  async publier(id, acteur, hash, taille) {
    const { data, error } = await admin().rpc('fn_publier_copie_bulletin_interne', {
      p_copie_id: id, p_acteur_id: acteur, p_sha256: hash, p_taille: taille,
    });
    if (error) throw new Error(error.message);
    return data;
  },
}));
