export type AccesCopie = {
  id: string;
  statut: 'RESERVEE' | 'PUBLIEE' | 'REMPLACEE';
  storage_path: string;
  sha256_attendu: string;
  taille_attendue: number;
};
export type DependancesCopies = {
  authentifier(req: Request): Promise<string | null>;
  acces(req: Request, id: string, action: 'finaliser' | 'telecharger'): Promise<AccesCopie>;
  lire(path: string): Promise<Uint8Array>;
  verifierPdf(bytes: Uint8Array): Promise<void>;
  publier(id: string, acteur: string, hash: string, taille: number): Promise<{ ok: true; id: string; statut: string }>;
  cors(req: Request): Record<string, string>;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ERREURS: Record<string, number> = {
  COPIE_ACCES_REFUSE: 403, COPIE_RETIREE: 410, COPIE_RESERVATION_EXPIREE: 409,
  COPIE_VERSION_CONFLIT: 409, COPIE_INTEGRITE_INVALIDE: 409, COPIE_FICHIER_ABSENT: 409,
  COPIE_PDF_INVALIDE: 422, COPIE_MISSIONS_INVALIDES: 409,
};

export function creerHandlerCopies(deps: DependancesCopies) {
  return async (req: Request): Promise<Response> => {
    const headers = { ...deps.cors(req), 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
    const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
      status, headers: { ...headers, 'Content-Type': 'application/json' },
    });
    if (req.method === 'OPTIONS') return new Response(null, { headers });
    if (req.method !== 'POST') return json(405, { error: 'METHODE_INTERDITE' });
    try {
      const acteur = await deps.authentifier(req);
      if (!acteur) return json(401, { error: 'AUTHENTIFICATION_REQUISE' });
      // Corps minuscule et strict : pas de PDF/base64, de chemins ni de noms en JSON.
      if (Number(req.headers.get('Content-Length') || 0) > 1024) return json(400, { error: 'REQUETE_INVALIDE' });
      const text = await req.text();
      if (text.length > 1024) return json(400, { error: 'REQUETE_INVALIDE' });
      let body: Record<string, unknown>;
      try { body = JSON.parse(text); } catch { return json(400, { error: 'REQUETE_INVALIDE' }); }
      if (!body || Array.isArray(body) || typeof body !== 'object'
        || Object.keys(body).some((key) => !['action','copie_id','destinataire_confirme'].includes(key))
        || typeof body.copie_id !== 'string' || !UUID.test(body.copie_id)
        || !['finaliser','telecharger'].includes(String(body.action))
        || (body.action === 'finaliser' && body.destinataire_confirme !== true)) {
        return json(400, { error: 'REQUETE_INVALIDE' });
      }
      const action = body.action as 'finaliser' | 'telecharger';
      const copie = await deps.acces(req, body.copie_id, action);
      if (copie.id !== body.copie_id || copie.storage_path !== `${copie.id}/original.pdf`
        || !/^[a-f0-9]{64}$/.test(copie.sha256_attendu)
        || !Number.isSafeInteger(copie.taille_attendue) || copie.taille_attendue < 1 || copie.taille_attendue > 10485760) {
        throw new Error('COPIE_INTEGRITE_INVALIDE');
      }
      const bytes = await deps.lire(copie.storage_path);
      if (bytes.byteLength !== copie.taille_attendue) throw new Error('COPIE_INTEGRITE_INVALIDE');
      const digest = await crypto.subtle.digest('SHA-256', new Uint8Array(bytes).buffer);
      const hash = Array.from(new Uint8Array(digest), (x) => x.toString(16).padStart(2, '0')).join('');
      if (hash !== copie.sha256_attendu) throw new Error('COPIE_INTEGRITE_INVALIDE');
      if (action === 'finaliser') {
        await deps.verifierPdf(bytes);
        // La transaction recontrôle l'acteur, la réservation, le CAS et le digest.
        const publication = await deps.publier(copie.id, acteur, hash, bytes.length);
        if (!publication || publication.ok !== true || publication.id !== copie.id
          || !['PUBLIEE','REMPLACEE'].includes(publication.statut)) throw new Error('PUBLICATION_NON_CONFIRMEE');
        return json(200, publication);
      }
      // Une révocation/suspension pendant la lecture Storage doit fermer l'accès.
      await deps.acces(req, copie.id, 'telecharger');
      return new Response(new Uint8Array(bytes).buffer, { headers: {
        ...headers, 'Content-Type': 'application/pdf',
        'Content-Disposition': 'attachment; filename="copie-bulletin.pdf"',
        'Content-Length': String(bytes.length),
      } });
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      const code = Object.hasOwn(ERREURS, message) ? message : 'COPIE_SERVICE_INDISPONIBLE';
      // Ni log d'exception, ni message brut Supabase/Storage/parseur.
      return json(ERREURS[code] || 503, { error: code });
    }
  };
}
