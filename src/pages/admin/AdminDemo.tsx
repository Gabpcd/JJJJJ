import React, { useState, useEffect } from 'react';
import { Database, Loader2, Trash2, Building2, Users, Briefcase, FileText } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { CarteKPI } from '@/components/CarteKPI';

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
      toast({ title: 'Erreur', description: error.message, variant: 'destructive' });
    } else {
      toast({ title: 'Données de démo chargées', description: '4 établissements, 12 soignants, 35 missions' });
      chargerKpi();
    }
  };

  const purgerDemo = async () => {
    setLoading('purger');
    const { error } = await supabase.rpc('fn_purger_demo' as any);
    setLoading(null);
    if (error) {
      toast({ title: 'Erreur', description: error.message, variant: 'destructive' });
    } else {
      toast({ title: 'Données de démo supprimées', description: 'La base a été nettoyée.' });
      chargerKpi();
    }
  };

  return (
    <LayoutAdmin>
      <div className="space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Données de démonstration</h1>
          <p className="text-muted-foreground mt-1">Charger ou purger un jeu de données réaliste pour les démos investisseurs.</p>
        </div>

        {/* Actions */}
        <div className="flex flex-wrap gap-4">
          <Button onClick={chargerDemo} disabled={loading !== null} size="lg" className="gap-2">
            {loading === 'charger' ? <Loader2 className="h-5 w-5 animate-spin" /> : <Database className="h-5 w-5" />}
            Charger les données de démo
          </Button>
          <Button onClick={purgerDemo} disabled={loading !== null} variant="destructive" size="lg" className="gap-2">
            {loading === 'purger' ? <Loader2 className="h-5 w-5 animate-spin" /> : <Trash2 className="h-5 w-5" />}
            Purger la démo
          </Button>
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
              <CarteKPI label="Soignants" valeur={kpi.total_soignants ?? 0} icone={Users} couleurIcone="text-primary" couleurFond="bg-primary/10" />
              <CarteKPI label="Établissements" valeur={kpi.total_etablissements ?? 0} icone={Building2} couleurIcone="text-primary" couleurFond="bg-primary/10" />
              <CarteKPI label="Missions" valeur={kpi.total_missions ?? 0} icone={Briefcase} couleurIcone="text-primary" couleurFond="bg-primary/10" />
              <CarteKPI label="Factures" valeur={kpi.total_factures ?? 0} icone={FileText} couleurIcone="text-primary" couleurFond="bg-primary/10" />
            </div>
          ) : (
            <p className="text-muted-foreground">Impossible de charger les KPI.</p>
          )}
        </div>
      </div>
    </LayoutAdmin>
  );
}
