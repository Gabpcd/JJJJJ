import { supabase } from '@/integrations/supabase/client';
import { messageErreurEdgeFn } from '@/lib/erreurs';

type PreuveEtablissement = 'IDENTITE' | 'FONCTION';

type FinaliserPreuveParams = {
  etablissementId: string;
  preuve: PreuveEtablissement;
  nouvelleS3Key: string;
  typeMime: string;
  typeDocument: string;
  versionAttendue: number;
  representantNom?: string | null;
  representantPrenom?: string | null;
};

/**
 * Passe le pointeur documentaire par une Edge Function service_role. Si la
 * transaction SQL échoue, la fonction nettoie le nouveau blob; après succès,
 * elle nettoie l'ancienne version et conserve son snapshot dans l'audit SQL.
 */
export async function finaliserTeleversementPreuveEtablissement(
  params: FinaliserPreuveParams,
): Promise<void> {
  const { data, error } = await supabase.functions.invoke(
    'finalize-etablissement-proof-upload',
    {
      body: {
        etablissement_id: params.etablissementId,
        preuve: params.preuve,
        nouvelle_s3_key: params.nouvelleS3Key,
        type_mime: params.typeMime,
        type_document: params.typeDocument,
        version_attendue: params.versionAttendue,
        representant_nom: params.representantNom ?? null,
        representant_prenom: params.representantPrenom ?? null,
      },
    },
  );
  if (error) {
    throw new Error(await messageErreurEdgeFn(
      error,
      "Le document n'a pas pu être rattaché au dossier. Le nouveau fichier a été nettoyé si l'écriture a échoué.",
    ));
  }
  if (data?.ok !== true) {
    throw new Error(data?.error || 'Remplacement documentaire impossible. Rechargez la page.');
  }
}
