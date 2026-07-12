import { useEffect, useState } from 'react';
import { AlertTriangle, GraduationCap, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { getLabelProfession } from '@/lib/constantes';

interface Equivalence {
  id: string;
  formation: string;
  libelle_formation: string;
  annee_validee_min: number;
  profession_autorisee: string;
  base_reglementaire: string | null;
  actif: boolean;
}

/**
 * Registre en lecture seule des règles d'équivalence étudiant. Ces règles ont un
 * effet direct sur l'éligibilité à des missions : elles doivent donc passer par
 * une migration versionnée et une validation conformité, pas par une mutation
 * immédiate depuis le navigateur.
 */
export function EditeurEquivalencesScolarite() {
  const [liste, setListe] = useState<Equivalence[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let actif = true;
    const charger = async () => {
      const { data, error } = await (supabase as any).from('equivalences_scolarite')
        .select('id, formation, libelle_formation, annee_validee_min, profession_autorisee, base_reglementaire, actif')
        .order('formation', { ascending: true })
        .order('annee_validee_min', { ascending: true });

      if (!actif) return;
      if (error) toast.error('Le registre des équivalences est indisponible.');
      setListe((data || []) as Equivalence[]);
      setLoading(false);
    };
    charger();
    return () => { actif = false; };
  }, []);

  return (
    <section className="card-base">
      <div className="mb-1 flex items-center gap-2">
        <GraduationCap className="h-5 w-5 text-primary" aria-hidden="true" />
        <h2 className="text-base font-semibold text-foreground">Équivalences étudiant « faisant fonction »</h2>
      </div>
      <p className="mb-4 text-xs text-muted-foreground">
        Une règle active peut ouvrir l'accès à une profession de mission après contrôle des justificatifs de scolarité.
        La base réglementaire affichée doit être vérifiée pour chaque règle ; aucune conformité globale n'est présumée.
      </p>

      <div className="mb-4 flex items-start gap-2 rounded-lg border border-warning/30 bg-warning/5 p-3 text-xs text-foreground" role="note">
        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" aria-hidden="true" />
        <p>Modification directe désactivée. Toute création, activation ou suppression doit être revue par la conformité, documentée par une source primaire puis livrée dans une migration auditée.</p>
      </div>

      {loading ? (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Chargement…
        </div>
      ) : (
        <div className="space-y-2">
          {liste.length === 0 && <p className="text-sm text-muted-foreground">Aucune règle enregistrée.</p>}
          {liste.map((equivalence) => (
            <div
              key={equivalence.id}
              className={`flex items-start justify-between gap-3 rounded-lg border border-input p-2.5 ${equivalence.actif ? '' : 'opacity-60'}`}
            >
              <div className="min-w-0">
                <p className="text-sm font-medium text-foreground">
                  {equivalence.libelle_formation} · année {equivalence.annee_validee_min} validée →{' '}
                  <span className="text-primary">{getLabelProfession(equivalence.profession_autorisee)}</span>
                </p>
                {equivalence.base_reglementaire ? (
                  <p className="break-words text-[11px] text-muted-foreground">Source : {equivalence.base_reglementaire}</p>
                ) : (
                  <p className="text-[11px] font-medium text-destructive">Source primaire non renseignée — règle à revoir</p>
                )}
              </div>
              <span className={`inline-flex min-h-[28px] shrink-0 items-center rounded-full px-2 text-[11px] ${equivalence.actif ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'}`}>
                {equivalence.actif ? 'Active' : 'Inactive'}
              </span>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
