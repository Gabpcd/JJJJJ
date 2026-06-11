import { useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { FileText, FolderOpen, FileCheck2 } from 'lucide-react';
import { ListeContratsContent } from './ListeContrats';
import { DocumentsSoignantContent } from './DocumentsSoignant';
import { MesDPAEContent } from './MesDPAE';

/* Session B : centre documents unique — justificatifs, contrats signés et DPAE
   au même endroit (l'ancienne page /soignant/dpae redirige vers ?tab=dpae). */
const TABS = ['contrats', 'justificatifs', 'dpae'] as const;
type Tab = typeof TABS[number];

export default function MesDocuments() {
  usePageTitle('Documents');
  const [searchParams, setSearchParams] = useSearchParams();
  const tabParam = searchParams.get('tab');
  // Défaut 'justificatifs' : l'onglet upload documents est le plus utile en
  // onboarding (la majorité des CTA pointe vers `/soignant/documents` qui
  // redirige déjà avec `?tab=justificatifs`, on aligne le défaut quand aucun
  // param n'est passé).
  const currentTab: Tab = TABS.includes(tabParam as Tab) ? (tabParam as Tab) : 'justificatifs';

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-4">Mes documents</h1>

      <Tabs
        value={currentTab}
        onValueChange={(v) => setSearchParams({ tab: v }, { replace: true })}
      >
        <TabsList className="grid w-full grid-cols-3 mb-4">
          <TabsTrigger value="justificatifs" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <FolderOpen className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Justificatifs</span>
          </TabsTrigger>
          <TabsTrigger value="contrats" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <FileText className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Contrats</span>
          </TabsTrigger>
          <TabsTrigger value="dpae" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <FileCheck2 className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>DPAE</span>
          </TabsTrigger>
        </TabsList>

        <TabsContent value="justificatifs" className="mt-0">
          <DocumentsSoignantContent />
        </TabsContent>

        <TabsContent value="contrats" className="mt-0">
          <ListeContratsContent role="SOIGNANT" />
        </TabsContent>

        <TabsContent value="dpae" className="mt-0">
          <MesDPAEContent />
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}
