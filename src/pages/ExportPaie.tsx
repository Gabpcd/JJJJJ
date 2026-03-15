import { useState, useEffect } from 'react';
import { FileSpreadsheet, Download, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

type FormatExport = 'Silae' | 'Sage' | 'ADP';

function generateSilaeCSV(missions: any[], soignantMap: Record<string, any>): string {
  const BOM = '\uFEFF';
  const headers = ['matricule', 'nom', 'prenom', 'date_debut', 'date_fin', 'heures', 'taux_horaire', 'brut', 'ifm', 'icp', 'total_brut'];
  const rows = missions.map((m: any) => {
    const sg = soignantMap[m.soignant_assigne_id];
    return [
      sg?.id?.substring(0, 8) || '',
      sg?.nom || '',
      sg?.prenom || '',
      format(new Date(m.debut_le), 'dd/MM/yyyy'),
      format(new Date(m.fin_le), 'dd/MM/yyyy'),
      m.duree_heures || 0,
      m.taux_horaire_base || 0,
      ((m.duree_heures || 0) * (m.taux_horaire_base || 0)).toFixed(2),
      (m.montant_ifm || 0).toFixed(2),
      (m.montant_icp || 0).toFixed(2),
      (m.total_brut || 0).toFixed(2),
    ].join(';');
  });
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function generateSageCSV(missions: any[], soignantMap: Record<string, any>): string {
  const BOM = '\uFEFF';
  const headers = ['code_societe', 'matricule', 'rubrique', 'base', 'taux', 'montant'];
  const rows: string[] = [];
  for (const m of missions) {
    const sg = soignantMap[m.soignant_assigne_id];
    const matricule = sg?.id?.substring(0, 8) || '';
    const codeSociete = 'SD001';
    // Base hours
    rows.push([codeSociete, matricule, '100', m.duree_heures || 0, m.taux_horaire_base || 0, ((m.duree_heures || 0) * (m.taux_horaire_base || 0)).toFixed(2)].join(';'));
    // IFM
    if (m.montant_ifm > 0) rows.push([codeSociete, matricule, '200', 1, (m.montant_ifm || 0).toFixed(2), (m.montant_ifm || 0).toFixed(2)].join(';'));
    // ICP
    if (m.montant_icp > 0) rows.push([codeSociete, matricule, '210', 1, (m.montant_icp || 0).toFixed(2), (m.montant_icp || 0).toFixed(2)].join(';'));
    // Night surcharge
    if (m.montant_majoration_nuit > 0) rows.push([codeSociete, matricule, '300', m.heures_nuit || 0, '', (m.montant_majoration_nuit || 0).toFixed(2)].join(';'));
    // Sunday surcharge
    if (m.montant_majoration_dimanche > 0) rows.push([codeSociete, matricule, '310', m.heures_dimanche || 0, '', (m.montant_majoration_dimanche || 0).toFixed(2)].join(';'));
    // Holiday surcharge
    if (m.montant_majoration_ferie > 0) rows.push([codeSociete, matricule, '320', m.heures_ferie || 0, '', (m.montant_majoration_ferie || 0).toFixed(2)].join(';'));
  }
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function generateADPCSV(missions: any[], soignantMap: Record<string, any>): string {
  const BOM = '\uFEFF';
  const headers = ['employee_id', 'pay_period_start', 'pay_period_end', 'hours_worked', 'hourly_rate', 'gross_pay'];
  const rows = missions.map((m: any) => {
    const sg = soignantMap[m.soignant_assigne_id];
    return [
      sg?.id?.substring(0, 8) || '',
      format(new Date(m.debut_le), 'yyyy-MM-dd'),
      format(new Date(m.fin_le), 'yyyy-MM-dd'),
      m.duree_heures || 0,
      m.taux_horaire_base || 0,
      (m.total_brut || 0).toFixed(2),
    ].join(',');
  });
  return BOM + [headers.join(','), ...rows].join('\n');
}

function downloadCSV(content: string, filename: string) {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export default function ExportPaie() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState<FormatExport | null>(null);
  const [mois, setMois] = useState(new Date().getMonth() + 1);
  const [annee, setAnnee] = useState(new Date().getFullYear());
  const [missions, setMissions] = useState<any[]>([]);
  const [soignantMap, setSoignantMap] = useState<Record<string, any>>({});

  const debutMois = new Date(annee, mois - 1, 1).toISOString();
  const finMois = new Date(annee, mois, 0, 23, 59, 59).toISOString();

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      setLoading(true);
      const [{ data: missionsData }, { data: soignantsData }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, heures_nuit, heures_dimanche, heures_ferie, taux_horaire_base, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, montant_ifm, montant_icp, total_brut, soignant_assigne_id, type_paiement_soignant, contrats_mission(type_contrat)')
          .eq('etablissement_id', user.id)
          .eq('statut', 'TERMINEE')
          .eq('type_paiement_soignant', 'BULLETIN_PAIE')
          .gte('fin_le', debutMois)
          .lt('fin_le', finMois)
          .order('debut_le', { ascending: true }),
        supabase.rpc('fn_mes_soignants_etablissement'),
      ]);

      const sgMap: Record<string, any> = {};
      if (Array.isArray(soignantsData)) {
        for (const s of soignantsData) sgMap[s.id] = s;
      }
      setSoignantMap(sgMap);
      setMissions((missionsData as any[]) || []);
      setLoading(false);
    };
    load();
  }, [user, mois, annee]);

  const handleExport = async (fmt: FormatExport) => {
    if (!user || missions.length === 0) return;
    setExporting(fmt);

    const moisStr = String(mois).padStart(2, '0');
    let content: string;
    let filename: string;

    switch (fmt) {
      case 'Silae':
        content = generateSilaeCSV(missions, soignantMap);
        filename = `export_silae_${moisStr}_${annee}.csv`;
        break;
      case 'Sage':
        content = generateSageCSV(missions, soignantMap);
        filename = `export_sage_${moisStr}_${annee}.csv`;
        break;
      case 'ADP':
        content = generateADPCSV(missions, soignantMap);
        filename = `export_adp_${moisStr}_${annee}.csv`;
        break;
    }

    downloadCSV(content, filename);

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id,
      p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'EXPORT_RH_PAIE',
      p_type_ressource: 'etablissement',
      p_id_ressource: user.id,
      p_cle_s3: null,
      p_details: { logiciel: fmt, mois, annee, nb_missions: missions.length },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    setExporting(null);
    afficherNotification({ type: 'succes', message: `✅ Export ${fmt} généré — ${missions.length} missions` });
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  const moisLabel = format(new Date(annee, mois - 1), 'MMMM yyyy', { locale: fr });

  const FORMATS: { id: FormatExport; label: string; desc: string; icon: string }[] = [
    { id: 'Silae', label: 'Silae', desc: 'CSV point-virgule — matricule, nom, heures, brut, IFM, ICP', icon: '📊' },
    { id: 'Sage', label: 'Sage Paie', desc: 'CSV multi-rubriques — code société, rubriques paie ventilées', icon: '📋' },
    { id: 'ADP', label: 'ADP', desc: 'CSV international — employee_id, hours, gross_pay', icon: '🌐' },
  ];

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <FileSpreadsheet className="h-6 w-6 text-primary" /> Export Paie
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Générez un fichier CSV compatible avec votre logiciel de paie</p>
      </div>

      {/* Period selector */}
      <div className="card-base mb-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Mois</label>
            <select value={mois} onChange={e => setMois(Number(e.target.value))} className="input-base">
              {Array.from({ length: 12 }, (_, i) => (
                <option key={i + 1} value={i + 1}>{format(new Date(2026, i), 'MMMM', { locale: fr })}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Année</label>
            <select value={annee} onChange={e => setAnnee(Number(e.target.value))} className="input-base">
              {[2024, 2025, 2026].map(a => <option key={a} value={a}>{a}</option>)}
            </select>
          </div>
        </div>
      </div>

      {/* Export format cards */}
      <div className="mb-6">
        <h2 className="text-lg font-bold text-foreground mb-3">Formats d'export</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {FORMATS.map(fmt => (
            <div key={fmt.id} className="card-base flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-2xl">{fmt.icon}</span>
                  <h3 className="font-semibold text-foreground">{fmt.label}</h3>
                </div>
                <p className="text-xs text-muted-foreground mb-4">{fmt.desc}</p>
              </div>
              <button
                onClick={() => handleExport(fmt.id)}
                disabled={missions.length === 0 || exporting !== null}
                className="btn-primary flex items-center justify-center gap-2 text-sm w-full disabled:opacity-50"
              >
                {exporting === fmt.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                {exporting === fmt.id ? 'Export…' : 'Télécharger'}
              </button>
            </div>
          ))}
        </div>
      </div>

      {/* Preview table */}
      <div className="mb-6">
        <h2 className="text-lg font-bold text-foreground mb-3">Aperçu — {moisLabel}</h2>
        {missions.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 px-2 text-xs text-muted-foreground font-medium">Date</th>
                  <th className="text-left py-2 px-2 text-xs text-muted-foreground font-medium">Soignant</th>
                  <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Heures</th>
                  <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Taux</th>
                  <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">IFM</th>
                  <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">ICP</th>
                  <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Brut</th>
                </tr>
              </thead>
              <tbody>
                {missions.map((m: any) => {
                  const sg = soignantMap[m.soignant_assigne_id];
                  return (
                    <tr key={m.id} className="border-b border-border/50">
                      <td className="py-2 px-2 text-xs">{format(new Date(m.debut_le), 'dd/MM', { locale: fr })}</td>
                      <td className="py-2 px-2 text-xs font-medium">{sg?.prenom} {sg?.nom}</td>
                      <td className="py-2 px-2 text-xs text-right">{m.duree_heures}h</td>
                      <td className="py-2 px-2 text-xs text-right">{m.taux_horaire_base}€</td>
                      <td className="py-2 px-2 text-xs text-right">{(m.montant_ifm || 0).toFixed(0)}€</td>
                      <td className="py-2 px-2 text-xs text-right">{(m.montant_icp || 0).toFixed(0)}€</td>
                      <td className="py-2 px-2 text-xs text-right font-semibold">{(m.total_brut || 0).toFixed(0)}€</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            <p className="text-sm text-muted-foreground mt-3">{missions.length} missions salariées ce mois</p>
          </div>
        ) : (
          <EtatVide icone={FileSpreadsheet} titre="Aucune mission salariée terminée" sousTitre={`Aucune mission avec bulletin de paie en ${moisLabel}.`} />
        )}
      </div>

      <p className="text-xs text-muted-foreground italic">
        ⚠️ Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
      </p>
    </LayoutApp>
  );
}
