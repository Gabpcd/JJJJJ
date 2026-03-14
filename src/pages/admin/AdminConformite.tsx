import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { ShieldAlert, Clock, FileWarning, FileQuestion, Repeat, UserX, FileX } from 'lucide-react';

interface Indicateur {
  cle: string;
  label: string;
  icone: React.ElementType;
}

const INDICATEURS: Indicateur[] = [
  { cle: 'violations_repos_11h', label: 'Violations repos 11h', icone: Clock },
  { cle: 'alertes_48h', label: 'Alertes 48h', icone: ShieldAlert },
  { cle: 'docs_expires', label: 'Documents expirés', icone: FileWarning },
  { cle: 'docs_en_attente', label: 'Documents en attente', icone: FileQuestion },
  { cle: 'cddu_repetitifs', label: 'CDDU répétitifs', icone: Repeat },
  { cle: 'soignants_sans_docs', label: 'Soignants sans documents', icone: UserX },
  { cle: 'missions_sans_contrat', label: 'Missions sans contrat', icone: FileX },
];

function getCouleur(val: number): string {
  if (val === 0) return 'text-green-500';
  if (val <= 5) return 'text-orange-500';
  return 'text-destructive';
}

function getBgCouleur(val: number): string {
  if (val === 0) return 'bg-green-500/10 border-green-500/20';
  if (val <= 5) return 'bg-orange-500/10 border-orange-500/20';
  return 'bg-destructive/10 border-destructive/20';
}

export default function AdminConformite() {
  usePageTitle('Conformité');
  const [data, setData] = useState<Record<string, number> | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.rpc('fn_admin_conformite' as any).then(({ data: d }: any) => {
      if (d && typeof d === 'object') setData(d);
      else if (Array.isArray(d) && d[0]) setData(d[0]);
      setLoading(false);
    });
  }, []);

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Conformité" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Conformité</h1>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {INDICATEURS.map((ind) => {
            const val = data?.[ind.cle] ?? 0;
            return (
              <Card key={ind.cle} className={`border ${getBgCouleur(val)}`}>
                <CardContent className="pt-5 pb-5 flex items-center gap-4">
                  <div className={`rounded-xl p-2.5 ${getBgCouleur(val)}`}>
                    <ind.icone className={`h-5 w-5 ${getCouleur(val)}`} />
                  </div>
                  <div>
                    <p className={`text-2xl font-bold ${getCouleur(val)}`}>{val}</p>
                    <p className="text-xs text-muted-foreground">{ind.label}</p>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      </div>
    </LayoutAdmin>
  );
}
