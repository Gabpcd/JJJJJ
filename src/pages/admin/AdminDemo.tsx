import React, { useState, useEffect } from 'react';
import { Database, Loader2, Trash2, Building2, Users, Briefcase, FileText } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';

export default function AdminDemo() {
  usePageTitle('Données de démo');
  const [loading, setLoading] = useState<'charger' | 'purger' | null>(null);
  const [kpi, setKpi] = useState<any>(null);
  const [kpiLoading, setKpiLoading] = useState(true);

  const chargerKpi = async () => {
    setKpiLoading(true);
    const { data } = await supabase.rpc('fn_admin_kpi' as any);
    if (data) setKpi(data);
    setKpiLoading(false);
  };

  useEffect(() => { chargerKpi(); }, []);

  const chargerDemo = async () => {
    setLoading('charger');
    const { error } = await supabase.rpc('fn_charger_demo_investisseur' as any);
    setLoading(null);
    if (error) {
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    } else {
      toast.success('Données de démo chargées — 4 établissements, 12 soignants, 35 missions');
      chargerKpi();
    }
  };

  const purgerDemo = async () => {
    setLoading('purger');
    const { error } = await supabase.rpc('fn_purger_demo' as any);
    setLoading(null);
    if (error) {
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    } else {
      toast.success('Données de démo supprimées — La base a été nettoyée');
      chargerKpi();
    }
  };

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Données de démo" />
      <div className="space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Données de démonstration</h1>
          <p className="text-muted-foreground mt-1">Charger ou purger un jeu de données réaliste pour les démos investisseurs.</p>
        </div>

        {/* Actions */}
        <div className="flex flex-wrap gap-4">
          <BoutonY2K onClick={chargerDemo} disabled={loading !== null} loading={loading === 'charger'} size="lg" className="gap-2" iconeGauche={loading === 'charger' ? undefined : <Database className="h-5 w-5" />}>
            Charger les données de démo
          </BoutonY2K>
          <BoutonY2K onClick={purgerDemo} disabled={loading !== null} loading={loading === 'purger'} variant="destructive" size="lg" className="gap-2" iconeGauche={loading === 'purger' ? undefined : <Trash2 className="h-5 w-5" />}>
            Purger la démo
          </BoutonY2K>
        </div>

        {/* Résumé BDD */}
        <div>
          <h2 className="text-lg font-semibold text-foreground mb-4">État actuel de la base</h2>
          {kpiLoading ? (
            <div className="flex items-center gap-2 text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Chargement…
            </div>
          ) : kpi ? (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <CarteKPIY2K
                label="Soignants"
                valeur={kpi.total_soignants ?? 0}
                icone={<Users className="h-4 w-4" />}
                variant="holographic"
              />
              <CarteKPIY2K
                label="Établissements"
                valeur={kpi.total_etablissements ?? 0}
                icone={<Building2 className="h-4 w-4" />}
                variant="default"
              />
              <CarteKPIY2K
                label="Missions"
                valeur={kpi.total_missions ?? 0}
                icone={<Briefcase className="h-4 w-4" />}
                variant="default"
              />
              <CarteKPIY2K
                label="Factures"
                valeur={kpi.total_factures ?? 0}
                icone={<FileText className="h-4 w-4" />}
                variant="default"
              />
            </div>
          ) : (
            <p className="text-muted-foreground">Impossible de charger les KPI.</p>
          )}
        </div>
      </div>
    </LayoutAdmin>
  );
}
