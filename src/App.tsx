import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/contexts/AuthContext";
import { NotificationProvider } from "@/contexts/NotificationContext";
import { RouteProtegee } from "@/components/RouteProtegee";

import PageAccueil from "./pages/PageAccueil";
import PageConnexion from "./pages/PageConnexion";
import ConfirmerEmail from "./pages/ConfirmerEmail";
import InscriptionSoignant from "./pages/InscriptionSoignant";
import InscriptionEtablissement from "./pages/InscriptionEtablissement";
import DashboardSoignant from "./pages/DashboardSoignant";
import DashboardEtablissement from "./pages/DashboardEtablissement";
import DashboardGroupe from "./pages/DashboardGroupe";
import ProfilSoignant from "./pages/ProfilSoignant";
import ProfilEtablissement from "./pages/ProfilEtablissement";
import CreerMission from "./pages/CreerMission";
import ListeMissions from "./pages/ListeMissions";
import DetailMission from "./pages/DetailMission";
import ModifierMission from "./pages/ModifierMission";
import MonGroupe from "./pages/MonGroupe";
import MissionsSoignant from "./pages/MissionsSoignant";
import DetailMissionSoignant from "./pages/DetailMissionSoignant";
import DetailSerieSoignant from "./pages/DetailSerieSoignant";
import DocumentsSoignant from "./pages/DocumentsSoignant";
import PlanningSoignant from "./pages/PlanningSoignant";
import ConformiteSoignant from "./pages/ConformiteSoignant";
import PresencesSoignant from "./pages/PresencesSoignant";
import PresencesEtablissement from "./pages/PresencesEtablissement";
import MesGains from "./pages/MesGains";
import FiabiliteSoignant from "./pages/FiabiliteSoignant";
import Parcours3200h from "./pages/Parcours3200h";
import PrevoyanceSoignant from "./pages/PrevoyanceSoignant";
import AttestationHeures from "./pages/AttestationHeures";
import Tarifs from "./pages/Tarifs";
import FacturationEtablissement from "./pages/FacturationEtablissement";
import DetailFacture from "./pages/DetailFacture";
import PasserEnLiberal from "./pages/PasserEnLiberal";
import ExclusionsSoignant from "./pages/ExclusionsSoignant";
import ExclusionsEtablissement from "./pages/ExclusionsEtablissement";
import ExportPaie from "./pages/ExportPaie";
import ContratMission from "./pages/ContratMission";
import ListeContrats from "./pages/ListeContrats";
import PageNotifications from "./pages/PageNotifications";
import PageCGU from "./pages/PageCGU";
import PageCGV from "./pages/PageCGV";
import PageConfidentialite from "./pages/PageConfidentialite";
import PageMentionsLegales from "./pages/PageMentionsLegales";
import NotFound from "./pages/NotFound";
import AdminDashboard from "./pages/admin/AdminDashboard";
import AdminUtilisateurs from "./pages/admin/AdminUtilisateurs";
import AdminModeration from "./pages/admin/AdminModeration";
import AdminFacturation from "./pages/admin/AdminFacturation";
import AdminConformite from "./pages/admin/AdminConformite";
import RechercheMissions from "./pages/RechercheMissions";
import PremiumSoignant from "./pages/PremiumSoignant";
import PremiumEtablissement from "./pages/PremiumEtablissement";
import WidgetRecrutement from "./pages/WidgetRecrutement";

const queryClient = new QueryClient();

const App = () => (
  <ErrorBoundary>
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <AuthProvider>
          <NotificationProvider>
            <BrowserRouter>
              <Routes>
                <Route path="/" element={<PageAccueil />} />
                <Route path="/tarifs" element={<Tarifs />} />
                <Route path="/connexion" element={<PageConnexion />} />
                <Route path="/confirmer-email" element={<ConfirmerEmail />} />
                <Route path="/inscription/soignant" element={<InscriptionSoignant />} />
                <Route path="/inscription/etablissement" element={<InscriptionEtablissement />} />

                {/* Pages légales — publiques */}
                <Route path="/cgu" element={<PageCGU />} />
                <Route path="/cgv" element={<PageCGV />} />
                <Route path="/confidentialite" element={<PageConfidentialite />} />
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
                <Route path="/soignant/mes-gains" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MesGains /></RouteProtegee>} />
                <Route path="/soignant/fiabilite" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><FiabiliteSoignant /></RouteProtegee>} />
                <Route path="/soignant/parcours-3200h" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><Parcours3200h /></RouteProtegee>} />
                <Route path="/soignant/prevoyance" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PrevoyanceSoignant /></RouteProtegee>} />
                <Route path="/soignant/attestation-heures" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><AttestationHeures /></RouteProtegee>} />
                <Route path="/soignant/passer-en-liberal" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PasserEnLiberal /></RouteProtegee>} />
                <Route path="/soignant/exclusions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ExclusionsSoignant /></RouteProtegee>} />
                <Route path="/soignant/contrats" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ListeContrats role="SOIGNANT" /></RouteProtegee>} />
                <Route path="/soignant/premium" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PremiumSoignant /></RouteProtegee>} />
                <Route path="/soignant/notifications" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><PageNotifications role="SOIGNANT" /></RouteProtegee>} />

                {/* Établissement */}
                <Route path="/etablissement/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
                <Route path="/etablissement/profil" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ProfilEtablissement /></RouteProtegee>} />
                <Route path="/etablissement/missions" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ListeMissions /></RouteProtegee>} />
                <Route path="/etablissement/missions/creer" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><CreerMission /></RouteProtegee>} />
                <Route path="/etablissement/missions/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailMission /></RouteProtegee>} />
                <Route path="/etablissement/missions/:id/modifier" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ModifierMission /></RouteProtegee>} />
                <Route path="/etablissement/presences" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PresencesEtablissement /></RouteProtegee>} />
                <Route path="/etablissement/contrats" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ListeContrats role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
                <Route path="/etablissement/facturation" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><FacturationEtablissement /></RouteProtegee>} />
                <Route path="/etablissement/facturation/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><DetailFacture /></RouteProtegee>} />
                <Route path="/etablissement/export-paie" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ExportPaie /></RouteProtegee>} />
                <Route path="/etablissement/mon-groupe" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><MonGroupe /></RouteProtegee>} />
                <Route path="/etablissement/notifications" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PageNotifications role="ADMIN_ETABLISSEMENT" /></RouteProtegee>} />
                <Route path="/etablissement/exclusions" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><ExclusionsEtablissement /></RouteProtegee>} />
                <Route path="/etablissement/premium" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><PremiumEtablissement /></RouteProtegee>} />

                {/* Contrat (accessible par soignant et établissement) */}
                <Route path="/contrat/:id" element={<RouteProtegee rolesAutorises={['SOIGNANT', 'ADMIN_ETABLISSEMENT']}><ContratMission /></RouteProtegee>} />

                {/* Groupe */}
                <Route path="/groupe/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />
                <Route path="/groupe/etablissements" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />

                {/* Admin Plateforme */}
                <Route path="/admin" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminDashboard /></RouteProtegee>} />
                <Route path="/admin/utilisateurs" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminUtilisateurs /></RouteProtegee>} />
                <Route path="/admin/moderation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminModeration /></RouteProtegee>} />
                <Route path="/admin/facturation" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminFacturation /></RouteProtegee>} />
                <Route path="/admin/conformite" element={<RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}><AdminConformite /></RouteProtegee>} />

                {/* Widget public */}
                <Route path="/widget-recrutement" element={<WidgetRecrutement />} />

                <Route path="*" element={<NotFound />} />
              </Routes>
              <BandeauCookies />
            </BrowserRouter>
          </NotificationProvider>
        </AuthProvider>
      </TooltipProvider>
    </QueryClientProvider>
  </ErrorBoundary>
);

export default App;
