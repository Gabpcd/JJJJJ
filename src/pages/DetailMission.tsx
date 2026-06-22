import React, { useState, useEffect, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { logger } from '@/lib/logger';
import { useParams, useNavigate, Link } from 'react-router-dom';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { UserSearch, PlusCircle, Copy, XCircle, RotateCcw, Star, Send, CreditCard, MessageCircle, BellRing, Scale } from 'lucide-react';
import { Textarea } from '@/components/ui/textarea';
import { LayoutApp } from '@/components/LayoutApp';
import { BadgeStatut } from '@/components/BadgeStatut';
import { ChatMission } from '@/components/ChatMission';
import { ChatConversation } from '@/components/ChatConversation';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { FactureHonorairesCard } from '@/components/FactureHonorairesCard';
import { BlocContratTravailMission } from '@/components/BlocContratTravailMission';
import { AffichageCodeRotatifEtab } from '@/components/pointage/AffichageCodeRotatifEtab';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { ModalConfirmation } from '@/components/ModalConfirmation';
// Sprint 8 ter-G PR 1 — modales chargées à la demande (code splitting)
const ModaleAnnulationMissionEtab = lazy(() =>
  import('@/components/etablissement/ModaleAnnulationMissionEtab').then((m) => ({
    default: m.ModaleAnnulationMissionEtab,
  })),
);
const EvaluationPostMission = lazy(() =>
  import('@/components/EvaluationPostMission').then((m) => ({
    default: m.EvaluationPostMission,
  })),
);
import { ChargementPage } from '@/components/ChargementPage';
import { BandeauRappelDPAE } from '@/components/BandeauRappelDPAE';
import { BoutonExclusion } from '@/components/BoutonExclusion';
import { useOuvrirConversation } from '@/hooks/useOuvrirConversation';
import { BoutonFavori } from '@/components/BoutonFavori';
import { BoutonNoterMission } from '@/components/BoutonNoterMission';
import { RechercheRemplacantUrgence } from '@/components/RechercheRemplacantUrgence';
import { WorkflowPaiementMission } from '@/components/WorkflowPaiementMission';
import { ListeCandidatures } from '@/components/ListeCandidatures';
import { FilDiscussionLitige } from '@/components/FilDiscussionLitige';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { extraireMessageErreur } from '@/lib/erreurs';
import { payerMissionStripeConnectAvecGenerationAuto } from '@/lib/stripeMissionPay';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BandeauActionPrioritaire, type ActionPrioritaire } from '@/components/BandeauActionPrioritaire';
import { toast } from 'sonner';
import { capturerErreurSentry } from '@/lib/sentry';
import { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider } from '@/components/ui/tooltip';

function scoreColor(score: number): string {
  if (score >= 70) return 'text-success';
  if (score >= 40) return 'text-warning';
  return 'text-destructive';
}

function scoreLabel(score: number): string {
  if (score >= 70) return 'Fiable';
  if (score >= 40) return 'Moyen';
  return 'À surveiller';
}

function scoreBadgeClasses(score: number): string {
  if (score >= 70) return 'bg-success/10 text-success';
  if (score >= 40) return 'bg-warning/10 text-warning';
  return 'bg-destructive/10 text-destructive';
}

function AlerterPoolUrgence({ missionId, mission, user, afficherNotification }: { missionId: string; mission: any; user: any; afficherNotification: (n: any) => void }) {
  const [alerting, setAlerting] = useState(false);
  const [alerted, setAlerted] = useState(false);

  const alerterPool = async () => {
    setAlerting(true);
    try {
      const { data: soignants, error } = await supabase.rpc('fn_soignants_urgence' as any, { p_mission_id: missionId });
      logger.debug('fn_soignants_urgence result:', { count: soignants?.length, error });

      if (error || !soignants?.length) {
        toast.error('Aucun soignant éligible dans le pool d\'urgence.');
        setAlerting(false);
        return;
      }

      const { data: session } = await supabase.auth.getSession();
      const token = session?.session?.access_token;
      const debut = new Date(mission.debut_le);
      const fin = new Date(mission.fin_le);

      // Send notification + email to all soignants in parallel
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
      const results = await Promise.allSettled(
        (soignants as any[]).map(async (s) => {
          await supabase.rpc('fn_creer_notification', {
            p_destinataire_id: s.soignant_id,
            p_type_destinataire: 'SOIGNANT',
            p_type: 'MISSION_URGENTE',
            p_titre: `🚨 Mission urgente : ${mission.intitule}`,
            p_corps: `${mission.intitule} — ${format(debut, 'dd/MM à HH:mm', { locale: fr })}. Premier arrivé, premier servi !`,
            p_lien: `/soignant/missions/${missionId}`,
            p_type_ressource: 'MISSION',
            p_id_ressource: missionId,
          });
          if (token) {
            fetch(`${supabaseUrl}/functions/v1/send-email`, {
              method: 'POST',
              headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
              body: JSON.stringify({
                type: 'MISSION_URGENTE',
                destinataire_id: s.soignant_id,
                data: {
                  prenom: s.prenom,
                  mission: mission.intitule,
                  etablissement: mission.etablissements?.nom || '',
                  date: format(debut, 'dd/MM/yyyy', { locale: fr }),
                  heure_debut: format(debut, 'HH:mm'),
                  heure_fin: format(fin, 'HH:mm'),
                  taux_horaire: String(mission.taux_horaire_base),
                  mission_id: missionId,
                },
              }),
            }).catch((err) => { logger.warn('[DetailMission] send-email alert failed', err); });

            // SMS Twilio en parallèle (best-effort, ne bloque pas l'UI)
            // L'edge function send-sms vérifie sms_actif AND sms_alertes_actives
            // côté serveur — pas besoin de check ici. Si pas de téléphone, skip.
            if (s.telephone) {
              const smsBody = `🚨 Mission urgente : ${mission.intitule.slice(0, 40)} le ${format(debut, 'dd/MM', { locale: fr })} à ${format(debut, 'HH:mm')}. Voir l'app pour postuler.`;
              fetch(`${supabaseUrl}/functions/v1/send-sms`, {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  type: 'MISSION_URGENTE',
                  destinataire_id: s.soignant_id,
                  telephone: s.telephone,
                  contenu: smsBody,
                  prefix_type: 'MISSION_URGENTE',
                }),
              }).catch((err) => { logger.warn('[DetailMission] send-sms alert failed', err); });
            }
          }
        })
      );
      const sent = results.filter(r => r.status === 'fulfilled').length;

      toast.success(`🚨 ${sent} soignant${sent > 1 ? 's' : ''} alerté${sent > 1 ? 's' : ''}`);
      setAlerted(true);
    } catch (err: any) {
      capturerErreurSentry(err, 'DetailMission', 'alerter_pool');
      toast.error('Erreur lors de l\'envoi des alertes. Veuillez réessayer.');
    }
    setAlerting(false);
  };

  return (
    <div className="card-base border-destructive/30 bg-destructive/5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-semibold text-destructive flex items-center gap-2">
            <BellRing className="h-4 w-4" /> Mission urgente
          </p>
          <p className="text-xs text-muted-foreground mt-1">Alerter les soignants du pool d'urgence pour cette mission</p>
        </div>
        <BoutonY2K
          variant="destructive"
          size="sm"
          onClick={alerterPool}
          disabled={alerting || alerted}
          loading={alerting}
          iconeGauche={!alerting ? <BellRing className="h-4 w-4" /> : undefined}
        >
          {alerted ? 'Pool alerté ✅' : '🚨 Alerter le pool'}
        </BoutonY2K>
      </div>
    </div>
  );
}

/* ── Rétrocession : le titulaire déclare les honoraires bruts encaissés pendant
   le remplacement → rétrocession (%) et commission calculées automatiquement. ── */
function DeclarationRetrocession({ mission, onMaj }: { mission: any; onMaj: (patch: any) => void }) {
  const [montant, setMontant] = useState('');
  const [justificatif, setJustificatif] = useState<File | null>(null);
  const [envoi, setEnvoi] = useState(false);

  if (mission.montant_honoraires_bruts != null) {
    const retro = Math.round(mission.montant_honoraires_bruts * (mission.retrocession_pct ?? 50)) / 100 * 100 / 100;
    return (
      <div className="card-base border-success/30 bg-success/5">
        <p className="text-sm font-semibold text-success">💶 Honoraires déclarés : {Number(mission.montant_honoraires_bruts).toLocaleString('fr-FR')} €</p>
        <p className="text-xs text-muted-foreground mt-1">
          Rétrocession au remplaçant ({mission.retrocession_pct}%) : <strong>{Number(mission.net_a_payer ?? retro).toLocaleString('fr-FR')} €</strong> —
          {mission.honoraires_confirmes_le
            ? ' relevé confirmé par le remplaçant ✓. Réglez-le par virement puis déclarez le paiement ci-dessous.'
            : ' ⏳ en attente de confirmation du remplaçant (validation automatique sous 48h sans contestation).'}
        </p>
      </div>
    );
  }

  const declarer = async () => {
    const v = parseFloat(montant);
    if (!v || v <= 0) { toast.error('Saisissez le montant des honoraires encaissés.'); return; }
    if (!justificatif) { toast.error('Joignez le relevé d\'actes / bordereau justificatif (obligatoire).'); return; }
    setEnvoi(true);
    try {
      // Preuve opposable : relevé uploadé dans le bucket privé 'justificatifs',
      // référencé sur la mission (consultable par le remplaçant via litige et l'admin).
      const nomSanitise = justificatif.name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\w.-]+/g, '-');
      const cle = `retrocession/${mission.id}/${Date.now()}-${nomSanitise}`;
      const { error: upErr } = await supabase.storage.from('justificatifs')
        .upload(cle, justificatif, { contentType: justificatif.type || undefined, upsert: false });
      if (upErr) { toast.error('Téléversement du justificatif impossible.'); return; }

      const { data, error } = await supabase.rpc('fn_declarer_honoraires_retrocession' as any, {
        p_mission_id: mission.id, p_montant_honoraires: v, p_justificatif_cle: cle,
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Déclaration impossible.'); return; }
      toast.success(`Rétrocession calculée : ${(data as any).montant_retrocede} € à verser au remplaçant. Le soignant est notifié.`);
      onMaj({ montant_honoraires_bruts: v, net_a_payer: (data as any).montant_retrocede, total_brut: (data as any).montant_retrocede });
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <div className="card-base border-primary/30 bg-primary/5 space-y-2">
      <p className="text-sm font-semibold text-foreground">💶 Déclarez les honoraires du remplacement</p>
      <p className="text-xs text-muted-foreground">
        Montant brut des actes encaissés pendant le remplacement (vos feuilles de soins).
        La rétrocession ({mission.retrocession_pct ?? 50}%) et la commission Jolene seront calculées automatiquement.
        <strong> Justificatif obligatoire</strong> (relevé d'actes, journal SNIR ou bordereau de la période) —
        preuve opposable jointe à la mission.
      </p>
      <label className="text-xs font-medium text-foreground block">
        📎 Relevé justificatif *
        <input
          type="file"
          accept="image/*,.pdf"
          onChange={(e) => setJustificatif(e.target.files?.[0] || null)}
          className="block mt-1 text-xs text-muted-foreground file:mr-2 file:rounded-lg file:border-0 file:bg-primary/10 file:px-3 file:py-1.5 file:text-primary file:text-xs file:font-medium"
        />
        {justificatif && <span className="text-success">✓ {justificatif.name}</span>}
      </label>
      <div className="flex gap-2">
        <div className="relative flex-1 max-w-[220px]">
          <input type="number" step="0.01" min="1" value={montant} onChange={(e) => setMontant(e.target.value)}
            placeholder="Ex : 4 250" className="input-base pr-8" />
          <span aria-hidden="true" className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">€</span>
        </div>
        <BoutonY2K size="sm" onClick={declarer} disabled={envoi || !montant || !justificatif} loading={envoi}>
          Déclarer
        </BoutonY2K>
      </div>
    </div>
  );
}

/* ── Boost + Garantie remplacement (leviers de remplissage de la mission) ── */
function BoostEtGarantie({ mission, onMaj }: { mission: any; onMaj: (patch: any) => void }) {
  const [boosting, setBoosting] = useState(false);
  const [togglingGarantie, setTogglingGarantie] = useState(false);

  const booster = async () => {
    setBoosting(true);
    try {
      const { data, error } = await supabase.rpc('fn_booster_mission' as any, { p_mission_id: mission.id });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Boost impossible.'); return; }
      const nb = (data as any)?.soignants_notifies ?? 0;
      toast.success(`🚀 Mission boostée — ${nb} soignant${nb > 1 ? 's' : ''} compatible${nb > 1 ? 's' : ''} notifié${nb > 1 ? 's' : ''}, priorité dans le feed.`);
      onMaj({ boostee_le: new Date().toISOString() });
    } finally {
      setBoosting(false);
    }
  };

  const toggleGarantie = async () => {
    setTogglingGarantie(true);
    try {
      const actif = !mission.garantie_remplacement;
      const { data, error } = await supabase.rpc('fn_activer_garantie_mission' as any, { p_mission_id: mission.id, p_actif: actif });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Modification impossible.'); return; }
      toast.success(actif ? 'Garantie remplacement activée ✓' : 'Garantie remplacement désactivée.');
      onMaj({ garantie_remplacement: actif });
    } finally {
      setTogglingGarantie(false);
    }
  };

  return (
    <div className="card-base space-y-3">
      {/* Boost */}
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold text-foreground">🚀 Booster cette mission</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Notifie immédiatement les soignants compatibles dans le rayon et remonte la mission
            en tête de leur feed pendant 7 jours. <span className="text-success font-medium">Inclus — offre de lancement.</span>
          </p>
        </div>
        {mission.boostee_le ? (
          <span className="badge-base bg-primary/10 text-primary text-xs shrink-0">Boostée ✓</span>
        ) : mission.statut === 'OUVERTE' ? (
          <BoutonY2K size="sm" onClick={booster} disabled={boosting} loading={boosting}>
            Booster
          </BoutonY2K>
        ) : null}
      </div>

      {/* Garantie remplacement */}
      {(mission.statut === 'OUVERTE' || mission.statut === 'ASSIGNEE') && (
        <div className="flex items-center justify-between gap-3 pt-3 border-t border-border">
          <div className="min-w-0">
            <p className="text-sm font-semibold text-foreground">🛡️ Garantie remplacement</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Sans pointage 30 min après le début, une mission de remplacement urgente est diffusée
              automatiquement au pool de soignants disponibles (premier arrivé, premier servi).
              Le soignant assigné doit aussi confirmer sa présence la veille.
            </p>
          </div>
          <BoutonY2K
            size="sm"
            variant={mission.garantie_remplacement ? 'primary' : 'secondary'}
            onClick={toggleGarantie}
            disabled={togglingGarantie}
            loading={togglingGarantie}
          >
            {mission.garantie_remplacement ? 'Activée ✓' : 'Activer'}
          </BoutonY2K>
        </div>
      )}

      {/* Présence confirmée */}
      {mission.statut === 'ASSIGNEE' && mission.presence_confirmee_le && (
        <p className="text-xs text-success pt-2 border-t border-border">
          ✓ Présence confirmée par le soignant le {format(new Date(mission.presence_confirmee_le), 'dd/MM à HH:mm', { locale: fr })}
        </p>
      )}
    </div>
  );
}

export default function DetailMission({ role = 'ADMIN_ETABLISSEMENT' }: { role?: 'ADMIN_ETABLISSEMENT' | 'ADMIN_PLATEFORME' }) {
  usePageTitle('Détail mission');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const isAdmin = role === 'ADMIN_PLATEFORME';
  const baseMsg = isAdmin ? '/admin/messagerie' : '/etablissement/messagerie';
  const ouvrirConv = useOuvrirConversation(baseMsg);
  const [mission, setMission] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [modalAnnuler, setModalAnnuler] = useState(false);
  const [modalDupliquer, setModalDupliquer] = useState(false);
  const [modalTerminer, setModalTerminer] = useState(false);
  const [terminating, setTerminating] = useState(false);
  const [showEvaluation, setShowEvaluation] = useState(true);
  const [alerteRequalif, setAlerteRequalif] = useState<any>(null);

  // IA Matching
  const [recommandations, setRecommandations] = useState<any[]>([]);
  const [loadingReco, setLoadingReco] = useState(false);
  const [proposing, setProposing] = useState<string | null>(null);
  const [nbCandidatures, setNbCandidatures] = useState(0);

  // Litige existant
  const [litigeExistant, setLitigeExistant] = useState<any>(null);
  const [loadingLitige, setLoadingLitige] = useState(false);
  const [showLitigeForm, setShowLitigeForm] = useState(false);
  const [litigeMotif, setLitigeMotif] = useState('');
  const [litigeCreating, setLitigeCreating] = useState(false);

  const ouvrirLitige = async () => {
    if (litigeMotif.trim().length < 10) {
      toast.error('Le motif doit contenir au moins 10 caractères.');
      return;
    }
    setLitigeCreating(true);
    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: id,
      p_motif: litigeMotif.trim(),
    });
    setLitigeCreating(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Une erreur est survenue. Veuillez réessayer.');
      return;
    }
    toast.success('Litige ouvert avec succès');
    refresh();
  };

  // Stripe Connect
  const [soignantHasConnect, setSoignantHasConnect] = useState(false);
  const [connectPayLoading, setConnectPayLoading] = useState(false);
  const [showConnectCheckout, setShowConnectCheckout] = useState(false);
  const [connectClientSecret, setConnectClientSecret] = useState<string | null>(null);
  const [connectDecomposition, setConnectDecomposition] = useState<{ commission_ttc: number; salaire_brut: number; total: number } | null>(null);
  // Audit étab fix #3 : refreshTick remplace navigate(0) (full page reload).
  // Incrémente cet état pour re-fetcher les données ciblées sans perdre l'UI.
  const [refreshTick, setRefreshTick] = useState(0);
  const refresh = React.useCallback(() => setRefreshTick(t => t + 1), []);

  useEffect(() => {
    if (!id) return;
    const load = async () => {
      const { data: m } = await supabase
        .from('missions')
        .select(`
          id, intitule, description, service, profession_requise,
          specialite_medicale_requise, accepte_non_specialises,
          debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
          total_brut, net_a_payer, net_estime, montant_ifm, montant_icp, montant_majoration_nuit,
          montant_majoration_dimanche, montant_majoration_ferie,
          heures_nuit, heures_dimanche, heures_ferie,
          montant_commission_ttc, commission_facturee,
          statut, est_urgente, niveau_urgence, soignant_assigne_id, etablissement_id,
          mode_attribution, boostee_le, garantie_remplacement, presence_confirmee_le,
          mode_remuneration, retrocession_pct, montant_honoraires_bruts, honoraires_confirmes_le,
          type_contrat_recherche, type_contrat_applique, type_paiement_soignant, mode_paiement_soignant, choix_contrat_soignant,
          cree_le, modifie_le,
          etablissements(nom, adresse_ville, adresse_departement,
            taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
            taux_majoration_ferie_pourcent, mode_paiement_commission)
        `)
        .eq('id', id)
        .single();

      if (m && m.soignant_assigne_id) {
        const { data: sg } = await supabase.rpc('fn_soignant_pour_etablissement', { p_soignant_id: m.soignant_assigne_id });
        setMission({ ...m, soignants: sg || null });

        const { data: alerteData } = await supabase.rpc('fn_alerte_cddu_repetitif' as any, {
          p_soignant_id: m.soignant_assigne_id,
          p_etablissement_id: m.etablissement_id,
        });
        if (alerteData) setAlerteRequalif(alerteData);
      } else {
        setMission(m ? { ...m, soignants: null } : null);
      }

      // Count candidatures for tab badge
      if (m && (m as any).mode_attribution === 'CANDIDATURE' && (m as any).statut === 'OUVERTE') {
        const { count } = await supabase.from('candidatures')
          .select('id', { count: 'exact', head: true })
          .eq('mission_id', id!)
          .eq('statut', 'EN_ATTENTE');
        setNbCandidatures(count || 0);
      }

      // Check if litige exists for this mission
      if (m && ['TERMINEE', 'LITIGE', 'EN_COURS'].includes((m as any).statut)) {
        const { data: litigeData } = await supabase.rpc('fn_litige_pour_mission' as any, { p_mission_id: id });
        if (litigeData && (litigeData as any).exists !== false && (litigeData as any).litige_id) {
          setLitigeExistant(litigeData);
        }
      }

      // Check if soignant has Connect account
      if (m && m.soignant_assigne_id && (m as any).statut === 'TERMINEE') {
        const { data: connectData } = await supabase
          .from('stripe_connect_onboarding')
          .select('statut')
          .eq('soignant_id', m.soignant_assigne_id)
          .maybeSingle();
        setSoignantHasConnect(connectData?.statut === 'COMPLET');
      }

      setLoading(false);
    };
    load();
  }, [id, refreshTick]);

  // Load recommendations when tab is selected
  const chargerRecommandations = async () => {
    if (!id || recommandations.length > 0) return;
    setLoadingReco(true);
    const { data, error } = await supabase.rpc('fn_recommander_soignants' as any, { p_mission_id: id });
    if (!error && Array.isArray(data)) setRecommandations(data);
    setLoadingReco(false);
  };

  const proposerMission = async (soignantId: string) => {
    setProposing(soignantId);
    try {
      const { data: existingCandidature, error: checkError } = await supabase
        .from('candidatures')
        .select('id, statut')
        .eq('mission_id', id)
        .eq('soignant_id', soignantId)
        .maybeSingle();

      if (checkError) throw checkError;

      if (existingCandidature && !['REFUSEE', 'EXPIREE'].includes(existingCandidature.statut || '')) {
        afficherNotification({ type: 'erreur', message: 'Ce soignant a déjà une candidature en cours pour cette mission.' });
        return;
      }

      const { error: propositionError } = existingCandidature
        ? await supabase
            .from('candidatures')
            .update({
              statut: 'PROPOSEE',
              message: 'Mission proposée depuis les recommandations IA',
              traite_le: null,
              motif_refus: null,
            } as any)
            .eq('id', existingCandidature.id)
        : await supabase
            .from('candidatures')
            .insert({
              mission_id: id,
              soignant_id: soignantId,
              statut: 'PROPOSEE',
              message: 'Mission proposée depuis les recommandations IA',
            } as any);

      if (propositionError) throw propositionError;

      afficherNotification({ type: 'succes', message: 'Mission proposée au soignant !' });
    } catch (err: any) {
      capturerErreurSentry(err, 'DetailMission', 'proposer_soignant');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setProposing(null);
  };

  // handleAnnuler legacy supprimé : remplacé par ModaleAnnulationMissionEtab (Sprint 5.5 PR 3)
  // qui appelle fn_annuler_mission_etab avec motif structuré + décomposition L1243-8 / 1231-5.

  const handleBack = () => {
    if (window.history.length > 2) {
      navigate(-1);
    } else {
      navigate(isAdmin ? '/admin/calendrier' : '/etablissement/missions');
    }
  };
  const backLabel = isAdmin ? '← Retour au calendrier' : '← Retour';

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;
  if (!loading && !mission) return <LayoutApp role={role}><div className="text-center py-20"><p className="text-lg font-semibold text-foreground">Mission introuvable</p><p className="text-sm text-muted-foreground mt-2">Cette mission n'existe pas ou a été supprimée.</p><button onClick={() => navigate(-1)} className="btn-primary mt-4">Retour</button></div></LayoutApp>;

  const m = mission;
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  const estAnnulee = m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT';

  /* Hiérarchisation : LA prochaine action attendue de l'établissement —
     uniquement les cas certains depuis l'état chargé (pas de faux rappels). */
  const actionPrioritaire: ActionPrioritaire | null = (() => {
    if (isAdmin) return null;
    if (m.statut === 'TERMINEE' && (m as any).mode_remuneration === 'RETROCESSION' && m.montant_honoraires_bruts == null) {
      return {
        titre: 'Déclarez les honoraires du remplacement',
        description: 'Montant encaissé + justificatif — la rétrocession et la commission seront calculées automatiquement.',
        cta: 'Déclarer',
        cibleId: 'bloc-retro-declaration',
        variante: 'warning',
      };
    }
    if (m.statut === 'ABSENCE') {
      return {
        titre: 'Trouvez un remplaçant en urgence',
        description: 'Le soignant ne s\'est pas présenté — diffusez la mission au pool de remplaçants disponibles.',
        cta: 'Chercher',
        cibleId: 'bloc-remplacant',
        variante: 'destructive',
      };
    }
    if (m.mode_attribution === 'CANDIDATURE' && m.statut === 'OUVERTE' && nbCandidatures > 0) {
      return {
        titre: `${nbCandidatures} candidature${nbCandidatures > 1 ? 's' : ''} en attente`,
        description: 'Des soignants attendent votre réponse — examinez les profils.',
        cta: 'Examiner',
        cibleId: 'bloc-candidatures',
      };
    }
    if (m.statut === 'EN_COURS' && fin.getTime() < Date.now()) {
      return {
        titre: 'Terminez la mission',
        description: 'La mission est arrivée à son terme — clôturez-la pour déclencher la facturation et le paiement.',
        cta: 'Terminer',
        onClick: () => setModalTerminer(true),
      };
    }
    return null;
  })();

  return (
    <LayoutApp role={role}>
      <button onClick={handleBack} className="text-sm text-primary hover:underline mb-4 inline-block">
        {backLabel}
      </button>

      {actionPrioritaire && <BandeauActionPrioritaire {...actionPrioritaire} />}

      {alerteRequalif?.alerte && (
        <div className="bg-warning/5 border border-warning/30 rounded-xl p-4 mb-4 flex items-start gap-3">
          <span className="text-lg">⚠️</span>
          <p className="text-sm font-medium text-warning">
            Ce soignant a travaillé {alerteRequalif.jours_travailles || '?'} jours chez vous sur 12 mois. Risque de requalification en CDI au-delà de 150 jours.
          </p>
        </div>
      )}

      {/* Candidatures en haut si mode CANDIDATURE et OUVERTE */}
      {m.mode_attribution === 'CANDIDATURE' && m.statut === 'OUVERTE' && (
        <div id="bloc-candidatures" className="mb-4">
          <h2 className="text-lg font-bold text-foreground mb-3">Candidatures {nbCandidatures > 0 ? `(${nbCandidatures})` : ''}</h2>
          <ListeCandidatures
            missionId={m.id}
            missionProfession={m.profession_requise}
            missionSpecialiteMedicale={(m as any).specialite_medicale_requise}
            missionAccepteNonSpecialises={(m as any).accepte_non_specialises}
            modePaiement={(m.etablissements as any)?.mode_paiement_commission}
            onAccepted={() => refresh()}
            onError={(msg) => toast.error(msg)}
            onSuccess={(msg) => toast.success(msg)}
          />
        </div>
      )}

      <Tabs defaultValue="details">
        <TabsList className="mb-4">
          <TabsTrigger value="details">Détails</TabsTrigger>
          {m.statut === 'OUVERTE' && <TabsTrigger value="recommandations" onClick={chargerRecommandations}>Soignants recommandés</TabsTrigger>}
        </TabsList>

        <TabsContent value="details">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 space-y-4">
              <div className="card-base">
                <h1 className="text-2xl font-bold text-foreground mb-2">{m.intitule}</h1>
                <div className="flex items-center gap-2 flex-wrap mb-3">
                  <BadgeStatut statut={m.statut} />
                  {m.est_urgente && (
                    <span className="badge-base bg-destructive/10 text-destructive text-[10px]">
                      {m.niveau_urgence === 3 ? '🚨 Critique' : m.niveau_urgence === 2 ? '🔥 Élevé' : '⚡ Urgent'}
                    </span>
                  )}
                  {m.rist_plafond_applique && (
                    <span className="badge-base bg-warning/10 text-warning text-[10px]">⚠️ Rist plafonné</span>
                  )}
                </div>
                {m.description && <p className="text-sm text-muted-foreground mb-3">{m.description}</p>}
                <p className="text-sm text-muted-foreground">
                  {getLabelProfession(m.profession_requise)}{m.service ? ` · ${m.service}` : ''}
                </p>
                <hr className="my-3 border-border" />
                <p className="text-sm text-foreground">📅 {format(debut, 'EEEE d MMMM yyyy', { locale: fr })}</p>
                <p className="text-sm text-foreground">🕐 {format(debut, 'HH:mm')} → {format(fin, 'HH:mm')} ({m.duree_heures?.toFixed(1)}h)</p>
              </div>

              <div className="card-base">
                <h2 className="font-semibold text-foreground mb-3">Soignant assigné</h2>
                {m.soignants ? (
                  <div className="space-y-2">
                    <div className="flex items-center gap-2">
                      <Link to={`/etablissement/soignants/${m.soignant_assigne_id}`} className="font-semibold text-foreground hover:text-primary hover:underline">
                        👤 {m.soignants.prenom} {m.soignants.nom}
                      </Link>
                      <button
                        type="button"
                        onClick={() => ouvrirConv(m.soignant_assigne_id, m.id)}
                        className="h-8 w-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors shrink-0"
                        title="Contacter le soignant"
                      >
                        <MessageCircle className="h-4 w-4" />
                      </button>
                      {m.statut === 'TERMINEE' && m.soignant_assigne_id && (
                        <BoutonFavori soignantId={m.soignant_assigne_id} etablissementId={m.etablissement_id} />
                      )}
                      {m.statut === 'TERMINEE' && m.soignant_assigne_id && !isAdmin && (
                        <BoutonNoterMission missionId={m.id} sens="ETAB_VERS_SOIGNANT" missionIntitule={m.intitule} variant="secondary" />
                      )}
                    </div>
                    <p className="text-sm text-muted-foreground">
                      {getLabelProfession(m.soignants.profession)} ·{' '}
                      {m.soignants.score_fiabilite != null && m.soignants.total_missions_terminees > 0 ? (
                        <span className={`font-semibold ${scoreColor(m.soignants.score_fiabilite)}`}>
                          ⭐ {m.soignants.score_fiabilite}/100 ({scoreLabel(m.soignants.score_fiabilite)})
                        </span>
                      ) : (
                        <span className="text-muted-foreground">Pas encore d'évaluation</span>
                      )}
                    </p>
                    <p className="text-sm text-muted-foreground">
                      {m.soignants.telephone ? `📱 ${m.soignants.telephone}` : '📞 Numéro disponible le jour de la mission'}
                    </p>
                    {m.soignants.numero_rpps && <p className="text-xs text-muted-foreground">RPPS : {m.soignants.numero_rpps}</p>}
                    <div className="mt-2 pt-2 border-t border-border space-y-2">
                      <BoutonExclusion excluId={m.soignant_assigne_id} typeExcluPar="ETABLISSEMENT" />
                    </div>
                  </div>
                ) : m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS' ? (
                  <div className="text-center py-6">
                    <p className="text-sm text-muted-foreground">Chargement des informations du soignant…</p>
                  </div>
                ) : (
                  <div className="text-center py-6">
                    <UserSearch className="h-12 w-12 text-muted-foreground/30 mx-auto mb-2" />
                    <p className="text-sm text-muted-foreground">En attente d'un soignant</p>
                    <p className="text-xs text-muted-foreground">Les soignants qualifiés voient cette mission et peuvent postuler.</p>
                  </div>
                )}
              </div>

              {/* Alert pool urgence button */}
              {m.statut === 'OUVERTE' && m.est_urgente && (
                <AlerterPoolUrgence missionId={m.id} mission={m} user={user} afficherNotification={afficherNotification} />
              )}

              {/* Boost + garantie remplacement */}
              {(m.statut === 'OUVERTE' || m.statut === 'ASSIGNEE') && (
                <BoostEtGarantie mission={m} onMaj={(patch) => setMission((prev: any) => ({ ...prev, ...patch }))} />
              )}

              {/* Rétrocession : déclaration des honoraires encaissés en fin de mission */}
              {m.statut === 'TERMINEE' && (m as any).mode_remuneration === 'RETROCESSION' && (
                <div id="bloc-retro-declaration">
                  <DeclarationRetrocession mission={m} onMaj={(patch) => setMission((prev: any) => ({ ...prev, ...patch }))} />
                </div>
              )}


              {/* Recherche remplaçant urgence si ABSENCE */}
              {m.statut === 'ABSENCE' && (
                <div id="bloc-remplacant">
                <RechercheRemplacantUrgence
                  missionId={m.id}
                  onPropose={() => {}}
                  onError={(msg) => afficherNotification({ type: 'erreur', message: msg })}
                  onSuccess={(msg) => afficherNotification({ type: 'succes', message: msg })}
                />
                </div>
              )}

              <div className="card-base">
                <h2 className="font-semibold text-foreground mb-3">Historique</h2>
                <div className="space-y-3 text-sm">
                  <div className="flex items-center gap-3">
                    <PlusCircle className="h-4 w-4 text-primary flex-shrink-0" />
                    <span className="text-muted-foreground">Créée le {format(new Date(m.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}</span>
                  </div>
                  {m.modifie_le && m.modifie_le !== m.cree_le && (
                    <div className="flex items-center gap-3">
                      <PlusCircle className="h-4 w-4 text-info flex-shrink-0" />
                      <span className="text-muted-foreground">Modifiée le {format(new Date(m.modifie_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}</span>
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div className="space-y-4">
              <DecompositionFinanciere mission={m} role={isAdmin ? 'ADMIN' : 'ETAB'} />
              {/* Payment mode indicator — ordre priorité :
                  1. mode_paiement_soignant=STRIPE_CONNECT + commission_facturee : commission capturée à la source, déjà réglée
                  2. etablissements.mode_paiement_commission (STRIPE_RESERVATION / CHORUS_PRO)
                  3. fallback : facturée en fin de mois */}
              {m.montant_commission_ttc > 0 && (
                <div className="card-base flex items-center gap-2 text-xs text-muted-foreground">
                  {m.mode_paiement_soignant === 'STRIPE_CONNECT' && m.commission_facturee ? (
                    <><CreditCard className="h-3.5 w-3.5 text-success" /><span>Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — ✅ Capturée à la source par Stripe lors du paiement (déjà réglée)</span></>
                  ) : (m.etablissements as any)?.mode_paiement_commission === 'STRIPE_RESERVATION' ? (
                    <><CreditCard className="h-3.5 w-3.5 text-primary" /><span>Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — 💳 Prélevée à la réservation</span></>
                  ) : (m.etablissements as any)?.mode_paiement_commission === 'CHORUS_PRO' ? (
                    <><span>🏛️ Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — Chorus Pro</span></>
                  ) : (
                    <><span>📄 Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — Facturée en fin de mois</span></>
                  )}
                </div>
              )}
              {/* Contrat de travail SALARIE (Partie 2 onboarding) — étab uploade
                  le contrat CDD pour les missions salariées. Affichage seulement si
                  type_contrat_applique=SALARIE et soignant assigné. */}
              {m.soignant_assigne_id && (
                <div className="mb-4">
                  <BlocContratTravailMission
                    missionId={m.id}
                    typeContratApplique={(m as any).type_contrat_applique}
                    soignantAssigneId={m.soignant_assigne_id}
                    etablissementId={m.etablissement_id}
                    debutLe={m.debut_le}
                    role="ETABLISSEMENT"
                  />
                </div>
              )}
              {/* Facture honoraires — visible quand mission TERMINEE (une facture
                  a été générée à la déclaration paiement ou via generate-invoice).
                  L'étab doit pouvoir télécharger la facture comme preuve comptable. */}
              {m.statut === 'TERMINEE' && m.soignant_assigne_id && (
                <FactureHonorairesCard missionId={m.id} viewerRole={isAdmin ? 'ADMIN' : 'ETAB'} />
              )}
              {/* Workflow paiement mission */}
              {!isAdmin && m.statut === 'TERMINEE' && m.soignant_assigne_id && (
                <WorkflowPaiementMission
                  missionId={m.id}
                  soignantAssigneId={m.soignant_assigne_id}
                  etablissementId={m.etablissement_id}
                  soignantHasConnect={soignantHasConnect}
                  onStartConnectPay={async () => {
                    setConnectPayLoading(true);
                    const loadingToastId = toast.loading('Préparation du paiement…');
                    try {
                      const { data: sessionData } = await supabase.auth.getSession();
                      const accessToken = sessionData?.session?.access_token;
                      if (!accessToken) {
                        toast.error('Session expirée, veuillez vous reconnecter', { id: loadingToastId });
                        return;
                      }

                      // FIX 3 Option B — génération facture honoraires à la volée si absente.
                      const { result: data, error: fnErr, code, message, factureGenereeAuto } =
                        await payerMissionStripeConnectAvecGenerationAuto(m.id, accessToken, (msg) => toast.loading(msg, { id: loadingToastId }));

                      if (code === 'CONTRAT_SALARIE_NON_STRIPE') {
                        toast.error(message || "Les missions salariées doivent être payées par virement SEPA (bulletin de paie).", { id: loadingToastId, duration: 8000 });
                        return;
                      }

                      if (data?.already_paid) {
                        toast.info(data.message || 'Ce paiement a déjà été effectué', { id: loadingToastId });
                        refresh();
                        return;
                      }

                      if (fnErr || code || !data?.client_secret) {
                        toast.error(message || code || fnErr?.message || 'Erreur lors du paiement', { id: loadingToastId });
                        return;
                      }

                      toast.dismiss(loadingToastId);
                      if (factureGenereeAuto) {
                        toast.success('Facture honoraires générée automatiquement');
                      }
                      setConnectClientSecret(data.client_secret);
                      setConnectDecomposition({ commission_ttc: data.commission_ttc, salaire_brut: data.salaire_brut, total: data.total });
                      setShowConnectCheckout(true);
                    } finally {
                      setConnectPayLoading(false);
                    }
                  }}
                />
              )}
              {/* Litige section */}
              {!isAdmin && (m.statut === 'TERMINEE' || m.statut === 'LITIGE') && m.soignant_assigne_id && (
                litigeExistant ? (
                  <div className="card-base border-warning/30">
                    <h2 className="font-semibold text-foreground mb-3 flex items-center gap-2">⚖️ Litige en cours</h2>
                    <FilDiscussionLitige
                      litige={{
                        id: litigeExistant.litige_id,
                        statut: litigeExistant.statut,
                        motif: litigeExistant.motif,
                        cree_le: litigeExistant.cree_le,
                        accord_soignant: litigeExistant.accord_soignant,
                        accord_etablissement: litigeExistant.accord_etablissement,
                        resolution: litigeExistant.resolution,
                        missions: { intitule: m.intitule },
                      }}
                      onUpdate={() => refresh()}
                    />
                  </div>
                ) : (
                  <div className="card-base">
                    {showLitigeForm ? (
                      <div className="space-y-3">
                        <h3 className="font-semibold flex items-center gap-2"><Scale className="h-4 w-4 text-warning" /> Ouvrir un litige</h3>
                        <Textarea value={litigeMotif} onChange={e => setLitigeMotif(e.target.value)}
                          placeholder="Décrivez le problème rencontré (min. 10 caractères)..." rows={3} />
                        <div className="flex gap-2">
                          <BoutonY2K onClick={ouvrirLitige} disabled={litigeCreating || litigeMotif.trim().length < 10}>
                            {litigeCreating ? 'Création…' : '⚠️ Confirmer le litige'}
                          </BoutonY2K>
                          <BoutonY2K variant="ghost" onClick={() => setShowLitigeForm(false)}>Annuler</BoutonY2K>
                        </div>
                      </div>
                    ) : (
                      <button
                        onClick={() => setShowLitigeForm(true)}
                        className="text-sm text-warning hover:underline font-medium flex items-center gap-1.5"
                      >
                        ⚖️ Ouvrir un litige pour cette mission
                      </button>
                    )}
                  </div>
                )
              )}
              {(m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS') && (
                <AffichageCodeRotatifEtab missionId={m.id} />
              )}
              {isAdmin && (
                <button
                  type="button"
                  onClick={() => ouvrirConv(m.etablissement_id, m.id, true)}
                  className="text-sm font-medium text-primary hover:underline underline-offset-4 flex items-center gap-1 mb-3"
                >
                  <MessageCircle className="h-4 w-4" /> Contacter l'établissement
                </button>
              )}
              {(m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS' || m.statut === 'TERMINEE' || m.statut === 'ABSENCE' || m.statut === 'LITIGE') && m.soignant_assigne_id && (
                <div id="chat-mission">
                  <ChatConversation
                    missionId={m.id}
                    autreUserId={m.soignant_assigne_id}
                  />
                </div>
              )}
              {isAdmin && m.statut === 'OUVERTE' && (
                <div id="chat-mission">
                  <ChatMission missionId={m.id} role="ETABLISSEMENT" prenomUtilisateur="Admin" isAdmin />
                </div>
              )}
            </div>
          </div>
        </TabsContent>


        {m.statut === 'OUVERTE' && (
          <TabsContent value="recommandations">
            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-4">🤖 Soignants recommandés par l'IA</h2>
              {loadingReco ? (
                <p className="text-sm text-muted-foreground py-8 text-center">Analyse en cours…</p>
              ) : recommandations.length > 0 ? (
                <TooltipProvider>
                <div className="overflow-x-auto scroll-hint">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border text-left">
                        <th className="pb-2 font-medium text-muted-foreground">Soignant</th>
                        <th className="pb-2 font-medium text-muted-foreground">Fiabilité</th>
                        <th className="pb-2 font-medium text-muted-foreground">Distance</th>
                        <th className="pb-2 font-medium text-muted-foreground">Missions ici</th>
                        <th className="pb-2 font-medium text-muted-foreground">Score matching</th>
                        <th className="pb-2 font-medium text-muted-foreground">Alertes</th>
                        <th className="pb-2 font-medium text-muted-foreground"></th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {recommandations.map((r: any) => {
                        const typeExo = r.type_exercice || 'SALARIE';
                        const missionContrat = (m as any).type_contrat_recherche;
                        const incompatible = (missionContrat === 'LIBERAL' && typeExo === 'SALARIE') || (missionContrat === 'SALARIE' && typeExo === 'LIBERAL');
                        return (
                        <tr key={r.id} className="hover:bg-muted/50">
                          <td className="py-3 font-medium text-foreground">
                            <div className="flex items-center gap-1.5 flex-wrap">
                              {r.est_favori && <Star className="h-3.5 w-3.5 text-warning fill-warning" />}
                              <span>{r.prenom} {r.nom}</span>
                              <span className={`badge-base text-[10px] ${typeExo === 'LIBERAL' ? 'bg-info/10 text-info' : typeExo === 'MIXTE' ? 'bg-rose/10 text-rose' : 'bg-muted text-muted-foreground'}`}>
                                {typeExo === 'MIXTE' ? 'Salarié + Libéral' : typeExo === 'LIBERAL' ? 'Libéral' : 'Salarié'}
                              </span>
                            </div>
                          </td>
                          <td className="py-3">
                            <div className="space-y-0.5">
                              {r.score_fiabilite != null && r.score_fiabilite > 0 ? (
                                <span className={`badge-base text-[10px] ${scoreBadgeClasses(r.score_fiabilite)}`}>
                                  ⭐ {r.score_fiabilite}/100
                                </span>
                              ) : (
                                <span className="text-[10px] text-muted-foreground">—</span>
                              )}
                              {r.note_moyenne != null && r.nb_evaluations > 0 && (
                                <p className="text-[10px] text-muted-foreground">{Number(r.note_moyenne).toFixed(1)}/5 ({r.nb_evaluations} avis)</p>
                              )}
                            </div>
                          </td>
                          <td className="py-3 text-muted-foreground">{r.distance_km != null ? `${r.distance_km.toFixed(1)} km` : '—'}</td>
                          <td className="py-3 text-muted-foreground">{r.missions_etablissement ?? 0}</td>
                          <td className="py-3">
                            <span className="font-bold text-primary">{r.score_matching?.toFixed(0) ?? '—'}</span>
                          </td>
                          <td className="py-3">
                            <div className="flex flex-wrap gap-1">
                              {r.tous_documents_valides === false && (
                                <span className="badge-base bg-warning/10 text-warning text-[9px]">⚠️ Docs incomplets</span>
                              )}
                              {r.distance_km != null && r.distance_km > 50 && (
                                <span className="badge-base bg-muted text-muted-foreground text-[9px]">📍 Hors zone</span>
                              )}
                              {incompatible && (
                                <span className="badge-base bg-destructive/10 text-destructive text-[9px]">⚠️ Type incompatible</span>
                              )}
                            </div>
                          </td>
                          <td className="py-3">
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <span>
                                  <button
                                     onClick={() => proposerMission(r.id)}
                                     disabled={proposing === r.id || incompatible}
                                     className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50 disabled:cursor-not-allowed"
                                   >
                                     <Send className="h-3.5 w-3.5" />
                                     {proposing === r.id ? '…' : 'Proposer'}
                                   </button>
                                </span>
                              </TooltipTrigger>
                              {incompatible && <TooltipContent>Type d'exercice incompatible avec cette mission</TooltipContent>}
                            </Tooltip>
                          </td>
                        </tr>
                        );
                      })}
                    </tbody>
                   </table>
                 </div>
                </TooltipProvider>
              ) : (
                <div className="text-center py-8 space-y-2">
                  <p className="text-sm text-muted-foreground">Aucun soignant disponible pour cette profession.</p>
                  <p className="text-xs text-muted-foreground">Invitez des soignants via votre lien de parrainage.</p>
                </div>
              )}
            </div>
          </TabsContent>
        )}
      </Tabs>

      <div className="fixed bottom-16 left-0 right-0 z-30 flex gap-3 border-t border-border bg-card p-3 md:static md:mt-6 md:justify-end md:border-0 md:p-0">
        {!isAdmin && m.statut === 'OUVERTE' && (
          <button onClick={() => navigate(`/etablissement/missions/${m.id}/modifier`)} className="btn-secondary text-sm flex-1 md:flex-none">
            Modifier
          </button>
        )}
        {m.statut === 'EN_COURS' && (
          <button onClick={() => setModalTerminer(true)} className="text-sm font-semibold flex items-center gap-1 px-4 py-2 rounded-xl bg-success text-success-foreground hover:bg-success/90 transition flex-1 md:flex-none justify-center">
            ✅ Terminer la mission
          </button>
        )}
        <button onClick={() => setModalDupliquer(true)} className="text-sm font-medium text-muted-foreground hover:text-foreground flex items-center gap-1 px-3">
          <Copy className="h-4 w-4" /> Dupliquer
        </button>
        {(m.statut === 'OUVERTE' || m.statut === 'ASSIGNEE') && (
          <button onClick={() => setModalAnnuler(true)} className="btn-danger text-sm flex-1 md:flex-none">
            Annuler
          </button>
        )}
        {estAnnulee && (
          <button onClick={() => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)} className="btn-primary text-sm flex-1 md:flex-none flex items-center gap-1 justify-center">
            <RotateCcw className="h-4 w-4" /> Republier
          </button>
        )}
      </div>

      {/* Sprint 5.5 PR 3 : modale annulation avec décomposition L1243-8 / 1231-5
          Sprint 8 ter-G : lazy mount uniquement quand ouverte (code splitting) */}
      {modalAnnuler && (
        <Suspense fallback={null}>
          <ModaleAnnulationMissionEtab
            ouvert={true}
            onFermer={() => setModalAnnuler(false)}
            onAnnulee={() => {
              setModalAnnuler(false);
              navigate(role === 'ADMIN_PLATEFORME' ? '/admin/calendrier' : '/etablissement/missions');
            }}
            mission={{
              id: m.id,
              intitule: m.intitule,
              statut: m.statut,
              debut_le: m.debut_le,
              fin_le: m.fin_le,
              duree_heures: m.duree_heures,
              taux_horaire_base: m.taux_horaire_base,
              total_brut: m.total_brut,
              type_contrat_applique: (m as any).type_contrat_applique,
              type_contrat_recherche: (m as any).type_contrat_recherche,
            }}
          />
        </Suspense>
      )}

      <ModalConfirmation
        ouvert={modalDupliquer}
        onFermer={() => setModalDupliquer(false)}
        onConfirmer={() => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)}
        titre="Dupliquer cette mission ?"
        message={`Une copie de « ${m.intitule} » sera créée avec le statut OUVERTE.`}
        labelConfirmer="Dupliquer"
      />

      <ModalConfirmation
        ouvert={modalTerminer}
        onFermer={() => setModalTerminer(false)}
        onConfirmer={async () => {
          setTerminating(true);
          const { data, error } = await supabase.rpc('fn_terminer_mission' as any, { p_mission_id: id! });
          if (error) {
            afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
          } else if (data && typeof data === 'object' && (data as any).success === false) {
            afficherNotification({ type: 'erreur', message: (data as any).error || 'Erreur lors de la terminaison.' });
          } else {
            afficherNotification({ type: 'succes', message: 'Mission terminée ✅' });
            refresh();
          }
          setTerminating(false);
        }}
        titre="Terminer cette mission ?"
        message="Êtes-vous sûr de vouloir terminer cette mission ? Le soignant sera notifié et la facture sera générée."
        labelConfirmer="Terminer la mission"
      />

      {!isAdmin && m.statut === 'TERMINEE' && m.soignant_assigne_id && showEvaluation && (
        <Suspense fallback={null}>
          <EvaluationPostMission
            missionId={m.id}
            evalueId={m.soignant_assigne_id}
            typeEvaluateur="ETABLISSEMENT"
            nomEvalue={m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : 'Soignant'}
            onTermine={() => setShowEvaluation(false)}
          />
        </Suspense>
      )}

      {showConnectCheckout && connectClientSecret && (
        <StripeEmbeddedCheckout
          factureId={m.id}
          open={showConnectCheckout}
          onClose={() => setShowConnectCheckout(false)}
          onComplete={() => {
            setShowConnectCheckout(false);
            toast.success('Paiement effectué ! Le soignant recevra son salaire via Stripe.');
            refresh();
          }}
        />
      )}
    </LayoutApp>
  );
}
