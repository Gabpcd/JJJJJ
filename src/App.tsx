import React, { lazy, Suspense } from 'react';
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/contexts/AuthContext";
import { NotificationProvider } from "@/contexts/NotificationContext";
import { RouteProtegee } from "@/components/RouteProtegee";
import { PageTransition } from "@/components/PageTransition";
import { ChargementPage } from "@/components/ChargementPage";
import { ScrollToTop } from "@/components/ScrollToTop";
import { Toaster } from "sonner";

/* ─── Public pages ─── */
const PageAccueil = lazy(() => import("./pages/PageAccueil"));
const PageConnexion = lazy(() => import("./pages/PageConnexion"));
const ConfirmerEmail = lazy(() => import("./pages/ConfirmerEmail"));
const InscriptionSoignant = lazy(() => import("./pages/InscriptionSoignant"));
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
const NotFound = lazy(() => import("./pages/NotFound"));
const WidgetRecrutement = lazy(() => import("./pages/WidgetRecrutement"));
const Telecharger = lazy(() => import("./pages/Telecharger"));

/* ─── Soignant pages ─── */
const DashboardSoignant = lazy(() => import("./pages/DashboardSoignant"));
const ProfilSoignant = lazy(() => import("./pages/ProfilSoignant"));
const ProfilSoignantEtablissement = lazy(() => import("./pages/ProfilSoignantEtablissement"));
const MissionsSoignant = lazy(() => import("./pages/MissionsSoignant"));
const RechercheMissions = lazy(() => import("./pages/RechercheMissions"));
const DetailMissionSoignant = lazy(() => import("./pages/DetailMissionSoignant"));
const DetailSerieSoignant = lazy(() => import("./pages/DetailSerieSoignant"));
const DocumentsSoignant = lazy(() => import("./pages/DocumentsSoignant"));
const PlanningSoignant = lazy(() => import("./pages/PlanningSoignant"));
const ConformiteSoignant = lazy(() => import("./pages/ConformiteSoignant"));
const PresencesSoignant = lazy(() => import("./pages/PresencesSoignant"));
const MesGains = lazy(() => import("./pages/MesGains"));
const HistoriqueMissions = lazy(() => import("./pages/HistoriqueMissions"));
const FiabiliteSoignant = lazy(() => import("./pages/FiabiliteSoignant"));
const Parcours3200h = lazy(() => import("./pages/Parcours3200h"));
const PrevoyanceSoignant = lazy(() => import("./pages/PrevoyanceSoignant"));
const AttestationHeures = lazy(() => import("./pages/AttestationHeures"));
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
const APIEtablissement = lazy(() => import("./pages/APIEtablissement"));
const ProfilEtablissement = lazy(() => import("./pages/ProfilEtablissement"));
const ListeMissions = lazy(() => import("./pages/ListeMissions"));
const CreerMission = lazy(() => import("./pages/CreerMission"));
const DetailMission = lazy(() => import("./pages/DetailMission"));
const ModifierMission = lazy(() => import("./pages/ModifierMission"));
const PresencesEtablissement = lazy(() => import("./pages/PresencesEtablissement"));
const FacturationEtablissement = lazy(() => import("./pages/FacturationEtablissement"));
const DetailFacture = lazy(() => import("./pages/DetailFacture"));
const ExportPaie = lazy(() => import("./pages/ExportPaie"));
const DashboardRH = lazy(() => import("./pages/DashboardRH"));
const MonGroupe = lazy(() => import("./pages/MonGroupe"));
const ExclusionsEtablissement = lazy(() => import("./pages/ExclusionsEtablissement"));
const PremiumEtablissement = lazy(() => import("./pages/PremiumEtablissement"));
const ChorusConfig = lazy(() => import("./pages/ChorusConfig"));
const PoolUrgenceEtablissement = lazy(() => import("./pages/PoolUrgenceEtablissement"));
const ContratPlateforme = lazy(() => import("./pages/ContratPlateforme"));
const DetailPresencesMission = lazy(() => import("./pages/DetailPresencesMission"));
const ObligationsFinancieres = lazy(() => import("./pages/ObligationsFinancieres"));

/* ─── Shared protected ─── */
const ContratMission = lazy(() => import("./pages/ContratMission"));
const ListeContrats = lazy(() => import("./pages/ListeContrats"));
const PageNotifications = lazy(() => import("./pages/PageNotifications"));
const DashboardGroupe = lazy(() => import("./pages/DashboardGroupe"));

/* ─── Admin pages ─── */
const AdminDashboard = lazy(() => import("./pages/admin/AdminDashboard"));
const AdminUtilisateurs = lazy(() => import("./pages/admin/AdminUtilisateurs"));
const AdminModeration = lazy(() => import("./pages/admin/AdminModeration"));
const AdminFacturation = lazy(() => import("./pages/admin/AdminFacturation"));
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
          <Route path="/confirmer-email" element={<ConfirmerEmail />} />
          <Route path="/inscription/soignant" element={<InscriptionSoignant />} />
          <Route path="/inscription/etablissement" element={<InscriptionEtablissement />} />

          {/* Pages légales — publiques */}
          <Route path="/cgu" element={<PageCGU />} />
          <Route path="/cgv" element={<PageCGV />} />
          <Route path="/confidentialite" element={<PageConfidentialite />} />
          <Route path="/politique-confidentialite" element={<PageConfidentialite />} />
          <Route path="/mentions-legales" element={<PageMentionsLegales />} />

          {/* Soignant */}
          <Route path="/soignant/tableau-de-bord" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DashboardSoignant /></RouteProtegee>} />
          <Route path="/soignant/profil" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ProfilSoignant /></RouteProtegee>} />
          <Route path="/soignant/missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MissionsSoignant /></RouteProtegee>} />
          <Route path="/soignant/recherche-missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><RechercheMissions /></RouteProtegee>} />
          <Route path="/soignant/missions/serie/:serieId" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailSerieSoignant /></RouteProtegee>} />
          <Route path="/soignant/missions/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailMissionSoignant /></RouteProtegee>} />
          <Route path="/soignant/documents" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DocumentsSoignant /></RouteProtegee>} />
          <Route path="/soignant/planning" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PlanningSoignant /></RouteProtegee>} />
          <Route path="/soignant/conformite" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ConformiteSoignant /></RouteProtegee>} />
          <Route path="/soignant/presences" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PresencesSoignant /></RouteProtegee>} />
          <Route path="/soignant/presences/mission/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DetailPresencesMission role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/mes-gains" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesGains /></RouteProtegee>} />
          <Route path="/soignant/historique-missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><HistoriqueMissions /></RouteProtegee>} />
          <Route path="/soignant/fiabilite" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><FiabiliteSoignant /></RouteProtegee>} />
          <Route path="/soignant/parcours-3200h" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><Parcours3200h /></RouteProtegee>} />
          <Route path="/soignant/prevoyance" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PrevoyanceSoignant /></RouteProtegee>} />
          <Route path="/soignant/attestation-heures" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><AttestationHeures /></RouteProtegee>} />
          <Route path="/soignant/passer-en-liberal" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PasserEnLiberal /></RouteProtegee>} />
          <Route path="/soignant/exclusions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ExclusionsSoignant /></RouteProtegee>} />
          <Route path="/soignant/contrats" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ListeContrats role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/premium" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PremiumSoignant /></RouteProtegee>} />
          <Route path="/soignant/charges" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ChargesSociales /></RouteProtegee>} />
          <Route path="/soignant/notifications" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageNotifications role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/parrainage" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageParrainage /></RouteProtegee>} />
          <Route path="/soignant/messagerie" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageMessagerie role="SOIGNANT" /></RouteProtegee>} />
          <Route path="/soignant/litiges" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><LitigesSoignant /></RouteProtegee>} />
          <Route path="/soignant/stripe-connect" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageStripeConnect /></RouteProtegee>} />

          {/* Établissement */}
          <Route path="/etablissement/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/profil" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ProfilEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/soignants/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ProfilSoignantEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/missions" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ListeMissions /></RouteProtegee>} />
          <Route path="/etablissement/missions/creer" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><CreerMission /></RouteProtegee>} />
          <Route path="/etablissement/missions/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailMission /></RouteProtegee>} />
          <Route path="/etablissement/missions/:id/modifier" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ModifierMission /></RouteProtegee>} />
          <Route path="/etablissement/presences" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PresencesEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/contrats" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ListeContrats role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
          <Route path="/etablissement/facturation" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><FacturationEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/facturation/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailFacture /></RouteProtegee>} />
          <Route path="/etablissement/export-paie" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ExportPaie /></RouteProtegee>} />
          <Route path="/etablissement/rh" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardRH /></RouteProtegee>} />
          <Route path="/etablissement/mon-groupe" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><MonGroupe /></RouteProtegee>} />
          <Route path="/etablissement/notifications" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageNotifications role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
          <Route path="/etablissement/exclusions" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ExclusionsEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/api" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><APIEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/premium" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PremiumEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/chorus-config" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ChorusConfig /></RouteProtegee>} />
          <Route path="/etablissement/pool-urgence" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PoolUrgenceEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/soignants" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PoolUrgenceEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/pool-soignants" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PoolUrgenceEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/dashboard" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/contrat-plateforme" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ContratPlateforme /></RouteProtegee>} />
          <Route path="/etablissement/messagerie" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageMessagerie role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
          <Route path="/etablissement/litiges" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><LitigesEtablissement /></RouteProtegee>} />
          <Route path="/etablissement/presences/mission/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailPresencesMission /></RouteProtegee>} />

          {/* Contrat (accessible par soignant et établissement) */}
          <Route path="/contrat/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT', 'ADMIN_ETABLISSEMENT']}><ContratMission /></RouteProtegee>} />

          {/* Groupe */}
          <Route path="/groupe/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />
          <Route path="/groupe/etablissements" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />

          {/* Admin Plateforme */}
          <Route path="/admin" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDashboard /></RouteProtegee>} />
          <Route path="/admin/utilisateurs" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminUtilisateurs /></RouteProtegee>} />
          <Route path="/admin/utilisateurs/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDetailUtilisateur /></RouteProtegee>} />
          <Route path="/admin/moderation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminModeration /></RouteProtegee>} />
          <Route path="/admin/facturation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminFacturation /></RouteProtegee>} />
          <Route path="/admin/conformite" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminConformite /></RouteProtegee>} />
          <Route path="/admin/demo" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDemo /></RouteProtegee>} />
          <Route path="/admin/emails" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminEmails /></RouteProtegee>} />
          <Route path="/admin/api" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminAPI /></RouteProtegee>} />
          <Route path="/admin/groupes" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminGroupes /></RouteProtegee>} />
          <Route path="/admin/missions" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminMissions /></RouteProtegee>} />
          <Route path="/admin/calendrier" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminCalendrier /></RouteProtegee>} />
          <Route path="/admin/reclamations" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminReclamations /></RouteProtegee>} />
          <Route path="/admin/pool-urgence" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><PoolUrgenceEtablissement isAdmin /></RouteProtegee>} />
          <Route path="/admin/missions/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><DetailMission role="ADMIN_PLATEFORME" /></RouteProtegee>} />
          <Route path="/admin/presences/mission/:id" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><DetailPresencesMission role="ADMIN_PLATEFORME" /></RouteProtegee>} />
          <Route path="/admin/messagerie" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><PageMessagerie role="ADMIN_PLATEFORME" /></RouteProtegee>} />
          <Route path="/admin/finances" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminFinances /></RouteProtegee>} />

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
              <AppRoutes />
              <Toaster position="top-right" richColors closeButton />
            </BrowserRouter>
          </NotificationProvider>
        </AuthProvider>
      </TooltipProvider>
    </QueryClientProvider>
  </ErrorBoundary>
);

export default App;
