import { useCallback, useEffect, useState } from 'react';
import { Loader2, FileText, Clock, CheckCircle, XCircle, RefreshCw } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getLabelProfession, getLabelTypeEtablissement } from '@/lib/constantes';

interface HeureExterneAdmin {
  id: string;
  soignant_id: string;
  soignant_nom: string;
  soignant_prenom: string;
  profession: string | null;
  type_exercice: string | null;
  etablissement_nom: string;
  etablissement_type: string | null;
  date_debut: string;
  date_fin: string;
  heures_declarees: number;
  heures_extraites_ia: number | null;
  coherence_ia: boolean | null;
  statut_validation: 'EN_ATTENTE' | 'VALIDE' | 'REJETE';
  commentaire_validation: string | null;
  attestation_url: string | null;
  attestation_nom_fichier: string | null;
  verifie_ia_le: string | null;
  cree_le: string;
}

type Filtre = 'EN_ATTENTE' | 'VALIDE' | 'REJETE' | 'TOUS';
const DELAI_CHARGEMENT_HEURES_MS = 15_000;

function avecDelaiHeures<T>(requete: PromiseLike<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = window.setTimeout(
      () => reject(new Error('Le chargement des heures a dépassé 15 secondes.')),
      DELAI_CHARGEMENT_HEURES_MS,
    );
    Promise.resolve(requete).then(
      (resultat) => { window.clearTimeout(timer); resolve(resultat); },
      (erreur) => { window.clearTimeout(timer); reject(erreur); },
    );
  });
}

/**
 * Page admin /admin/heures-externes — validation des heures externes (parcours 3200h).
 *
 * L'analyse automatique extrait des signaux mais ne valide aucune heure. Toutes
 * les déclarations non conclusivement invalides sont tranchées ici par un admin :
 * VALIDE → comptent vers les 3200h ; REJETE → écartées (motif obligatoire).
 */
export default function AdminHeuresExternes() {
  usePageTitle('Heures externes');
  const { afficherNotification } = useNotification();
  const [filtre, setFiltre] = useState<Filtre>('EN_ATTENTE');
  const [heures, setHeures] = useState<HeureExterneAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [selectionnee, setSelectionnee] = useState<HeureExterneAdmin | null>(null);
  const [openingId, setOpeningId] = useState<string | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    setErreurChargement(null);
    try {
      const { data, error } = await avecDelaiHeures(supabase.rpc('fn_admin_lister_heures_externes' as any, {
        p_statut: filtre, p_limit: 200,
      }));
      if (error) throw error;
      if (!(data as any)?.success) throw new Error((data as any)?.error || 'Erreur de chargement');
      setHeures(((data as any).heures || []) as HeureExterneAdmin[]);
    } catch (erreur) {
      const message = erreur instanceof Error ? erreur.message : 'Impossible de charger les heures externes.';
      setErreurChargement(message);
      afficherNotification({ type: 'erreur', message });
    } finally {
      setLoading(false);
    }
  }, [afficherNotification, filtre]);

  useEffect(() => { charger(); }, [charger]);

  const ouvrirAttestation = async (id: string, path: string | null) => {
    if (!path) return;

    const preview = window.open('about:blank', '_blank');
    if (!preview) {
      afficherNotification({
        type: 'erreur',
        message: 'Autorisez les fenêtres contextuelles pour consulter l’attestation.',
      });
      return;
    }
    preview.opener = null;

    setOpeningId(id);
    try {
      const { data, error } = await supabase.storage
        .from(path.includes('/heures-externes/') ? 'jolene-documents' : 'attestations-heures-externes')
        .createSignedUrl(path, 3600);
      if (error || !data?.signedUrl) throw error || new Error('URL indisponible');
      preview.location.replace(data.signedUrl);
    } catch {
      preview.close();
      afficherNotification({ type: 'erreur', message: 'Impossible d\'ouvrir l\'attestation.' });
    } finally {
      setOpeningId(null);
    }
  };

  return (
    <LayoutAdmin>
      <div className="max-w-5xl mx-auto p-4 space-y-4">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Heures externes — parcours 3200h</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Déclarations d'heures hors Jolene. L'analyse automatique prépare les contrôles ;
            toute validation comptabilisée exige votre décision humaine.
          </p>
        </div>

        <div className="flex gap-2 flex-wrap">
          {(['EN_ATTENTE', 'VALIDE', 'REJETE', 'TOUS'] as const).map(f => (
            <BoutonY2K key={f} size="sm" variant={filtre === f ? 'primary' : 'secondary'} onClick={() => setFiltre(f)}>
              {f === 'EN_ATTENTE' ? 'En attente' : f === 'VALIDE' ? 'Validées' : f === 'REJETE' ? 'Rejetées' : 'Toutes'}
            </BoutonY2K>
          ))}
        </div>

        {loading ? (
          <div className="flex items-center justify-center gap-2 py-8" role="status">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            <span className="text-sm text-muted-foreground">Chargement des déclarations…</span>
          </div>
        ) : erreurChargement ? (
          <div className="rounded-2xl border border-destructive/30 bg-destructive/5 p-6 text-center" role="alert">
            <p className="font-semibold text-foreground">Déclarations indisponibles</p>
            <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
            <BoutonY2K className="mt-4" size="sm" onClick={() => { void charger(); }} iconeGauche={<RefreshCw className="h-4 w-4" />}>
              Réessayer
            </BoutonY2K>
          </div>
        ) : heures.length === 0 ? (
          <EmptyState
            icone={<Clock />}
            mascotte={filtre === 'EN_ATTENTE' ? 'happy' : 'empty'}
            titre={filtre === 'EN_ATTENTE' ? 'Aucune déclaration à traiter' : 'Aucune déclaration'}
            description={filtre === 'EN_ATTENTE' ? 'Toutes les heures en attente ont été traitées.' : undefined}
            variant={filtre === 'EN_ATTENTE' ? 'success' : 'info'}
          />
        ) : (
          <div className="space-y-2">
            {heures.map(h => {
              const enAttente = h.statut_validation === 'EN_ATTENTE';
              return (
                <div key={h.id}
                  className={`rounded-xl border p-4 ${enAttente
                    ? 'border-amber-300 bg-amber-50/40 dark:bg-amber-950/20'
                    : 'border-border bg-card'}`}>
                  <div className="flex items-start justify-between gap-3 flex-col sm:flex-row">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-foreground">{h.soignant_prenom} {h.soignant_nom}</span>
                        {h.profession && <span className="text-xs bg-muted px-1.5 py-0.5 rounded">{getLabelProfession(h.profession)}</span>}
                        {h.type_exercice && <span className="text-[11px] text-muted-foreground">{h.type_exercice}</span>}
                        <BadgeY2K
                          variant={h.statut_validation === 'VALIDE' ? 'success' : h.statut_validation === 'REJETE' ? 'error' : 'warning'}
                          size="sm"
                          icone={h.statut_validation === 'VALIDE' ? <CheckCircle className="h-3 w-3" /> : h.statut_validation === 'REJETE' ? <XCircle className="h-3 w-3" /> : <Clock className="h-3 w-3" />}
                        >
                          {h.statut_validation === 'EN_ATTENTE' ? 'En attente' : h.statut_validation === 'VALIDE' ? 'Validée' : 'Rejetée'}
                        </BadgeY2K>
                      </div>

                      <p className="text-sm text-foreground mt-2">
                        <strong>{h.etablissement_nom}</strong>
                        {h.etablissement_type && <span className="text-muted-foreground"> · {getLabelTypeEtablissement(h.etablissement_type)}</span>}
                      </p>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {format(new Date(h.date_debut), 'd MMM yyyy', { locale: fr })} → {format(new Date(h.date_fin), 'd MMM yyyy', { locale: fr })}
                      </p>

                      <div className="flex items-center gap-3 flex-wrap mt-2 text-xs">
                        <span className="text-foreground"><strong>{h.heures_declarees.toLocaleString('fr-FR')}h</strong> déclarées</span>
                        {h.verifie_ia_le && (
                          <span className="inline-flex items-center gap-1 text-muted-foreground">
                            Analyse IA : {h.heures_extraites_ia != null
                              ? <strong className="text-foreground">{h.heures_extraites_ia.toLocaleString('fr-FR')}h lues</strong>
                              : 'heures non extraites'}
                            {h.coherence_ia === true && <span className="text-emerald-600"> · cohérent</span>}
                            {h.coherence_ia === false && <span className="text-amber-600"> · écart détecté</span>}
                          </span>
                        )}
                      </div>

                      {h.commentaire_validation && (
                        <p className="text-xs mt-2 bg-muted/40 p-2 rounded text-muted-foreground">{h.commentaire_validation}</p>
                      )}
                      <p className="text-[10px] text-muted-foreground mt-2">
                        Déclarée {format(new Date(h.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                      </p>
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      {h.attestation_url && (
                        <BoutonY2K
                          variant="secondary"
                          size="sm"
                          onClick={() => ouvrirAttestation(h.id, h.attestation_url)}
                          disabled={openingId === h.id}
                          loading={openingId === h.id}
                          iconeGauche={openingId !== h.id ? <FileText className="h-3.5 w-3.5" /> : undefined}
                        >
                          Attestation
                        </BoutonY2K>
                      )}
                      {enAttente && (
                        <BoutonY2K variant="primary" size="sm" onClick={() => setSelectionnee(h)}>Traiter</BoutonY2K>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {selectionnee && (
          <ModaleDecisionHeures
            heure={selectionnee}
            onFermer={() => setSelectionnee(null)}
            onTraitee={() => { setSelectionnee(null); charger(); }}
          />
        )}
      </div>
    </LayoutAdmin>
  );
}

function ModaleDecisionHeures({ heure, onFermer, onTraitee }: {
  heure: HeureExterneAdmin; onFermer: () => void; onTraitee: () => void;
}) {
  const { afficherNotification } = useNotification();
  const [decision, setDecision] = useState<'VALIDE' | 'REJETE'>('VALIDE');
  const [commentaire, setCommentaire] = useState('');
  const [loading, setLoading] = useState(false);

  async function soumettre() {
    if (decision === 'REJETE' && commentaire.trim().length < 5) {
      afficherNotification({ type: 'erreur', message: 'Motif requis pour un rejet (min 5 caractères).' });
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_valider_heures_externes' as any, {
        p_id: heure.id,
        p_decision: decision,
        p_commentaire: commentaire.trim() || null,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur' });
        return;
      }
      afficherNotification({ type: 'succes', message: decision === 'VALIDE' ? 'Heures validées — comptées vers les 3200h.' : 'Déclaration rejetée.' });
      onTraitee();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div role="dialog" aria-modal="true" aria-labelledby="admin-heures-externes-title" className="bg-card border border-border rounded-xl max-w-lg w-full p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 id="admin-heures-externes-title" className="text-lg font-bold text-foreground">Valider les heures externes</h2>

        <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-1">
          <p className="font-semibold">{heure.soignant_prenom} {heure.soignant_nom} — {heure.etablissement_nom}</p>
          <p>{heure.heures_declarees.toLocaleString('fr-FR')}h déclarées
            {heure.heures_extraites_ia != null && <> · <strong>{heure.heures_extraites_ia.toLocaleString('fr-FR')}h lues par l'IA</strong></>}
            {heure.coherence_ia === false && <span className="text-amber-600"> (écart)</span>}
          </p>
        </div>

        <div className="space-y-2">
          <span className="text-xs font-medium block">Décision *</span>
          {[
            { v: 'VALIDE', l: 'VALIDER (les heures comptent vers les 3 200 h)', i: <CheckCircle className="h-4 w-4 text-emerald-600" /> },
            { v: 'REJETE', l: 'REJETER (heures écartées)', i: <XCircle className="h-4 w-4 text-destructive" /> },
          ].map(opt => (
            <label key={opt.v} className="flex items-center gap-2 cursor-pointer p-2 rounded hover:bg-muted">
              <input type="radio" checked={decision === opt.v} onChange={() => setDecision(opt.v as any)} />
              {opt.i}
              <span className="text-sm">{opt.l}</span>
            </label>
          ))}
        </div>

        <label className="block">
          <span className="text-xs font-medium mb-1 block">
            {decision === 'REJETE' ? 'Motif du rejet * (min 5 caractères, visible par le soignant)' : 'Commentaire (optionnel)'}
          </span>
          <textarea value={commentaire} onChange={e => setCommentaire(e.target.value)} className="input-base" rows={3}
            placeholder={decision === 'REJETE' ? 'Ex: attestation ne mentionne pas le volume d\'heures...' : 'Ex: vérifié auprès de l\'établissement.'} />
        </label>

        <div className="flex gap-2">
          <BoutonY2K variant="secondary" size="md" onClick={onFermer} disabled={loading} className="flex-1">Annuler</BoutonY2K>
          <BoutonY2K variant="primary" size="md" onClick={soumettre} disabled={loading} loading={loading} className="flex-1">
            Appliquer
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}
