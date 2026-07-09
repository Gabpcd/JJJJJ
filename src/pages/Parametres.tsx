import { useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { User, Building2, Bell, Ban } from 'lucide-react';
import { ProfilEtablissementContent } from './ProfilEtablissement';
import { MonGroupeContent } from './MonGroupe';
import { NotificationsContent } from './PageNotifications';
import { APIContent } from './APIEtablissement';
import { ExclusionsContent } from './ExclusionsEtablissement';
import { TolerancePointageGps } from '@/components/etablissement/TolerancePointageGps';

const TABS = ['profil', 'groupe', 'config', 'exclusions'] as const;
type Tab = typeof TABS[number];

export default function Parametres() {
  usePageTitle('Paramètres');
  const [searchParams, setSearchParams] = useSearchParams();
  const tabParam = searchParams.get('tab');
  const currentTab: Tab = TABS.includes(tabParam as Tab) ? (tabParam as Tab) : 'profil';

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <Tabs
        value={currentTab}
        onValueChange={(v) => setSearchParams({ tab: v }, { replace: true })}
        className="w-full"
      >
        <div className="overflow-x-auto -mx-1 px-1 mb-6">
        <TabsList className="w-max">
          <TabsTrigger value="profil" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <User className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Profil</span>
          </TabsTrigger>
          <TabsTrigger value="groupe" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <Building2 className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Groupe</span>
          </TabsTrigger>
          <TabsTrigger value="config" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <Bell className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Config</span>
          </TabsTrigger>
          <TabsTrigger value="exclusions" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <Ban className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Exclusions</span>
          </TabsTrigger>
        </TabsList>
        </div>

        <TabsContent value="profil" className="mt-0">
          <ProfilEtablissementContent />
        </TabsContent>

        <TabsContent value="groupe" className="mt-0">
          <MonGroupeContent />
        </TabsContent>

        <TabsContent value="config" className="mt-0 space-y-8">
          <TolerancePointageGps />
          <NotificationsContent />
          <APIContent />
        </TabsContent>

        <TabsContent value="exclusions" className="mt-0">
          <ExclusionsContent />
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}
