import { useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Scale, MessageSquare } from 'lucide-react';
import { LitigesSoignantContent } from './LitigesSoignant';
import { ReclamationsContent } from './MesReclamations';

const TABS = ['litiges', 'reclamations'] as const;
type Tab = typeof TABS[number];

export default function LitigesContestationsSoignant() {
  usePageTitle('Litiges & contestations');
  const [searchParams, setSearchParams] = useSearchParams();
  const tabParam = searchParams.get('tab');
  const currentTab: Tab = TABS.includes(tabParam as Tab) ? (tabParam as Tab) : 'litiges';

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-4">Litiges & contestations</h1>

      <Tabs
        value={currentTab}
        onValueChange={(v) => setSearchParams({ tab: v }, { replace: true })}
      >
        <TabsList className="grid w-full grid-cols-2 mb-4">
          <TabsTrigger value="litiges" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <Scale className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Litiges mission</span>
          </TabsTrigger>
          <TabsTrigger value="reclamations" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <MessageSquare className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Réclamations</span>
          </TabsTrigger>
        </TabsList>

        <TabsContent value="litiges" className="mt-0">
          <LitigesSoignantContent />
        </TabsContent>

        <TabsContent value="reclamations" className="mt-0">
          <ReclamationsContent role="SOIGNANT" />
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}
