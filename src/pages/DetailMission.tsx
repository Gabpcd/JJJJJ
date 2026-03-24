import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { useParams, useNavigate, Link } from 'react-router-dom';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { UserSearch, PlusCircle, Copy, XCircle, RotateCcw, Eye, Star, Send, CreditCard, MessageCircle, BellRing, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { BadgeStatut } from '@/components/BadgeStatut';
import { ChatMission } from '@/components/ChatMission';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { CodesPointageMission } from '@/components/CodesPointageMission';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EvaluationPostMission } from '@/components/EvaluationPostMission';
import { ChargementPage } from '@/components/ChargementPage';
import { BandeauRappelDPAE } from '@/components/BandeauRappelDPAE';
import { BoutonExclusion } from '@/components/BoutonExclusion';
import { useOuvrirConversation } from '@/hooks/useOuvrirConversation';
import { BoutonFavori } from '@/components/BoutonFavori';
import { RechercheRemplacantUrgence } from '@/components/RechercheRemplacantUrgence';
import { ListeCandidatures } from '@/components/ListeCandidatures';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

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
      console.log('fn_soignants_urgence result:', { count: soignants?.length, error });

      if (error || !soignants?.length) {
        toast.error(error?.message || 'Aucun soignant éligible dans le pool');
        setAlerting(false);
        return;
      }

      const { data: session } = await supabase.auth.getSession();
      const token = session?.session?.access_token;
      const debut = new Date(mission.debut_le);
      const fin = new Date(mission.fin_le);

      // Send notification + email to each soignant
      let sent = 0;
      for (const s of soignants as any[]) {
        try {
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
            const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
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
            }).catch(() => {});
          }
          sent++;
        } catch {
          // Non-blocking per soignant
        }
      }

      toast.success(`🚨 ${sent} soignant${sent > 1 ? 's' : ''} alerté${sent > 1 ? 's' : ''}`);
      setAlerted(true);
    } catch (err: any) {
      toast.error(`Erreur : ${err.message}`);
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
        <Button
          variant="destructive"
          size="sm"
          onClick={alerterPool}
          disabled={alerting || alerted}
        >
          {alerting ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <BellRing className="h-4 w-4 mr-1" />}
          {alerted ? 'Pool alerté ✅' : '🚨 Alerter le pool'}
        </Button>
      </div>
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
  const [alerteCDDU, setAlerteCDDU] = useState<any>(null);

  // IA Matching
  const [recommandations, setRecommandations] = useState<any[]>([]);
  const [loadingReco, setLoadingReco] = useState(false);
  const [proposing, setProposing] = useState<string | null>(null);
  const [nbCandidatures, setNbCandidatures] = useState(0);

  // Stripe Connect
  const [soignantHasConnect, setSoignantHasConnect] = useState(false);
  const [connectPayLoading, setConnectPayLoading] = useState(false);
  const [showConnectCheckout, setShowConnectCheckout] = useState(false);
  const [connectClientSecret, setConnectClientSecret] = useState<string | null>(null);
  const [connectDecomposition, setConnectDecomposition] = useState<{ commission_ttc: number; salaire_brut: number; total: number } | null>(null);

  useEffect(() => {
    if (!id) return;
    const load = async () => {
      const { data: m } = await supabase
        .from('missions')
        .select(`
          id, intitule, description, service, profession_requise,
          debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
          total_brut, net_a_payer, montant_ifm, montant_icp, montant_majoration_nuit,
          montant_majoration_dimanche, montant_majoration_ferie,
          heures_nuit, heures_dimanche, heures_ferie,
          montant_commission_ttc,
          statut, est_urgente, niveau_urgence, soignant_assigne_id, etablissement_id,
          mode_attribution,
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
        if (alerteData) setAlerteCDDU(alerteData);
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

      setLoading(false);
    };
    load();
  }, [id]);

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
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setProposing(null);
  };

  const handleAnnuler = async () => {
    const { data, error } = await supabase.rpc('fn_annuler_mission_etablissement' as any, { p_mission_id: id! });
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else if ((data as any)?.success === false) {
      afficherNotification({ type: 'erreur', message: (data as any).error });
    } else {
      afficherNotification({ type: 'succes', message: 'Mission annulée.' });
      navigate(role === 'ADMIN_PLATEFORME' ? '/admin/calendrier' : '/etablissement/missions');
    }
  };

  const backUrl = isAdmin ? '/admin/calendrier' : '/etablissement/missions';
  const backLabel = isAdmin ? '← Retour au calendrier' : '← Retour aux missions';

  if (loading || !mission) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;

  const m = mission;
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  const estAnnulee = m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT';

  return (
    <LayoutApp role={role}>
      <button onClick={() => navigate(backUrl)} className="text-sm text-primary hover:underline mb-4 inline-block">
        {backLabel}
      </button>

      {alerteCDDU?.alerte && (
        <div className="bg-warning/5 border border-warning/30 rounded-xl p-4 mb-4 flex items-start gap-3">
          <span className="text-lg">⚠️</span>
          <p className="text-sm font-medium text-warning">
            Ce soignant a travaillé {alerteCDDU.jours_travailles || '?'} jours chez vous sur 12 mois. Risque de requalification en CDI au-delà de 150 jours.
          </p>
        </div>
      )}

      <Tabs defaultValue="details">
        <TabsList className="mb-4">
          <TabsTrigger value="details">Détails</TabsTrigger>
          {m.statut === 'OUVERTE' && m.mode_attribution === 'CANDIDATURE' && (
            <TabsTrigger value="candidatures">Candidatures{nbCandidatures > 0 ? ` (${nbCandidatures})` : ''}</TabsTrigger>
          )}
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
                    </div>
                    <p className="text-sm text-muted-foreground">
                      {getLabelProfession(m.soignants.profession)} ·{' '}
                      <span className={`font-semibold ${scoreColor(m.soignants.score_fiabilite || 0)}`}>
                        ⭐ {m.soignants.score_fiabilite || 0}/100 ({scoreLabel(m.soignants.score_fiabilite || 0)})
                      </span>
                    </p>
                    <p className="text-sm text-muted-foreground">
                      {m.soignants.telephone ? `📱 ${m.soignants.telephone}` : '📞 Numéro disponible le jour de la mission'}
                    </p>
                    {m.soignants.numero_rpps && <p className="text-xs text-muted-foreground">RPPS : {m.soignants.numero_rpps}</p>}
                    <div className="mt-2 pt-2 border-t border-border space-y-2">
                      <BoutonExclusion excluId={m.soignant_assigne_id} typeExcluPar="ETABLISSEMENT" />
                    </div>
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

              <div className="card-base flex items-center gap-2 text-sm text-muted-foreground">
                <Eye className="h-4 w-4" />
                <span>0 soignants ont vu cette mission</span>
              </div>

              {/* Recherche remplaçant urgence si ABSENCE */}
              {m.statut === 'ABSENCE' && (
                <RechercheRemplacantUrgence
                  missionId={m.id}
                  onPropose={() => {}}
                  onError={(msg) => afficherNotification({ type: 'erreur', message: msg })}
                  onSuccess={(msg) => afficherNotification({ type: 'succes', message: msg })}
                />
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
              <DecompositionFinanciere mission={m} />
              {/* Payment mode indicator */}
              {m.montant_commission_ttc > 0 && (
                <div className="card-base flex items-center gap-2 text-xs text-muted-foreground">
                  {(m.etablissements as any)?.mode_paiement_commission === 'STRIPE_RESERVATION' ? (
                    <><CreditCard className="h-3.5 w-3.5 text-primary" /><span>Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — 💳 Prélevée à la réservation</span></>
                  ) : (m.etablissements as any)?.mode_paiement_commission === 'CHORUS_PRO' ? (
                    <><span>🏛️ Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — Chorus Pro</span></>
                  ) : (
                    <><span>📄 Commission : {m.montant_commission_ttc?.toFixed(2)} € TTC — Facturée en fin de mois</span></>
                  )}
                </div>
              )}
              {(m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS') && (
                <CodesPointageMission missionId={m.id} />
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
              {(isAdmin || m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS' || m.statut === 'TERMINEE' || m.statut === 'ABSENCE' || m.statut === 'LITIGE') && (
                <div id="chat-mission">
                  <ChatMission missionId={m.id} role="ETABLISSEMENT" prenomUtilisateur={isAdmin ? 'Admin' : (m.etablissements?.nom || 'Établissement')} isAdmin={isAdmin} />
                </div>
              )}
            </div>
          </div>
        </TabsContent>

        {/* Candidatures tab */}
        {m.statut === 'OUVERTE' && m.mode_attribution === 'CANDIDATURE' && (
          <TabsContent value="candidatures">
            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-4">📋 Candidatures reçues</h2>
              <ListeCandidatures
                missionId={m.id}
                modePaiement={(m.etablissements as any)?.mode_paiement_commission}
                onAccepted={() => window.location.reload()}
                onError={(msg) => afficherNotification({ type: 'erreur', message: msg })}
                onSuccess={(msg) => afficherNotification({ type: 'succes', message: msg })}
              />
            </div>
          </TabsContent>
        )}

        {m.statut === 'OUVERTE' && (
          <TabsContent value="recommandations">
            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-4">🤖 Soignants recommandés par l'IA</h2>
              {loadingReco ? (
                <p className="text-sm text-muted-foreground py-8 text-center">Analyse en cours…</p>
              ) : recommandations.length > 0 ? (
                <div className="overflow-x-auto">
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
                      {recommandations.map((r: any) => (
                        <tr key={r.id} className="hover:bg-muted/50">
                          <td className="py-3 font-medium text-foreground">
                            <div className="flex items-center gap-1">
                              {r.est_favori && <Star className="h-3.5 w-3.5 text-warning fill-warning" />}
                              {r.prenom} {r.nom}
                            </div>
                          </td>
                          <td className="py-3">
                            <span className={`badge-base text-[10px] ${scoreBadgeClasses(r.score_fiabilite || 0)}`}>
                              {r.score_fiabilite || 0}/100
                            </span>
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
                            </div>
                          </td>
                          <td className="py-3">
                            <button
                               onClick={() => proposerMission(r.id)}
                               disabled={proposing === r.id}
                               className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                             >
                               <Send className="h-3.5 w-3.5" />
                               {proposing === r.id ? '…' : 'Proposer'}
                             </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
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

      <ModalConfirmation
        ouvert={modalAnnuler}
        onFermer={() => setModalAnnuler(false)}
        onConfirmer={handleAnnuler}
        titre="Annuler cette mission ?"
        message={`La mission « ${m.intitule} » sera définitivement annulée.`}
        labelConfirmer="Annuler la mission"
        variante="danger"
      />

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
            window.location.reload();
          }
          setTerminating(false);
        }}
        titre="Terminer cette mission ?"
        message="Êtes-vous sûr de vouloir terminer cette mission ? Le soignant sera notifié et la facture sera générée."
        labelConfirmer="Terminer la mission"
      />

      {!isAdmin && m.statut === 'TERMINEE' && m.soignant_assigne_id && showEvaluation && (
        <EvaluationPostMission
          missionId={m.id}
          evalueId={m.soignant_assigne_id}
          typeEvaluateur="ETABLISSEMENT"
          nomEvalue={m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : 'Soignant'}
          onTermine={() => setShowEvaluation(false)}
        />
      )}
    </LayoutApp>
  );
}
