import React, { Suspense, useEffect } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/contexts/AuthContext";
import { NotificationProvider } from "@/contexts/NotificationContext";
import { RouteProtegee } from "@/components/RouteProtegee";
import { PageTransition } from "@/components/PageTransition";
import { ChargementPage } from "@/components/ChargementPage";
import { ScrollToTop } from "@/components/ScrollToTop";
import { captureAttribution } from "@/lib/attribution";
import { Toaster } from "sonner";
import { BandeauCookies } from "@/components/BandeauCookies";

/* ─── Public pages ─── */
const PageAccueil = lazy(() => import("./pages/PageAccueil"));
const RacineApp = lazy(() => import("./pages/RacineApp"));
const PageConnexion = lazy(() => import("./pages/PageConnexion"));
const PageResetPassword = lazy(() => import("./pages/PageResetPassword"));
const PscCallback = lazy(() => import("./pages/PscCallback"));
const MandatFacturation = lazy(() => import("./pages/MandatFacturation"));
// Session F (F2) — les anciennes pages FinaliserInscriptionEtab + VerificationEtablissement
// sont fusionnées dans ActiverEtablissement. Les fichiers sources restent en place
// (référencés dans la doc/migrations) mais ne sont plus routés ; les anciennes routes
// redirigent vers /etablissement/activer.
const ActiverEtablissement = lazy(() => import("./pages/ActiverEtablissement"));
const VerificationEmailEtab = lazy(() => import("./pages/VerificationEmailEtab"));
/* Session G2 : MesFacturesHonoraires / MesAvances / BulletinsPaie ne sont plus
   routés directement — leurs `Content` sont composés dans le hub « Mes finances »
   (MesGains). Les anciennes URLs redirigent vers /soignant/mes-gains?tab=…. */
const AdminMandatsFacturation = lazy(() => import("./pages/admin/AdminMandatsFacturation"));
const AdminBFA = lazy(() => import("./pages/admin/AdminBFA"));
const AdminAffacturage = lazy(() => import("./pages/admin/AdminAffacturage"));
const AdminChorusPro = lazy(() => import("./pages/admin/AdminChorusPro"));
const ConfirmerEmail = lazy(() => import("./pages/ConfirmerEmail"));
const InscriptionSoignant = lazy(() => import("./pages/InscriptionSoignant"));
const InscriptionSoignantCompletion = lazy(() => import("./pages/InscriptionSoignantCompletion"));
const InscriptionEtablissement = lazy(() => import("./pages/InscriptionEtablissement"));
const Tarifs = lazy(() => import("./pages/Tarifs"));
const DevenirSoignant = lazy(() => import("./pages/DevenirSoignant"));
const RecruterSoignants = lazy(() => import("./pages/RecruterSoignants"));
const InfirmiereLiberal = lazy(() => import("./pages/InfirmiereLiberal"));
const VilleLanding = lazy(() => import("./pages/VilleLanding"));
const ProfessionLanding = lazy(() => import("./pages/ProfessionLanding"));
const MissionPublique = lazy(() => import("./pages/MissionPublique"));
const APropos = lazy(() => import("./pages/APropos"));
const PageContact = lazy(() => import("./pages/PageContact"));
const PageCGU = lazy(() => import("./pages/PageCGU"));
const PageCGV = lazy(() => import("./pages/PageCGV"));
const PageConfidentialite = lazy(() => import("./pages/PageConfidentialite"));
const PageSuppressionCompte = lazy(() => import("./pages/PageSuppressionCompte"));
const PageMentionsLegales = lazy(() => import("./pages/PageMentionsLegales"));
const PageAccessibilite = lazy(() => import("./pages/PageAccessibilite"));
const PageAide = lazy(() => import("./pages/PageAide"));
const PageAideArticle = lazy(() => import("./pages/PageAideArticle"));
const PageAideProSanteConnect = lazy(() => import("./pages/PageAideProSanteConnect"));
const PageParametresNotifications = lazy(() => import("./pages/PageParametresNotifications"));
const PageRecherchesSauvegardees = lazy(() => import("./pages/PageRecherchesSauvegardees"));
const PageParametresSoignant = lazy(() => import("./pages/PageParametresSoignant"));
const PageInscriptionSucces = lazy(() => import("./pages/PageInscriptionSucces"));
const NotFound = lazy(() => import("./pages/NotFound"));
const WidgetRecrutement = lazy(() => import("./pages/WidgetRecrutement"));
const Telecharger = lazy(() => import("./pages/Telecharger"));

/* ─── Soignant pages ─── */
const MesDocuments = lazy(() => import("./pages/MesDocuments"));
const LitigesContestationsSoignant = lazy(() => import("./pages/LitigesContestationsSoignant"));
const DashboardSoignant = lazy(() => import("./pages/DashboardSoignant"));
const MonCompteSoignant = lazy(() => import("./pages/MonCompteSoignant"));
const ProfilSoignant = lazy(() => import("./pages/ProfilSoignant"));
const ProfilSoignantEtablissement = lazy(() => import("./pages/ProfilSoignantEtablissement"));
const RechercheSoignantsEtab = lazy(() => import("./pages/RechercheSoignantsEtab"));
const MissionsSoignant = lazy(() => import("./pages/MissionsSoignant"));
const RechercheMissions = lazy(() => import("./pages/RechercheMissions"));
const DetailMissionSoignant = lazy(() => import("./pages/DetailMissionSoignant"));
// Session G1 : SwipeMissions n'est plus routé (consolidé dans RechercheMissions via toggle).
// Le fichier source reste en place ; la route /soignant/swipe-missions redirige.
// Refonte nav : MesMatches et PlanningSoignant ne sont plus routés (redirects
// vers /soignant/missions). Fichiers conservés pour réintégration (vue calendrier).
const DetailSerieSoignant = lazy(() => import("./pages/DetailSerieSoignant"));
const DocumentsSoignant = lazy(() => import("./pages/DocumentsSoignant"));
const ConformiteSoignant = lazy(() => import("./pages/ConformiteSoignant"));
const PresencesSoignant = lazy(() => import("./pages/PresencesSoignant"));
const SyncCalendrier = lazy(() => import("./pages/SyncCalendrier"));
const MesGains = lazy(() => import("./pages/MesGains"));
const HistoriqueMissions = lazy(() => import("./pages/HistoriqueMissions"));
const PageScoreSoignant = lazy(() => import("./pages/PageScoreSoignant"));
const PageScoreEtablissement = lazy(() => import("./pages/PageScoreEtablissement"));
const EvaluationsSoignant = lazy(() => import("./pages/EvaluationsSoignant"));
const MesReclamationsEtab = lazy(() => import("./pages/MesReclamationsEtab"));
const PrevoyanceSoignant = lazy(() => import("./pages/PrevoyanceSoignant"));
const AttestationHeures = lazy(() => import("./pages/AttestationHeures"));
const MesReclamations = lazy(() => import("./pages/MesReclamations"));
const PasserEnLiberal = lazy(() => import("./pages/PasserEnLiberal"));
const ExclusionsSoignant = lazy(() => import("./pages/ExclusionsSoignant"));
const PremiumSoignant = lazy(() => import("./pages/PremiumSoignant"));
const ChargesSociales = lazy(() => import("./pages/ChargesSociales"));
const PageParrainage = lazy(() => import("./pages/PageParrainage"));
const PageMessagerie = lazy(() => import("./pages/PageMessagerie"));
const LitigesSoignant = lazy(() => import("./pages/LitigesSoignant"));
const LitigesEtablissement = lazy(() => import("./pages/LitigesEtablissement"));
const PageStripeConnect = lazy(() => import("./pages/PageStripeConnect"));

/* ─── Établissement pages ─── */
const DashboardEtablissement = lazy(() => import("./pages/DashboardEtablissement"));
const MonCompteEtablissement = lazy(() => import("./pages/MonCompteEtablissement"));
const ListeMissions = lazy(() => import("./pages/ListeMissions"));
const CreerMission = lazy(() => import("./pages/CreerMission"));
const DetailMission = lazy(() => import("./pages/DetailMission"));
const ModifierMission = lazy(() => import("./pages/ModifierMission"));
const PresencesEtablissement = lazy(() => import("./pages/PresencesEtablissement"));
const FacturationEtablissement = lazy(() => import("./pages/FacturationEtablissement"));
const AnalyticsEtablissement = lazy(() => import("./pages/AnalyticsEtablissement"));
// Session F7/G4 : « Planning équipes » (GestionShifts) pointait sur une table
// DEPRECATED — retiré de la nav (F7) puis de la route (code mort). Fichier conservé.
const DetailFacture = lazy(() => import("./pages/DetailFacture"));
const ExportPaie = lazy(() => import("./pages/ExportPaie"));
const DashboardRH = lazy(() => import("./pages/DashboardRH"));
const PremiumEtablissement = lazy(() => import("./pages/PremiumEtablissement"));
const ChorusConfig = lazy(() => import("./pages/ChorusConfig"));
const PoolUrgenceEtablissement = lazy(() => import("./pages/PoolUrgenceEtablissement"));
const PoolUrgenceSoignant = lazy(() => import("./pages/PoolUrgenceSoignant"));
const MesFavorisSoignant = lazy(() => import("./pages/MesFavorisSoignant"));
const MesFavorisEtablissement = lazy(() => import("./pages/MesFavorisEtablissement"));
const PageParrainageEtablissement = lazy(() => import("./pages/PageParrainageEtablissement"));
const DetailPresencesMission = lazy(() => import("./pages/DetailPresencesMission"));
const Parametres = lazy(() => import("./pages/Parametres"));
const EquipeEtablissement = lazy(() => import("./pages/EquipeEtablissement"));
const AccepterInvitationEtab = lazy(() => import("./pages/AccepterInvitationEtab"));
const EvaluationsAFaireEtab = lazy(() => import("./pages/EvaluationsAFaireEtab"));


/* ─── Shared protected ─── */
const ContratMission = lazy(() => import("./pages/ContratMission"));
const CertificatSignaturePage = lazy(() => import("./pages/CertificatSignaturePage"));
const ListeContrats = lazy(() => import("./pages/ListeContrats"));
const PageNotifications = lazy(() => import("./pages/PageNotifications"));
const DashboardGroupe = lazy(() => import("./pages/DashboardGroupe"));

/* ─── Admin pages ─── */
const AdminDashboard = lazy(() => import("./pages/admin/AdminDashboard"));
const AdminUtilisateurs = lazy(() => import("./pages/admin/AdminUtilisateurs"));
const AdminModeration = lazy(() => import("./pages/admin/AdminModeration"));
const AdminSignalements = lazy(() => import("./pages/admin/AdminSignalements"));
const AdminVerificationEtablissements = lazy(() => import("./pages/admin/AdminVerificationEtablissements"));
const AdminLitiges = lazy(() => import("./pages/admin/AdminLitiges"));
const AdminTemplatesContrats = lazy(() => import("./pages/admin/AdminTemplatesContrats"));
const AdminEditerTemplateContrat = lazy(() => import("./pages/admin/AdminEditerTemplateContrat"));
const AdminContrats = lazy(() => import("./pages/admin/AdminContrats"));
const AdminDetailContrat = lazy(() => import("./pages/admin/AdminDetailContrat"));
const AdminAlertesPointage = lazy(() => import("./pages/admin/AdminAlertesPointage"));
const AdminExternalisationsActions = lazy(() => import("./pages/admin/AdminExternalisationsActions"));
const AdminStatus = lazy(() => import("./pages/admin/AdminStatus"));
const AdminFacturation = lazy(() => import("./pages/admin/AdminFacturation"));
const AdminImpayees = lazy(() => import("./pages/admin/AdminImpayees"));
const AdminConformite = lazy(() => import("./pages/admin/AdminConformite"));
const AdminDemo = lazy(() => import("./pages/admin/AdminDemo"));
const AdminEmails = lazy(() => import("./pages/admin/AdminEmails"));
const AdminAPI = lazy(() => import("./pages/admin/AdminAPI"));
const AdminGroupes = lazy(() => import("./pages/admin/AdminGroupes"));
const AdminDetailUtilisateur = lazy(() => import("./pages/admin/AdminDetailUtilisateur"));
const AdminCalendrier = lazy(() => import("./pages/admin/AdminCalendrier"));
const AdminMissions = lazy(() => import("./pages/admin/AdminMissions"));
const AdminReclamations = lazy(() => import("./pages/admin/AdminReclamations"));
const AdminFinances = lazy(() => import("./pages/admin/AdminFinances"));
const AdminTauxCommission = lazy(() => import("./pages/admin/AdminTauxCommission"));
const AdminConfig = lazy(() => import("./pages/admin/AdminConfig"));
const AdminAuditLogs = lazy(() => import("./pages/admin/AdminAuditLogs"));
const AdminMessagesContact = lazy(() => import("./pages/admin/AdminMessagesContact"));
const AdminDPIA = lazy(() => import("./pages/admin/AdminDPIA"));
const AdminHealthcheck = lazy(() => import("./pages/admin/AdminHealthcheck"));
const AdminCohortEconomics = lazy(() => import("./pages/admin/AdminCohortEconomics"));
const AdminAuditRLS = lazy(() => import("./pages/admin/AdminAuditRLS"));
const AdminRGPDTools = lazy(() => import("./pages/admin/AdminRGPDTools"));
const AdminHeuresExternes = lazy(() => import("./pages/admin/AdminHeuresExternes"));
const AdminPlanningGlobal = lazy(() => import("./pages/admin/AdminPlanningGlobal"));
const AdminCockpitFondateur = lazy(() => import("./pages/admin/AdminCockpitFondateur"));
const AdminEquipe = lazy(() => import("./pages/admin/AdminEquipe"));
const AdminLevee = lazy(() => import("./pages/admin/AdminLevee"));
const AdminAcquisition = lazy(() => import("./pages/admin/AdminAcquisition"));
const AdminSales = lazy(() => import("./pages/admin/AdminSales"));
const ClassementSoignants = lazy(() => import("./pages/ClassementSoignants"));

const queryClient = new QueryClient();

// Capture GLOBALE de l'attribution d'acquisition (UTM + referrer + code parrainage
// ?ref=CODE) dès l'arrivée sur N'IMPORTE quelle page (y compris la page d'accueil,
// cible des liens/QR partagés jolene.app?ref=… ou des campagnes ?utm_source=…).
// Le code parrainage est mirroré en sessionStorage (JO-* → soignant, ETB-* → étab)
// puis auto-rempli à l'inscription ; l'attribution complète est jointe à l'inscription.
function CaptureAttribution() {
  useEffect(() => {
    captureAttribution();
  }, []);
  return null;
}

// Session G1 : ancienne route /soignant/swipe-missions → page canonique
// « Trouver une mission ». On force la préférence de vue sur « swipe » pour que
// la page s'ouvre directement sur le mode swipe (préserve les deep links).
function RedirectionSwipeMissions() {
  try { localStorage.setItem('jolene_missions_view_pref', 'swipe'); } catch { /* ignore */ }
  return <Navigate to="/soignant/recherche-missions" replace />;
}

function AppRoutes() {
  return (
    <PageTransition>
      <CaptureAttribution />
      <ScrollToTop />
      <Suspense fallback={<ChargementPage />}>
        <Routes>
          <Route path="/" element={<RacineApp />} />
          <Route path="/tarifs" element={<Tarifs />} />
          <Route path="/devenir-soignant" element={<DevenirSoignant />} />
          <Route path="/recruter-soignants" element={<RecruterSoignants />} />
          <Route path="/infirmiere-liberale" element={<InfirmiereLiberal />} />
          <Route path="/emploi-soignant/:ville" element={<VilleLanding />} />
          <Route path="/metier/:profession" element={<ProfessionLanding />} />
          <Route path="/mission/:id" element={<MissionPublique />} />
          <Route path="/a-propos" element={<APropos />} />
          <Route path="/contact" element={<PageContact />} />
          <Route path="/telecharger" element={<Telecharger />} />
          <Route path="/connexion" element={<PageConnexion />} />
          <Route path="/reset-password" element={<PageResetPassword />} />
          <Route path="/auth/psc/callback" element={<PscCallback />} />
          <Route path="/confirmer-email" element={<ConfirmerEmail />} />
          <Route path="/inscription/soignant" element={<InscriptionSoignant />} />
          <Route path="/inscription/soignant/completion" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><InscriptionSoignantCompletion /></RouteProtegee>} />
          <Route path="/inscription/etablissement" element={<InscriptionEtablissement />} />
          <Route path="/inscription/succes" element={<PageInscriptionSucces />} />
          <Route path="/verification-email-etab" element={<VerificationEmailEtab />} />

          {/* Pages légales — publiques */}
          <Route path="/cgu" element={<PageCGU />} />
          <Route path="/cgv" element={<PageCGV />} />
          <Route path="/confidentialite" element={<PageConfidentialite />} />
          <Route path="/politique-confidentialite" element={<PageConfidentialite />} />
          <Route path="/supprimer-mon-compte" element={<PageSuppressionCompte />} />
          <Route path="/mentions-legales" element={<PageMentionsLegales />} />
          <Route path="/accessibilite" element={<PageAccessibilite />} />
          <Route path="/aide" element={<PageAide />} />
          {/* Route statique enregistrée AVANT /aide/:slug pour qu'elle ait priorité */}
          <Route path="/aide/pro-sante-connect" element={<PageAideProSanteConnect />} />
          <Route path="/aide/:slug" element={<PageAideArticle />} />
          <Route path="/faq" element={<Navigate to="/aide" replace />} />
          <Route path="/help" element={<Navigate to="/aide" replace />} />

          {/* Soignant */}
          <Route path="/soignant/tableau-de-bord" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DashboardSoignant /></RouteProtegee>} />
          <Route path="/soignant/profil" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ProfilSoignant /></RouteProtegee>} />
          <Route path="/soignant/mon-compte" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MonCompteSoignant /></RouteProtegee>} />
          <Route path="/soignant/missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MissionsSoignant /></RouteProtegee>} />
          <Route path="/soignant/recherche-missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><RechercheMissions /></RouteProtegee>} />
          {/* Session G1 : la découverte par swipe est consolidée dans la page canonique
              « Trouver une mission » (vue Swipe via toggle). On force la préférence puis on
              redirige pour que la page s'ouvre directement sur la vue swipe. */}
          <Route path="/soignant/swipe-missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><RedirectionSwipeMissions /></RouteProtegee>} />
          {/* Refonte nav : « Matchs » absorbé par « Mes missions › À venir ». */}
          <Route path="/soignant/mes-matches" element={<Navigate to="/soignant/missions" replace />} />
          <Route path="/soignant/missions/serie/:serieId" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailSerieSoignant /></RouteProtegee>} />
          <Route path="/soignant/missions/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailMissionSoignant /></RouteProtegee>} />
          <Route path="/soignant/mes-documents" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesDocuments /></RouteProtegee>} />
          <Route path="/soignant/documents" element={<Navigate to="/soignant/mes-documents?tab=justificatifs" replace />} />
          {/* Refonte nav : le planning devient l'onglet « À venir » de Mes missions.
              La vue calendrier (mois) sera réintégrée comme toggle de cet onglet
              (PR dédiée) en réutilisant PlanningSoignant. */}
          <Route path="/soignant/planning" element={<Navigate to="/soignant/missions?tab=a-venir" replace />} />
          <Route path="/soignant/calendrier-sync" element={<Navigate to="/soignant/missions?tab=a-venir" replace />} />
          <Route path="/soignant/conformite" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ConformiteSoignant /></RouteProtegee>} />
          {/* Hub Réputation dissous (modèle Uber) : le score simple vit sur le Profil. */}
          <Route path="/soignant/reputation" element={<Navigate to="/soignant/profil" replace />} />
          <Route path="/soignant/presences" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PresencesSoignant /></RouteProtegee>} />
          <Route path="/soignant/presences/mission/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailPresencesMission role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/mes-gains" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesGains /></RouteProtegee>} />
          <Route path="/soignant/mandat-facturation" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MandatFacturation /></RouteProtegee>} />
          {/* Session G2 : pages argent consolidées dans le hub « Mes finances » (/soignant/mes-gains). */}
          <Route path="/soignant/mes-factures-honoraires" element={<Navigate to="/soignant/mes-gains?tab=factures" replace />} />
          <Route path="/soignant/mes-avances" element={<Navigate to="/soignant/mes-gains?tab=avances" replace />} />
          <Route path="/soignant/bulletins-paie" element={<Navigate to="/soignant/mes-gains?tab=bulletins" replace />} />
          <Route path="/soignant/historique-missions" element={<Navigate to="/soignant/missions?tab=passees" replace />} />
          <Route path="/soignant/fiabilite" element={<Navigate to="/soignant/score" replace />} />
          <Route path="/soignant/score" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageScoreSoignant /></RouteProtegee>} />
          <Route path="/soignant/evaluations" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><EvaluationsSoignant /></RouteProtegee>} />
          <Route path="/etablissement/score" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageScoreEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/mes-reclamations" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><MesReclamationsEtab /></RouteProtegee>} />
          <Route path="/soignant/fiabilite-legacy" element={<Navigate to="/soignant/score" replace />} />
          <Route path="/soignant/parcours-3200h" element={<Navigate to="/soignant/passer-en-liberal" replace />} />
          <Route path="/soignant/prevoyance" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PrevoyanceSoignant /></RouteProtegee>} />
          <Route path="/soignant/attestation-heures" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><AttestationHeures /></RouteProtegee>} />
          <Route path="/soignant/dpae" element={<Navigate to="/soignant/mes-documents?tab=dpae" replace />} />
          <Route path="/soignant/reclamations" element={<Navigate to="/soignant/litiges?tab=reclamations" replace />} />
          <Route path="/soignant/passer-en-liberal" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PasserEnLiberal /></RouteProtegee>} />
          <Route path="/soignant/exclusions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ExclusionsSoignant /></RouteProtegee>} />
          <Route path="/soignant/contrats" element={<Navigate to="/soignant/mes-documents?tab=contrats" replace />} />
          <Route path="/soignant/premium" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PremiumSoignant /></RouteProtegee>} />
          <Route path="/soignant/charges" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ChargesSociales /></RouteProtegee>} />
          <Route path="/soignant/notifications" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageNotifications role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/parrainage" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageParrainage /></RouteProtegee>} />
          <Route path="/soignant/messagerie" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageMessagerie role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/litiges" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><LitigesContestationsSoignant /></RouteProtegee>} />
          <Route path="/soignant/stripe-connect" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageStripeConnect /></RouteProtegee>} />
          <Route path="/soignant/classement" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ClassementSoignants /></RouteProtegee>} />

          {/* Établissement */}
          <Route path="/etablissement/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/mon-compte" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><MonCompteEtablissement /></RouteProtegee>} />
          {/* Session F (F2) — page unique « Activer mon établissement » (fusion contrat + vérification + RIB différé) */}
          <Route path="/etablissement/activer" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ActiverEtablissement /></RouteProtegee>} />
          {/* Anciennes routes conservées en redirections pour ne pas casser les deep links (e-mails, articles d'aide, gates DB). */}
          <Route path="/etablissement/finaliser-inscription" element={<Navigate to="/etablissement/activer" replace />} />
          <Route path="/etablissement/verification" element={<Navigate to="/etablissement/activer" replace />} />
          {/* Session G3 — hub compte unique : l'index Paramètres redirige vers
              « Mon compte » (les réglages compte/mot de passe/GPS y sont foldés).
              ⚠️ Les SOUS-routes /parametres/notifications et
              /parametres/recherches-sauvegardees restent intactes ci-dessous. */}
          {/* « Tous les paramètres » dissous : doublon de Compte. Ses 2 entrées uniques
              (Recherches sauvegardées, Exclusions) sont remontées dans Compte. */}
          <Route path="/soignant/parametres-complet" element={<Navigate to="/soignant/mon-compte" replace />} />
          <Route path="/soignant/parametres" element={<Navigate to="/soignant/mon-compte" replace />} />
          <Route path="/soignant/parametres/notifications" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageParametresNotifications /></RouteProtegee>} />
          <Route path="/etablissement/parametres/notifications" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageParametresNotifications /></RouteProtegee>} />
          <Route path="/soignant/parametres/recherches-sauvegardees" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageRecherchesSauvegardees role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/etablissement/parametres/recherches-sauvegardees" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageRecherchesSauvegardees role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
          <Route path="/etablissement/parametres" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><Parametres /></RouteProtegee>} />
          <Route path="/etablissement/profil" element={<Navigate to="/etablissement/parametres?tab=profil" replace />} />
          <Route path="/etablissement/soignants" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><RechercheSoignantsEtab /></RouteProtegee>} />
          <Route path="/etablissement/soignants/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ProfilSoignantEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/missions" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ListeMissions /></RouteProtegee>} />
          <Route path="/etablissement/missions/creer" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><CreerMission /></RouteProtegee>} />
          <Route path="/etablissement/missions/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailMission /></RouteProtegee>} />
          <Route path="/etablissement/missions/:id/modifier" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ModifierMission /></RouteProtegee>} />
          <Route path="/etablissement/presences" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PresencesEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/contrats" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ListeContrats role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
          <Route path="/etablissement/facturation" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><FacturationEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/facturation/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailFacture /></RouteProtegee>} />
          <Route path="/etablissement/analytics" element={<Navigate to="/etablissement/rh?tab=analytics" replace />} />
          <Route path="/etablissement/assurance" element={<Navigate to="/etablissement/contrats" replace />} />
          <Route path="/etablissement/export-paie" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ExportPaie /></RouteProtegee>} />
          <Route path="/etablissement/rh" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardRH /></RouteProtegee>} />
          <Route path="/etablissement/mon-groupe" element={<Navigate to="/etablissement/parametres?tab=groupe" replace />} />
          <Route path="/etablissement/notifications" element={<Navigate to="/etablissement/parametres?tab=config" replace />} />
          <Route path="/etablissement/exclusions" element={<Navigate to="/etablissement/parametres?tab=exclusions" replace />} />
          <Route path="/etablissement/api" element={<Navigate to="/etablissement/parametres?tab=config" replace />} />
          <Route path="/etablissement/premium" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PremiumEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/chorus-config" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ChorusConfig /></RouteProtegee>} />
          <Route path="/etablissement/pool-urgence" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PoolUrgenceEtablissement /></RouteProtegee>} />
          <Route path="/soignant/pool-urgence" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PoolUrgenceSoignant /></RouteProtegee>} />
          <Route path="/soignant/mes-favoris" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesFavorisSoignant /></RouteProtegee>} />
          <Route path="/etablissement/mes-favoris" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><MesFavorisEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/parrainage" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageParrainageEtablissement /></RouteProtegee>} />
          {/* Session G4 — déduplication : /etablissement/dashboard rendait le même
              DashboardEtablissement que /etablissement/tableau-de-bord (canonique).
              Redirection pour ne garder qu'une seule URL. */}
          <Route path="/etablissement/dashboard" element={<Navigate to="/etablissement/tableau-de-bord" replace />} />
          <Route path="/etablissement/contrat-plateforme" element={<Navigate to="/etablissement/contrats" replace />} />
          <Route path="/etablissement/obligations" element={<Navigate to="/etablissement/facturation" replace />} />
          <Route path="/etablissement/equipe" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><EquipeEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/evaluations-a-faire" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><EvaluationsAFaireEtab /></RouteProtegee>} />
          <Route path="/etab/invitation/:token" element={<AccepterInvitationEtab />} />
          <Route path="/etablissement/messagerie" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageMessagerie role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
          <Route path="/etablissement/litiges" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><LitigesEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/reclamations" element={<Navigate to="/etablissement/litiges?tab=reclamations" replace />} />
          <Route path="/etablissement/presences/mission/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailPresencesMission /></RouteProtegee>} />

          {/* Contrat (accessible par soignant et établissement) */}
          <Route path="/contrat/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT', 'ADMIN_ETABLISSEMENT']}><ContratMission /></RouteProtegee>} />
          <Route path="/contrat/:id/certificat" element={<RouteProtegee rolesAutorises={['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME', 'ADMIN_GROUPE']}><CertificatSignaturePage /></RouteProtegee>} />

          {/* Groupe */}
          <Route path="/groupe/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />
          <Route path="/groupe/etablissements" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />

          {/* Admin Plateforme */}
          <Route path="/admin" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDashboard /></RouteProtegee>} />
          <Route path="/admin/utilisateurs" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminUtilisateurs /></RouteProtegee>} />
          <Route path="/admin/utilisateurs/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDetailUtilisateur /></RouteProtegee>} />
          <Route path="/admin/moderation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminModeration /></RouteProtegee>} />
          <Route path="/admin/signalements" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminSignalements /></RouteProtegee>} />
          <Route path="/admin/verification-etablissements" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminVerificationEtablissements /></RouteProtegee>} />
          <Route path="/admin/litiges" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminLitiges /></RouteProtegee>} />
          <Route path="/admin/messages-contact" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminMessagesContact /></RouteProtegee>} />
          <Route path="/admin/templates-contrats" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminTemplatesContrats /></RouteProtegee>} />
          <Route path="/admin/templates-contrats/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminEditerTemplateContrat /></RouteProtegee>} />
          <Route path="/admin/contrats" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminContrats /></RouteProtegee>} />
          <Route path="/admin/contrats/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDetailContrat /></RouteProtegee>} />
          <Route path="/admin/alertes-pointage" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAlertesPointage /></RouteProtegee>} />
          <Route path="/admin/reclamations-score" element={<Navigate to="/admin/reclamations?tab=score" replace />} />
          <Route path="/admin/heures-externes" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminHeuresExternes /></RouteProtegee>} />
          <Route path="/admin/scores" element={<Navigate to="/admin/reclamations?tab=triage" replace />} />
          <Route path="/admin/externalisations-actions" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminExternalisationsActions /></RouteProtegee>} />
          <Route path="/admin/status" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminStatus /></RouteProtegee>} />
          <Route path="/admin/facturation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminFacturation /></RouteProtegee>} />
          <Route path="/admin/impayees" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminImpayees /></RouteProtegee>} />
          <Route path="/admin/conformite" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminConformite /></RouteProtegee>} />
          <Route path="/admin/demo" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDemo /></RouteProtegee>} />
          <Route path="/admin/emails" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminEmails /></RouteProtegee>} />
          <Route path="/admin/api" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAPI /></RouteProtegee>} />
          <Route path="/admin/groupes" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminGroupes /></RouteProtegee>} />
          <Route path="/admin/mandats-facturation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminMandatsFacturation /></RouteProtegee>} />
          <Route path="/admin/bfa" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminBFA /></RouteProtegee>} />
          <Route path="/admin/affacturage" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAffacturage /></RouteProtegee>} />
          <Route path="/admin/chorus-pro" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminChorusPro /></RouteProtegee>} />
          <Route path="/admin/missions" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminMissions /></RouteProtegee>} />
          <Route path="/admin/calendrier" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminCalendrier /></RouteProtegee>} />
          <Route path="/admin/reclamations" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminReclamations /></RouteProtegee>} />
          <Route path="/admin/pool-urgence" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><PoolUrgenceEtablissement isAdmin /></RouteProtegee>} />
          <Route path="/admin/missions/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><DetailMission role="ADMIN_PLATEFORME" /></RouteProtegee>} />
          <Route path="/admin/presences/mission/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><DetailPresencesMission role="ADMIN_PLATEFORME" /></RouteProtegee>} />
          <Route path="/admin/messagerie" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><PageMessagerie role="ADMIN_PLATEFORME" /></RouteProtegee>} />
          <Route path="/admin/finances" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminFinances /></RouteProtegee>} />
          <Route path="/admin/taux-commission" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminTauxCommission /></RouteProtegee>} />
          <Route path="/admin/config" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminConfig /></RouteProtegee>} />
          <Route path="/admin/audit" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAuditLogs /></RouteProtegee>} />
          <Route path="/admin/dpia" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDPIA /></RouteProtegee>} />
          <Route path="/admin/healthcheck" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminHealthcheck /></RouteProtegee>} />
          <Route path="/admin/cohort" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminCohortEconomics /></RouteProtegee>} />
          <Route path="/admin/audit-rls" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAuditRLS /></RouteProtegee>} />
          <Route path="/admin/rgpd-tools" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminRGPDTools /></RouteProtegee>} />
          <Route path="/admin/planning-global" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminPlanningGlobal /></RouteProtegee>} />
          <Route path="/admin/fondateur" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminCockpitFondateur /></RouteProtegee>} />
          <Route path="/admin/fondateur/equipe" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminEquipe /></RouteProtegee>} />
          <Route path="/admin/fondateur/levee" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminLevee /></RouteProtegee>} />
          <Route path="/admin/fondateur/acquisition" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAcquisition /></RouteProtegee>} />
          <Route path="/admin/fondateur/sales" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminSales /></RouteProtegee>} />

          {/* Widget public */}
          <Route path="/widget-recrutement" element={<WidgetRecrutement />} />

          <Route path="*" element={<NotFound />} />
        </Routes>
      </Suspense>
    </PageTransition>
  );
}

const App = () => (
  <ErrorBoundary>
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <AuthProvider>
          <NotificationProvider>
            <BrowserRouter>
              <a href="#main-content" className="skip-to-content">Aller au contenu principal</a>
              <AppRoutes />
              <Toaster
                position="top-center"
                richColors
                closeButton
                offset={16}
                toastOptions={{
                  style: {
                    marginTop: 'calc(env(safe-area-inset-top, 0px) + 3.75rem)',
                  },
                }}
              />
              <BandeauCookies />
            </BrowserRouter>
          </NotificationProvider>
        </AuthProvider>
      </TooltipProvider>
    </QueryClientProvider>
  </ErrorBoundary>
);

export default App;
