import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/contexts/AuthContext";
import { NotificationProvider } from "@/contexts/NotificationContext";
import { RouteProtegee } from "@/components/RouteProtegee";
import PageAccueil from "./pages/PageAccueil";
import PageConnexion from "./pages/PageConnexion";
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
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <AuthProvider>
        <NotificationProvider>
          <BrowserRouter>
            <Routes>
              <Route path="/" element={<PageAccueil />} />
              <Route path="/connexion" element={<PageConnexion />} />
              <Route path="/inscription/soignant" element={<InscriptionSoignant />} />
              <Route path="/inscription/etablissement" element={<InscriptionEtablissement />} />

              <Route path="/soignant/tableau-de-bord" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><DashboardSoignant /></RouteProtegee>} />
              <Route path="/soignant/profil" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><ProfilSoignant /></RouteProtegee>} />
              <Route path="/soignant/missions" element={<RouteProtegee rolesAutorises={['SOIGNANT']}><MissionsSoignant /></RouteProtegee>} />
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

              <Route path="/etablissement/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><DashboardEtablissement /></RouteProtegee>} />
              <Route path="/etablissement/profil" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><ProfilEtablissement /></RouteProtegee>} />
              <Route path="/etablissement/missions" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><ListeMissions /></RouteProtegee>} />
              <Route path="/etablissement/missions/creer" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><CreerMission /></RouteProtegee>} />
              <Route path="/etablissement/missions/:id" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><DetailMission /></RouteProtegee>} />
              <Route path="/etablissement/missions/:id/modifier" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><ModifierMission /></RouteProtegee>} />
              <Route path="/etablissement/presences" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><PresencesEtablissement /></RouteProtegee>} />
              <Route path="/etablissement/mon-groupe" element={<RouteProtegee rolesAutorises={['ETABLISSEMENT']}><MonGroupe /></RouteProtegee>} />

              <Route path="/groupe/tableau-de-bord" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />
              <Route path="/groupe/etablissements" element={<RouteProtegee rolesAutorises={['ADMIN_GROUPE']}><DashboardGroupe /></RouteProtegee>} />

              <Route path="*" element={<NotFound />} />
            </Routes>
          </BrowserRouter>
        </NotificationProvider>
      </AuthProvider>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
