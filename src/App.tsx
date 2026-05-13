import React, { lazy, Suspense } from 'react';
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
import { Toaster } from "sonner";
import { BandeauCookies } from "@/components/BandeauCookies";

/* ─── Public pages ─── */
const PageAccueil = lazy(() => import("./pages/PageAccueil"));
const PageConnexion = lazy(() => import("./pages/PageConnexion"));
const PageResetPassword = lazy(() => import("./pages/PageResetPassword"));
const PscCallback = lazy(() => import("./pages/PscCallback"));
const MandatFacturation = lazy(() => import("./pages/MandatFacturation"));
const FinaliserInscriptionEtab = lazy(() => import("./pages/FinaliserInscriptionEtab"));
const MesFacturesHonoraires = lazy(() => import("./pages/MesFacturesHonoraires"));
const MesAvances = lazy(() => import("./pages/MesAvances"));
const BulletinsPaie = lazy(() => import("./pages/BulletinsPaie"));
const AdminMandatsFacturation = lazy(() => import("./pages/admin/AdminMandatsFacturation"));
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
const PharmacieRemplacement = lazy(() => import("./pages/PharmacieRemplacement"));
const BlogListe = lazy(() => import("./pages/BlogListe"));
const BlogArticle = lazy(() => import("./pages/BlogArticle"));
const APropos = lazy(() => import("./pages/APropos"));
const PageCGU = lazy(() => import("./pages/PageCGU"));
const PageCGV = lazy(() => import("./pages/PageCGV"));
const PageConfidentialite = lazy(() => import("./pages/PageConfidentialite"));
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
const ProfilSoignant = lazy(() => import("./pages/ProfilSoignant"));
const ProfilSoignantEtablissement = lazy(() => import("./pages/ProfilSoignantEtablissement"));
const RechercheSoignantsEtab = lazy(() => import("./pages/RechercheSoignantsEtab"));
const MissionsSoignant = lazy(() => import("./pages/MissionsSoignant"));
const RechercheMissions = lazy(() => import("./pages/RechercheMissions"));
const DetailMissionSoignant = lazy(() => import("./pages/DetailMissionSoignant"));
const DetailSerieSoignant = lazy(() => import("./pages/DetailSerieSoignant"));
const DocumentsSoignant = lazy(() => import("./pages/DocumentsSoignant"));
const PlanningSoignant = lazy(() => import("./pages/PlanningSoignant"));
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
const MesDPAE = lazy(() => import("./pages/MesDPAE"));
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
const ListeMissions = lazy(() => import("./pages/ListeMissions"));
const CreerMission = lazy(() => import("./pages/CreerMission"));
const DetailMission = lazy(() => import("./pages/DetailMission"));
const ModifierMission = lazy(() => import("./pages/ModifierMission"));
const PresencesEtablissement = lazy(() => import("./pages/PresencesEtablissement"));
const FacturationEtablissement = lazy(() => import("./pages/FacturationEtablissement"));
const AnalyticsEtablissement = lazy(() => import("./pages/AnalyticsEtablissement"));
const GestionShifts = lazy(() => import("./pages/GestionShifts"));
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
const ObligationsFinancieresEtab = lazy(() => import("./pages/ObligationsFinancieresEtab"));
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
const AdminLitiges = lazy(() => import("./pages/admin/AdminLitiges"));
const AdminTemplatesContrats = lazy(() => import("./pages/admin/AdminTemplatesContrats"));
const AdminEditerTemplateContrat = lazy(() => import("./pages/admin/AdminEditerTemplateContrat"));
const AdminContrats = lazy(() => import("./pages/admin/AdminContrats"));
const AdminDetailContrat = lazy(() => import("./pages/admin/AdminDetailContrat"));
const AdminAlertesPointage = lazy(() => import("./pages/admin/AdminAlertesPointage"));
const AdminReclamationsScore = lazy(() => import("./pages/admin/AdminReclamationsScore"));
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
const AdminAuditLogs = lazy(() => import("./pages/admin/AdminAuditLogs"));
const AdminDPIA = lazy(() => import("./pages/admin/AdminDPIA"));
const AdminHealthcheck = lazy(() => import("./pages/admin/AdminHealthcheck"));
const AdminCohortEconomics = lazy(() => import("./pages/admin/AdminCohortEconomics"));
const AdminRGPDTools = lazy(() => import("./pages/admin/AdminRGPDTools"));

const queryClient = new QueryClient();

function AppRoutes() {
  return (
    <PageTransition>
      <ScrollToTop />
      <Suspense fallback={<ChargementPage />}>
        <Routes>
          <Route path="/" element={<PageAccueil />} />
          <Route path="/tarifs" element={<Tarifs />} />
          <Route path="/devenir-soignant" element={<DevenirSoignant />} />
          <Route path="/recruter-soignants" element={<RecruterSoignants />} />
          <Route path="/infirmiere-liberale" element={<InfirmiereLiberal />} />
          <Route path="/pharmacie-remplacement" element={<PharmacieRemplacement />} />
          <Route path="/blog" element={<BlogListe />} />
          <Route path="/blog/:slug" element={<BlogArticle />} />
          <Route path="/a-propos" element={<APropos />} />
          <Route path="/telecharger" element={<Telecharger />} />
          <Route path="/connexion" element={<PageConnexion />} />
          <Route path="/reset-password" element={<PageResetPassword />} />
          <Route path="/auth/psc/callback" element={<PscCallback />} />
          <Route path="/confirmer-email" element={<ConfirmerEmail />} />
          <Route path="/inscription/soignant" element={<InscriptionSoignant />} />
          <Route path="/inscription/soignant/completion" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><InscriptionSoignantCompletion /></RouteProtegee>} />
          <Route path="/inscription/etablissement" element={<InscriptionEtablissement />} />
          <Route path="/inscription/succes" element={<PageInscriptionSucces />} />

          {/* Pages légales — publiques */}
          <Route path="/cgu" element={<PageCGU />} />
          <Route path="/cgv" element={<PageCGV />} />
          <Route path="/confidentialite" element={<PageConfidentialite />} />
          <Route path="/politique-confidentialite" element={<PageConfidentialite />} />
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
          <Route path="/soignant/missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MissionsSoignant /></RouteProtegee>} />
          <Route path="/soignant/recherche-missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><RechercheMissions /></RouteProtegee>} />
          <Route path="/soignant/missions/serie/:serieId" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailSerieSoignant /></RouteProtegee>} />
          <Route path="/soignant/missions/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailMissionSoignant /></RouteProtegee>} />
          <Route path="/soignant/mes-documents" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesDocuments /></RouteProtegee>} />
          <Route path="/soignant/documents" element={<Navigate to="/soignant/mes-documents?tab=justificatifs" replace />} />
          <Route path="/soignant/planning" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PlanningSoignant /></RouteProtegee>} />
          <Route path="/soignant/calendrier-sync" element={<Navigate to="/soignant/planning" replace />} />
          <Route path="/soignant/conformite" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ConformiteSoignant /></RouteProtegee>} />
          <Route path="/soignant/presences" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PresencesSoignant /></RouteProtegee>} />
          <Route path="/soignant/presences/mission/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailPresencesMission role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/mes-gains" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesGains /></RouteProtegee>} />
          <Route path="/soignant/mandat-facturation" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MandatFacturation /></RouteProtegee>} />
          <Route path="/soignant/mes-factures-honoraires" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesFacturesHonoraires /></RouteProtegee>} />
          <Route path="/soignant/mes-avances" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesAvances /></RouteProtegee>} />
          <Route path="/soignant/bulletins-paie" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><BulletinsPaie /></RouteProtegee>} />
          <Route path="/soignant/historique-missions" element={<Navigate to="/soignant/planning?tab=historique" replace />} />
          <Route path="/soignant/fiabilite" element={<Navigate to="/soignant/score" replace />} />
          <Route path="/soignant/score" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageScoreSoignant /></RouteProtegee>} />
          <Route path="/soignant/evaluations" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><EvaluationsSoignant /></RouteProtegee>} />
          <Route path="/etablissement/score" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageScoreEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/mes-reclamations" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><MesReclamationsEtab /></RouteProtegee>} />
          <Route path="/soignant/fiabilite-legacy" element={<Navigate to="/soignant/score" replace />} />
          <Route path="/soignant/parcours-3200h" element={<Navigate to="/soignant/passer-en-liberal" replace />} />
          <Route path="/soignant/prevoyance" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PrevoyanceSoignant /></RouteProtegee>} />
          <Route path="/soignant/attestation-heures" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><AttestationHeures /></RouteProtegee>} />
          <Route path="/soignant/dpae" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesDPAE /></RouteProtegee>} />
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

          {/* Établissement */}
          <Route path="/etablissement/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/finaliser-inscription" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><FinaliserInscriptionEtab /></RouteProtegee>} />
          <Route path="/soignant/parametres" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageParametresSoignant /></RouteProtegee>} />
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
          <Route path="/etablissement/shifts" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><GestionShifts /></RouteProtegee>} />
          <Route path="/etablissement/assurance" element={<Navigate to="/etablissement/parametres?tab=contrats" replace />} />
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
          <Route path="/etablissement/dashboard" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/contrat-plateforme" element={<Navigate to="/etablissement/parametres?tab=contrats" replace />} />
          <Route path="/etablissement/obligations" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ObligationsFinancieresEtab /></RouteProtegee>} />
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
          <Route path="/admin/litiges" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminLitiges /></RouteProtegee>} />
          <Route path="/admin/templates-contrats" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminTemplatesContrats /></RouteProtegee>} />
          <Route path="/admin/templates-contrats/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminEditerTemplateContrat /></RouteProtegee>} />
          <Route path="/admin/contrats" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminContrats /></RouteProtegee>} />
          <Route path="/admin/contrats/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDetailContrat /></RouteProtegee>} />
          <Route path="/admin/alertes-pointage" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAlertesPointage /></RouteProtegee>} />
          <Route path="/admin/reclamations-score" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminReclamationsScore /></RouteProtegee>} />
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
          <Route path="/admin/audit" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAuditLogs /></RouteProtegee>} />
          <Route path="/admin/dpia" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDPIA /></RouteProtegee>} />
          <Route path="/admin/healthcheck" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminHealthcheck /></RouteProtegee>} />
          <Route path="/admin/cohort" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminCohortEconomics /></RouteProtegee>} />
          <Route path="/admin/rgpd-tools" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminRGPDTools /></RouteProtegee>} />

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
