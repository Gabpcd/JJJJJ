import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AlertTriangle,
  CheckCircle2,
  ExternalLink,
  FileSearch,
  Loader2,
  RefreshCw,
  ShieldCheck,
  XCircle,
} from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { EmptyState } from '@/components/ui/EmptyState';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';

type Decision = 'APPROUVER' | 'REJETER';

interface RevueManuelle {
  id: string;
  type_entite: string;
  id_entite: string;
  service_en_echec: string;
  motif_echec: string | null;
  statut: string;
  priorite: number;
  cree_le: string | null;
  expire_le: string | null;
  est_compte_test: boolean;
  decision_directe: boolean;
  ressource_libelle: string;
  route_ressource: string;
  preuve_bucket: string | null;
  preuve_path: string | null;
  preuve_type: string | null;
  contexte: Record<string, unknown>;
  jeton_cas: string;
}

const LIBELLES_SERVICE: Record<string, string> = {
  VERIFY_RIB_ETABLISSEMENT: 'RIB établissement',
  VERIFY_FINESS_RECOUPEMENT: 'Recoupement FINESS',
  VERIFY_SIRET_IDENTITE_NON_CONCLUANTE: 'SIRET libéral — identité à confirmer',
  VERIFY_PIECE_IDENTITE_ETAB: 'Identité du représentant',
  VERIFY_JUSTIFICATIF_FONCTION: 'Fonction du représentant',
  REVUE_DEMANDEE_PAR_SOIGNANT: 'Document contesté par le soignant',
};

function formatDate(value: string | null): string {
  if (!value) return 'Date inconnue';
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? 'Date inconnue'
    : new Intl.DateTimeFormat('fr-FR', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(date);
}

function texte(value: unknown): string | null {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return null;
}

function contexteRevue(revue: RevueManuelle): Array<{ label: string; value: string }> {
  const contexte = revue.contexte || {};
  const donnees = contexte.donnees_revue && typeof contexte.donnees_revue === 'object'
    ? contexte.donnees_revue as Record<string, unknown>
    : {};
  const officielFiness = donnees.donnees_officielles_candidat
    && typeof donnees.donnees_officielles_candidat === 'object'
    ? donnees.donnees_officielles_candidat as Record<string, unknown>
    : {};
  const lignes = revue.service_en_echec === 'VERIFY_RIB_ETABLISSEMENT'
    ? [
      { label: 'SIRET', value: contexte.etablissement_siret },
      { label: 'IBAN (suffixe IA)', value: donnees.iban_last4 || contexte.rib_iban_last4 },
      { label: 'Cause', value: donnees.cause },
    ]
    : revue.service_en_echec === 'VERIFY_FINESS_RECOUPEMENT'
      ? [
        { label: 'FINESS candidat', value: donnees.finess_candidat },
        { label: 'SIRET profil', value: donnees.siret_profil },
        { label: 'Raison sociale', value: officielFiness.raison_sociale },
      ]
      : revue.service_en_echec === 'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE'
        ? [
          { label: 'Profession', value: contexte.soignant_profession },
          { label: 'SIRET candidat', value: donnees.siret_candidat },
          { label: 'Raison sociale', value: donnees.raison_sociale_officielle },
        ]
        : [
          { label: 'Type de preuve', value: revue.preuve_type },
          { label: 'Code', value: donnees.code },
        ];
  return lignes
    .map(({ label, value }) => ({ label, value: texte(value) || '—' }))
    .filter(({ value }) => value !== '—');
}

export default function AdminRevuesManuelles() {
  usePageTitle('Revues manuelles');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [revues, setRevues] = useState<RevueManuelle[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [actionId, setActionId] = useState<string | null>(null);
  const [ouvertureId, setOuvertureId] = useState<string | null>(null);
  const [motifs, setMotifs] = useState<Record<string, string>>({});
  const [ibans, setIbans] = useState<Record<string, string>>({});

  const charger = useCallback(async () => {
    setLoading(true);
    setErreurChargement(null);
    setRevues([]);
    try {
      const { data, error } = await supabase.rpc(
        'fn_admin_lister_revues_manuelles' as never,
        { p_limit: 200 } as never,
      );
      const payload = data as unknown as {
        success?: boolean;
        revues?: RevueManuelle[];
        error?: string;
      } | null;
      if (error || payload?.success !== true || !Array.isArray(payload.revues)) {
        throw error || new Error(payload?.error || 'Réponse de file invalide');
      }
      setRevues(payload.revues);
    } catch (error) {
      const message = error instanceof Error && error.message
        ? error.message
        : 'Impossible de charger la file de revue manuelle.';
      setErreurChargement(message);
      afficherNotification({ type: 'erreur', message });
    } finally {
      setLoading(false);
    }
  }, [afficherNotification]);

  useEffect(() => {
    void charger();
  }, [charger]);

  const ouvrirPreuve = async (revue: RevueManuelle) => {
    if (!revue.preuve_bucket || !revue.preuve_path) return;
    const preview = window.open('about:blank', '_blank');
    if (!preview) {
      afficherNotification({
        type: 'erreur',
        message: 'Autorisez les fenêtres contextuelles pour consulter cette preuve.',
      });
      return;
    }
    preview.opener = null;
    setOuvertureId(revue.id);
    try {
      const { data, error } = await supabase.storage
        .from(revue.preuve_bucket)
        .createSignedUrl(revue.preuve_path, 900);
      if (error || !data?.signedUrl) throw error || new Error('URL signée indisponible');
      preview.location.replace(data.signedUrl);
    } catch {
      preview.close();
      afficherNotification({
        type: 'erreur',
        message: 'La preuve n’a pas pu être ouverte. Rechargez la file puis réessayez.',
      });
    } finally {
      setOuvertureId(null);
    }
  };

  const decider = async (revue: RevueManuelle, decision: Decision) => {
    const motif = (motifs[revue.id] || '').trim();
    if (motif.length < 10) {
      afficherNotification({
        type: 'erreur',
        message: 'Expliquez la décision en au moins 10 caractères.',
      });
      return;
    }
    const ibanSaisi = (ibans[revue.id] || '').trim().toUpperCase();
    const ibanNormalise = ibanSaisi.replace(/[^A-Z0-9]/g, '');
    if (
      decision === 'APPROUVER'
      && revue.service_en_echec === 'VERIFY_RIB_ETABLISSEMENT'
      && !/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/.test(ibanNormalise)
    ) {
      afficherNotification({
        type: 'erreur',
        message: 'Recopiez l’IBAN complet visible sur le RIB; son checksum sera contrôlé côté serveur.',
      });
      return;
    }
    const verbe = decision === 'APPROUVER' ? 'Approuver' : 'Rejeter';
    if (!window.confirm(`${verbe} définitivement cette revue après contrôle de la ressource et de la preuve ?`)) {
      return;
    }

    setActionId(revue.id);
    try {
      const { data, error } = await supabase.rpc(
        'fn_admin_decider_revue_manuelle' as never,
        {
          p_revue_id: revue.id,
          p_decision: decision,
          p_motif: motif,
          p_jeton_cas: revue.jeton_cas,
          p_confirmation: decision === 'APPROUVER'
            && revue.service_en_echec === 'VERIFY_RIB_ETABLISSEMENT'
            ? { iban: ibanNormalise }
            : {},
        } as never,
      );
      const payload = data as unknown as {
        success?: boolean;
        idempotent?: boolean;
        error?: string;
      } | null;
      if (error || payload?.success !== true) {
        throw error || new Error(payload?.error || 'Décision non appliquée');
      }
      afficherNotification({
        type: 'succes',
        message: payload.idempotent
          ? 'Cette décision avait déjà été enregistrée.'
          : `Revue ${decision === 'APPROUVER' ? 'approuvée' : 'rejetée'} et auditée.`,
      });
      setMotifs(current => ({ ...current, [revue.id]: '' }));
      setIbans(current => ({ ...current, [revue.id]: '' }));
      await charger();
    } catch (error) {
      afficherNotification({
        type: 'erreur',
        message: error instanceof Error && error.message
          ? `${error.message} Rechargez la file avant toute nouvelle décision.`
          : 'Décision impossible. Rechargez la file avant de réessayer.',
      });
    } finally {
      setActionId(null);
    }
  };

  return (
    <LayoutAdmin>
      <div className="mx-auto w-full max-w-6xl space-y-6" aria-busy={loading}>
        <header className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-sm font-medium text-primary">Contrôle humain</p>
            <h1 className="mt-1 text-2xl font-bold text-foreground sm:text-3xl">Revues manuelles</h1>
            <p className="mt-2 max-w-3xl text-sm text-muted-foreground">
              Vérifiez la ressource et sa preuve avant de décider. Une file modifiée ou déjà traitée est refusée côté serveur.
            </p>
          </div>
          <BoutonY2K
            variant="secondary"
            className="min-h-[44px] gap-2"
            onClick={() => void charger()}
            disabled={loading || actionId !== null}
          >
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" />
            Actualiser
          </BoutonY2K>
        </header>

        {loading ? (
          <div role="status" className="flex min-h-52 items-center justify-center gap-3 text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin" aria-hidden="true" />
            Chargement sécurisé de la file…
          </div>
        ) : erreurChargement ? (
          <section role="alert" className="rounded-2xl border border-destructive/30 bg-destructive/5 p-5">
            <div className="flex items-start gap-3">
              <AlertTriangle className="mt-0.5 h-5 w-5 flex-none text-destructive" aria-hidden="true" />
              <div className="min-w-0 flex-1">
                <h2 className="font-semibold text-foreground">File indisponible</h2>
                <p className="mt-1 break-words text-sm text-muted-foreground">{erreurChargement}</p>
                <BoutonY2K className="mt-4 min-h-[44px] gap-2" onClick={() => void charger()}>
                  <RefreshCw className="h-4 w-4" aria-hidden="true" /> Réessayer
                </BoutonY2K>
              </div>
            </div>
          </section>
        ) : revues.length === 0 ? (
          <EmptyState
            icone={<ShieldCheck />}
            titre="Aucune revue en attente"
            description="Toutes les vérifications nécessitant une intervention humaine ont été traitées."
            variant="success"
          />
        ) : (
          <section aria-label={`${revues.length} revues manuelles en attente`} className="space-y-4">
            <p role="status" className="text-sm text-muted-foreground">
              {revues.length} revue{revues.length > 1 ? 's' : ''} en attente
            </p>
            {revues.map(revue => {
              const contexte = contexteRevue(revue);
              const actionEnCours = actionId === revue.id;
              return (
                <CardY2K key={revue.id} hoverLift={false} className="space-y-5">
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="rounded-full bg-warning/10 px-2.5 py-1 text-xs font-semibold text-warning-foreground">
                          Priorité {revue.priorite}/5
                        </span>
                        <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                          {revue.statut.replace(/_/g, ' ')}
                        </span>
                        {revue.est_compte_test && (
                          <span className="rounded-full border border-primary/30 bg-primary/5 px-2.5 py-1 text-xs font-semibold text-primary">
                            Donnée de test
                          </span>
                        )}
                      </div>
                      <h2 className="mt-3 break-words text-lg font-semibold text-foreground">
                        {LIBELLES_SERVICE[revue.service_en_echec] || revue.service_en_echec.replace(/_/g, ' ')}
                      </h2>
                      <p className="mt-1 break-words text-sm font-medium text-foreground">{revue.ressource_libelle}</p>
                      <p className="mt-1 text-xs text-muted-foreground">Ouverte le {formatDate(revue.cree_le)}</p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {revue.preuve_bucket && revue.preuve_path && (
                        <BoutonY2K
                          variant="secondary"
                          size="sm"
                          className="min-h-[44px] gap-2"
                          onClick={() => void ouvrirPreuve(revue)}
                          disabled={ouvertureId === revue.id || actionEnCours}
                        >
                          {ouvertureId === revue.id
                            ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                            : <FileSearch className="h-4 w-4" aria-hidden="true" />}
                          Ouvrir la preuve <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
                        </BoutonY2K>
                      )}
                      <BoutonY2K
                        variant="secondary"
                        size="sm"
                        className="min-h-[44px] gap-2"
                        onClick={() => navigate(revue.route_ressource)}
                        disabled={actionEnCours}
                      >
                        Ouvrir la ressource <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
                      </BoutonY2K>
                    </div>
                  </div>

                  <div className="rounded-xl border border-border bg-muted/20 p-4">
                    <p className="text-sm font-medium text-foreground">Motif d’entrée en revue</p>
                    <p className="mt-1 break-words text-sm text-muted-foreground">
                      {revue.motif_echec || 'La vérification automatique n’a pas pu conclure.'}
                    </p>
                    {contexte.length > 0 && (
                      <dl className="mt-4 grid gap-3 sm:grid-cols-3">
                        {contexte.map(ligne => (
                          <div key={ligne.label}>
                            <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{ligne.label}</dt>
                            <dd className="mt-1 break-words text-sm text-foreground">{ligne.value}</dd>
                          </div>
                        ))}
                      </dl>
                    )}
                  </div>

                  {revue.decision_directe ? (
                    <div className="space-y-4 border-t border-border pt-4">
                      {revue.service_en_echec === 'VERIFY_RIB_ETABLISSEMENT' && (
                        <div className="max-w-xs space-y-2">
                          <Label htmlFor={`iban-${revue.id}`}>IBAN complet visible sur le RIB</Label>
                          <Input
                            id={`iban-${revue.id}`}
                            value={ibans[revue.id] || ''}
                            onChange={event => setIbans(current => ({
                              ...current,
                              [revue.id]: event.target.value.toUpperCase().replace(/[^A-Z0-9 ]/g, '').slice(0, 42),
                            }))}
                            autoComplete="off"
                            inputMode="text"
                            maxLength={42}
                            placeholder="FR76 3000 6000 0112 3456 7890 189"
                            className="min-h-[44px] uppercase"
                            disabled={actionEnCours}
                          />
                          <p className="text-xs text-muted-foreground">Le format et le checksum sont contrôlés; seul le suffixe est conservé après la décision.</p>
                        </div>
                      )}
                      {revue.service_en_echec === 'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE' && (
                        <p className="rounded-xl border border-info/30 bg-info/5 p-3 text-sm text-muted-foreground">
                          L’approbation exige une pièce d’identité officielle courante déjà vérifiée dans la modération documentaire.
                        </p>
                      )}
                      <div className="space-y-2">
                        <Label htmlFor={`motif-${revue.id}`}>Motif de la décision (obligatoire)</Label>
                        <Textarea
                          id={`motif-${revue.id}`}
                          value={motifs[revue.id] || ''}
                          onChange={event => setMotifs(current => ({
                            ...current,
                            [revue.id]: event.target.value.slice(0, 1000),
                          }))}
                          minLength={10}
                          maxLength={1000}
                          rows={3}
                          placeholder="Décrivez les éléments vérifiés et la raison du verdict…"
                          disabled={actionEnCours}
                        />
                        <p className="text-xs text-muted-foreground">10 à 1 000 caractères · journalisé avec le snapshot contrôlé</p>
                      </div>
                      <div className="flex flex-col gap-2 sm:flex-row">
                        <BoutonY2K
                          className="min-h-[44px] gap-2"
                          onClick={() => void decider(revue, 'APPROUVER')}
                          disabled={actionId !== null}
                        >
                          {actionEnCours
                            ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                            : <CheckCircle2 className="h-4 w-4" aria-hidden="true" />}
                          Approuver après contrôle
                        </BoutonY2K>
                        <BoutonY2K
                          variant="destructive"
                          className="min-h-[44px] gap-2"
                          onClick={() => void decider(revue, 'REJETER')}
                          disabled={actionId !== null}
                        >
                          <XCircle className="h-4 w-4" aria-hidden="true" />
                          Rejeter après contrôle
                        </BoutonY2K>
                      </div>
                    </div>
                  ) : (
                    <div className="flex items-start gap-3 rounded-xl border border-info/30 bg-info/5 p-4">
                      <ShieldCheck className="mt-0.5 h-5 w-5 flex-none text-info" aria-hidden="true" />
                      <p className="text-sm text-muted-foreground">
                        Cette preuve conserve son formulaire spécialisé et ses contrôles métier. Ouvrez la ressource pour la décider sans contourner ces règles.
                      </p>
                    </div>
                  )}
                </CardY2K>
              );
            })}
          </section>
        )}
      </div>
    </LayoutAdmin>
  );
}
