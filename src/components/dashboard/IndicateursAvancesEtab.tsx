import React, { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { IndicateurTurnover } from '@/components/dashboard/IndicateurTurnover';
import { JaugeTauxRemplissage } from '@/components/dashboard/JaugeTauxRemplissage';
import { KPICoutMoyenHeure } from '@/components/dashboard/KPICoutMoyenHeure';

interface Stats {
  soignants_mois_precedent: number;
  cout_brut_ce_mois: number;
  heures_ce_mois: number;
  missions_pourvues_ce_mois: number;
  missions_publiees_ce_mois: number;
}

interface Props {
  /** Compteur soignants ce mois — vient du fn_stats_dashboard_etablissement principal */
  soignantsCeMois: number;
}

/**
 * Charge fn_stats_etab_complements et affiche les 3 composants graphiques étab
 * (Turnover, Taux remplissage, Coût moyen).
 */
export function IndicateursAvancesEtab({ soignantsCeMois }: Props) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase.rpc('fn_stats_etab_complements' as any);
      if (!alive) return;
      const payload = data as any;
      if (payload && !payload.error) {
        setStats(payload as Stats);
      }
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  if (loading || !stats) return null;

  // N'afficher que si on a au moins une donnée significative
  const hasData =
    stats.missions_publiees_ce_mois > 0
    || stats.soignants_mois_precedent > 0
    || soignantsCeMois > 0
    || Number(stats.cout_brut_ce_mois) > 0;
  if (!hasData) return null;

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-6">
      <IndicateurTurnover
        soignantsCeMois={soignantsCeMois}
        soignantsMoisPrecedent={Number(stats.soignants_mois_precedent) || 0}
      />
      <JaugeTauxRemplissage
        pourvues={Number(stats.missions_pourvues_ce_mois) || 0}
        total={Number(stats.missions_publiees_ce_mois) || 0}
      />
      <KPICoutMoyenHeure
        totalBrut={Number(stats.cout_brut_ce_mois) || 0}
        totalHeures={Number(stats.heures_ce_mois) || 0}
      />
    </div>
  );
}
