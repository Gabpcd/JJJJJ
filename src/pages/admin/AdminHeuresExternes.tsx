import { useEffect, useState } from 'react';
import { Loader2, FileText, Clock, CheckCircle, XCircle } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

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

/**
 * Page admin /admin/heures-externes — validation des heures externes (parcours 3200h).
 *
 * Les déclarations passées EN_ATTENTE par la vérification IA (écart heures lues vs
 * déclarées, ou volume non extrait) sont tranchées ici : VALIDE → comptent vers les
 * 3200h ; REJETE → écartées (motif obligatoire). La décision écrit valide_par/valide_le.
 */
export default function AdminHeuresExternes() {
  usePageTitle('Heures externes');
  const { afficherNotification } = useNotification();
  const [filtre, setFiltre] = useState<Filtre>('EN_ATTENTE');
  const [heures, setHeures] = useState<HeureExterneAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectionnee, setSelectionnee] = useState<HeureExterneAdmin | null>(null);
  const [openingId, setOpeningId] = useState<string | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_heures_externes' as any, {
      p_statut: filtre, p_limit: 200,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
    } else if ((data as any)?.success) {
      setHeures(((data as any).heures || []) as HeureExterneAdmin[]);
    } else {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || 'Erreur de chargement' });
    }
    setLoading(false);
  }

  useEffect(() => { charger(); }, [filtre]);

  const ouvrirAttestation = async (id: string, path: string | null) => {
    if (!path) return;
    setOpeningId(id);
    try {
      const { data, error } = await supabase.storage
        .from('attestations-heures-externes')
        .createSignedUrl(path, 3600);
      if (error || !data?.signedUrl) throw error || new Error('URL indisponible');
      window.open(data.signedUrl, '_blank');
    } catch {
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
            Déclarations d'heures hors Jolene. La vérification IA valide automatiquement les attestations cohérentes ;
            les cas en attente (écart ou volume non lu) sont à trancher ici.
          </p>
        </div>

        <div className="flex gap-2 flex-wrap">
          {(['EN_ATTENTE', 'VALIDE', 'REJETE', 'TOUS'] as const).map(f => (
            <button key={f} onClick={() => setFiltre(f)}
              className={`px-3 py-1.5 rounded-lg text-sm ${filtre === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground hover:bg-accent'}`}>
              {f === 'EN_ATTENTE' ? 'En attente' : f === 'VALIDE' ? 'Validées' : f === 'REJETE' ? 'Rejetées' : 'Toutes'}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-muted-foreground" /></div>
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
                        {h.profession && <span className="text-xs font-mono bg-muted px-1.5 py-0.5 rounded">{h.profession}</span>}
                        {h.type_exercice && <span className="text-[11px] text-muted-foreground">{h.type_exercice}</span>}
                        <span className={`text-xs px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${
                          h.statut_validation === 'VALIDE' ? 'bg-emerald-200 text-emerald-900' :
                          h.statut_validation === 'REJETE' ? 'bg-destructive/15 text-destructive' :
                          'bg-amber-200 text-amber-900 dark:bg-amber-800 dark:text-amber-100'}`}>
                          {h.statut_validation === 'VALIDE' ? <CheckCircle className="h-3 w-3" /> : h.statut_validation === 'REJETE' ? <XCircle className="h-3 w-3" /> : <Clock className="h-3 w-3" />}
                          {h.statut_validation === 'EN_ATTENTE' ? 'En attente' : h.statut_validation === 'VALIDE' ? 'Validée' : 'Rejetée'}
                        </span>
                      </div>

                      <p className="text-sm text-foreground mt-2">
                        <strong>{h.etablissement_nom}</strong>
                        {h.etablissement_type && <span className="text-muted-foreground"> · {h.etablissement_type.replace(/_/g, ' ').toLowerCase()}</span>}
                      </p>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {format(new Date(h.date_debut), 'd MMM yyyy', { locale: fr })} → {format(new Date(h.date_fin), 'd MMM yyyy', { locale: fr })}
                      </p>

                      <div className="flex items-center gap-3 flex-wrap mt-2 text-xs">
                        <span className="text-foreground"><strong>{h.heures_declarees.toLocaleString('fr-FR')}h</strong> déclarées</span>
                        {h.verifie_ia_le && (
                          <span className="inline-flex items-center gap-1 text-muted-foreground">
                            🤖 {h.heures_extraites_ia != null
                              ? <strong className="text-foreground">{h.heures_extraites_ia.toLocaleString('fr-FR')}h lues</strong>
                              : 'heures non extraites'}
                            {h.coherence_ia === true && <span className="text-emerald-600"> · cohérent ✓</span>}
                            {h.coherence_ia === false && <span className="text-amber-600"> · écart ⚠</span>}
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
                        <button
                          onClick={() => ouvrirAttestation(h.id, h.attestation_url)}
                          disabled={openingId === h.id}
                          className="btn-secondary text-xs inline-flex items-center gap-1 disabled:opacity-50">
                          {openingId === h.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FileText className="h-3.5 w-3.5" />}
                          Attestation
                        </button>
                      )}
                      {enAttente && (
                        <button onClick={() => setSelectionnee(h)} className="btn-primary text-xs">Traiter</button>
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
      <div className="bg-card border border-border rounded-xl max-w-lg w-full p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="text-lg font-bold text-foreground">Valider les heures externes</h2>

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
            { v: 'VALIDE', l: '✅ VALIDER (les heures comptent vers les 3200h)', i: <CheckCircle className="h-4 w-4 text-emerald-600" /> },
            { v: 'REJETE', l: '❌ REJETER (heures écartées)', i: <XCircle className="h-4 w-4 text-destructive" /> },
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
            {decision === 'REJETE' ? 'Motif du rejet * (min 5 chars, visible par le soignant)' : 'Commentaire (optionnel)'}
          </span>
          <textarea value={commentaire} onChange={e => setCommentaire(e.target.value)} className="input-base" rows={3}
            placeholder={decision === 'REJETE' ? 'Ex: attestation ne mentionne pas le volume d\'heures...' : 'Ex: vérifié auprès de l\'établissement.'} />
        </label>

        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">Annuler</button>
          <button onClick={soumettre} disabled={loading} className="btn-primary flex-1 disabled:opacity-50 inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Appliquer
          </button>
        </div>
      </div>
    </div>
  );
}
