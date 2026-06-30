import { useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { ShieldCheck, Star, Scale, MessageSquare } from 'lucide-react';
import { ScoreContent } from './PageScoreSoignant';
import { EvaluationsContent } from './EvaluationsSoignant';
import { LitigesSoignantContent } from './LitigesSoignant';
import { ReclamationsContent } from './MesReclamations';

/**
 * Hub « Ma réputation » (Session nav — regroupement fort). Une seule page à
 * onglets : Score · Évaluations · Litiges · Réclamations.
 *
 * Dégonflage réputation (refonte UX) : le « Classement » (mise en concurrence
 * des soignants — hors-sujet dans le soin) et la « Conformité » (vocabulaire de
 * surveillance, sans valeur pour le soignant) ont été retirés de la nav. Les
 * routes autonomes restent pour d'éventuels liens profonds.
 * Deep-link possible via ?tab=score|evaluations|litiges|reclamations.
 */
const ONGLETS = [
  { valeur: 'score', label: 'Score', icone: ShieldCheck },
  { valeur: 'evaluations', label: 'Évaluations', icone: Star },
  { valeur: 'litiges', label: 'Litiges', icone: Scale },
  { valeur: 'reclamations', label: 'Réclamations', icone: MessageSquare },
] as const;

export default function ReputationSoignant() {
  usePageTitle('Ma réputation');
  const [params, setParams] = useSearchParams();
  const tabParam = params.get('tab');
  const actif = ONGLETS.some((o) => o.valeur === tabParam) ? (tabParam as string) : 'score';

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-4">⭐ Ma réputation</h1>
      <Tabs value={actif} onValueChange={(v) => setParams({ tab: v }, { replace: true })}>
        <div className="overflow-x-auto -mx-1 px-1 mb-4">
          <TabsList className="w-max">
            {ONGLETS.map((o) => (
              <TabsTrigger key={o.valeur} value={o.valeur} className="gap-1.5">
                <o.icone className="h-4 w-4" />
                {o.label}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>

        <TabsContent value="score"><ScoreContent /></TabsContent>
        <TabsContent value="evaluations"><EvaluationsContent /></TabsContent>
        <TabsContent value="litiges"><LitigesSoignantContent /></TabsContent>
        <TabsContent value="reclamations"><ReclamationsContent role="SOIGNANT" /></TabsContent>
      </Tabs>
    </LayoutApp>
  );
}
