import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { CarteConformite } from '@/components/CarteConformite';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { handleErrorSilent } from '@/lib/handleError';
import { ShieldCheck, Copy } from 'lucide-react';
import { format, isToday, isYesterday } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

export default function ConformiteSoignant() {
  return (
    <LayoutApp role="SOIGNANT">
      <ConformiteContent />
    </LayoutApp>
  );
}

export function ConformiteContent() {
  usePageTitle('Conformité');
  const { user } = useAuth();
  const [controles, setControles] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('conformite_travail')
      .select('id, type_controle, resultat, controle_le, motif_derogation, missions(intitule, debut_le, fin_le, etablissement_id)')
      .eq('soignant_id', user.id)
      .order('controle_le', { ascending: false })
      .limit(50)
      .then(async ({ data }) => {
        const items = data || [];
        if (items.length > 0) {
          const etabIds = items.map((c: any) => c.missions?.etablissement_id).filter(Boolean);
          const etabMap = await fetchEtablissementsSafe(etabIds);
          items.forEach((c: any) => {
            if (c.missions?.etablissement_id) {
              c.missions.etablissements = etabMap[c.missions.etablissement_id] || null;
            }
          });
        }
        setControles(items);
        setLoading(false);

        // M1: Audit HDS consultation données de conformité
        supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'conformite_travail', p_id_ressource: user.id,
          p_cle_s3: null, p_details: { page: 'conformite_soignant' },
          p_ip: null, p_navigateur: navigator.userAgent,
        }).then(undefined, (err) => handleErrorSilent(err, 'ConformiteSoignant.audit'));
      }, (err) => handleErrorSilent(err, 'ConformiteSoignant.controles'));
  }, [user]);

  if (loading) return <ChargementPage />;

  const total = controles.length;
  const conformes = controles.filter(c => c.resultat === 'CONFORME').length;
  const violations = controles.filter(c => c.resultat === 'VIOLATION_BLOQUEE').length;
  const alertes = controles.filter(c => c.resultat === 'VIOLATION_ALERTEE').length;

  // Group by date
  const grouped = controles.reduce((acc, c) => {
    const date = new Date(c.controle_le);
    let label: string;
    if (isToday(date)) label = "Aujourd'hui";
    else if (isYesterday(date)) label = 'Hier';
    else label = format(date, 'EEEE d MMMM yyyy', { locale: fr });
    if (!acc[label]) acc[label] = [];
    acc[label].push(c);
    return acc;
  }, {} as Record<string, any[]>);

  const exporterHistorique = () => {
    const lignes = controles.map(c => {
      const date = format(new Date(c.controle_le), 'dd/MM/yyyy HH:mm', { locale: fr });
      const mission = c.missions?.intitule || '—';
      return `${date} | ${c.type_controle} | ${c.resultat} | ${mission}`;
    });
    const texte = `Historique de conformité — Jolene\n${'='.repeat(50)}\n\n${lignes.join('\n')}`;
    navigator.clipboard.writeText(texte);
    toast.success('Historique copié dans le presse-papier');
  };

  return (
    <>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-foreground">📊 Historique de conformité</h1>
        <button onClick={exporterHistorique} className="btn-secondary text-xs px-3 py-2 flex items-center gap-1.5">
          <Copy className="h-3.5 w-3.5" /> Exporter
        </button>
      </div>

      {/* KPI */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <div className="card-base text-center">
          <p className="text-2xl font-bold text-foreground">{total}</p>
          <p className="text-xs text-muted-foreground">Contrôles</p>
        </div>
        <div className="card-base text-center">
          <p className="text-2xl font-bold text-success">{conformes}</p>
          <p className="text-xs text-muted-foreground">Conformes ({total > 0 ? Math.round((conformes / total) * 100) : 0}%)</p>
        </div>
        <div className="card-base text-center">
          <p className="text-2xl font-bold text-destructive">{violations}</p>
          <p className="text-xs text-muted-foreground">Violations bloquées</p>
        </div>
        <div className="card-base text-center">
          <p className="text-2xl font-bold text-warning">{alertes}</p>
          <p className="text-xs text-muted-foreground">Alertes</p>
        </div>
      </div>

      {controles.length === 0 ? (
        <EmptyState
          icone={<ShieldCheck />}
          mascotte="empty"
          titre="Aucun contrôle de conformité"
          description="Les contrôles apparaîtront ici lorsque tu accepteras des missions."
        />
      ) : (
        <div className="space-y-6">
          {(Object.entries(grouped) as Array<[string, any[]]>).map(([label, items]) => (
            <div key={label}>
              <h3 className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">{label}</h3>
              <div className="card-base divide-y divide-border">
                {items.map((c: any) => (
                  <CarteConformite key={c.id} controle={c} />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}
