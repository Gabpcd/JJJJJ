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

const LOGICIELS = ['Silae', 'Sage Paie', 'ADP', 'Cegid', 'CSV Générique'];

function convertToCSV(data: Record<string, any>[]): string {
  if (data.length === 0) return '';
  const headers = Object.keys(data[0]);
  const rows = data.map(row => headers.map(h => {
    const val = row[h];
    const str = String(val ?? '');
    return str.includes(',') || str.includes('"') ? `"${str.replace(/"/g, '""')}"` : str;
  }).join(','));
  return [headers.join(','), ...rows].join('\n');
}

export default function ExportPaie() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [logiciel, setLogiciel] = useState('CSV Générique');
  const [mois, setMois] = useState(new Date().getMonth() + 1);
  const [annee, setAnnee] = useState(new Date().getFullYear());
  const [missions, setMissions] = useState<any[]>([]);

  const debutMois = new Date(annee, mois - 1, 1).toISOString();
  const finMois = new Date(annee, mois, 0, 23, 59, 59).toISOString();

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      setLoading(true);
      const { data } = await supabase
        .from('missions')
        .select(`*, soignants!soignant_assigne_id(prenom, nom, numero_secu, profession, numero_rpps)`)
        .eq('etablissement_id', user.id)
        .eq('statut', 'TERMINEE')
        .eq('type_paiement_soignant', 'BULLETIN_PAIE')
        .gte('fin_le', debutMois)
        .lt('fin_le', finMois)
        .order('debut_le', { ascending: true });
      setMissions((data as any[]) || []);
      setLoading(false);
    };
    load();
  }, [user, mois, annee]);

  const handleExport = async () => {
    if (!user || missions.length === 0) return;
    setExporting(true);

    const csvData = missions.map((m: any) => ({
      'Nom': m.soignants?.nom || '',
      'Prénom': m.soignants?.prenom || '',
      'N° Sécu': m.soignants?.numero_secu || '',
      'RPPS': m.soignants?.numero_rpps || '',
      'Profession': m.soignants?.profession || '',
      'Date début': format(new Date(m.debut_le), 'dd/MM/yyyy HH:mm'),
      'Date fin': format(new Date(m.fin_le), 'dd/MM/yyyy HH:mm'),
      'Heures totales': m.duree_heures || 0,
      'Heures nuit': m.heures_nuit || 0,
      'Heures dimanche': m.heures_dimanche || 0,
      'Heures férié': m.heures_ferie || 0,
      'Taux horaire': m.taux_horaire_base || 0,
      'Maj. nuit': m.montant_majoration_nuit || 0,
      'Maj. dimanche': m.montant_majoration_dimanche || 0,
      'Maj. férié': m.montant_majoration_ferie || 0,
      'IFM': m.montant_ifm || 0,
      'ICP': m.montant_icp || 0,
      'Total brut': m.total_brut || 0,
      'Type contrat': 'CDDU',
    }));

    const csv = convertToCSV(csvData);
    const BOM = '\uFEFF';
    const blob = new Blob([BOM + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `export_paie_${logiciel.replace(/\s/g, '_')}_${String(mois).padStart(2, '0')}_${annee}.csv`;
    a.click();
    URL.revokeObjectURL(url);

    // Audit
    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id,
      p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'EXPORT_RH_PAIE',
      p_type_ressource: 'etablissement',
      p_id_ressource: user.id,
      p_cle_s3: null,
      p_details: { logiciel, mois, annee, nb_missions: missions.length },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    setExporting(false);
    afficherNotification({ type: 'succes', message: `✅ Export généré — ${missions.length} missions exportées pour ${logiciel}` });
  };

  if (loading) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  const moisLabel = format(new Date(annee, mois - 1), 'MMMM yyyy', { locale: fr });

  return (
    <LayoutApp role="ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <FileSpreadsheet className="h-6 w-6 text-primary" /> Export Paie
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Générez un fichier CSV compatible avec votre logiciel de paie</p>
      </div>

      <div className="card-base mb-6 space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Logiciel de paie</label>
            <select value={logiciel} onChange={e => setLogiciel(e.target.value)} className="input-base">
              {LOGICIELS.map(l => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
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

      {/* Aperçu */}
      <div className="mb-6">
        <h2 className="text-lg font-bold text-foreground mb-3">Aperçu — {moisLabel}</h2>
        {missions.length > 0 ? (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border">
                    <th className="text-left py-2 px-2 text-xs text-muted-foreground font-medium">Date</th>
                    <th className="text-left py-2 px-2 text-xs text-muted-foreground font-medium">Soignant</th>
                    <th className="text-left py-2 px-2 text-xs text-muted-foreground font-medium">Profession</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Heures</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Nuit</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Dim</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Taux</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">IFM</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">ICP</th>
                    <th className="text-right py-2 px-2 text-xs text-muted-foreground font-medium">Brut</th>
                  </tr>
                </thead>
                <tbody>
                  {missions.map((m: any) => (
                    <tr key={m.id} className="border-b border-border/50">
                      <td className="py-2 px-2 text-xs">{format(new Date(m.debut_le), 'dd/MM', { locale: fr })}</td>
                      <td className="py-2 px-2 text-xs font-medium">{m.soignants?.prenom} {m.soignants?.nom}</td>
                      <td className="py-2 px-2 text-xs">{m.soignants?.profession}</td>
                      <td className="py-2 px-2 text-xs text-right">{m.duree_heures}h</td>
                      <td className="py-2 px-2 text-xs text-right">{m.heures_nuit || 0}h</td>
                      <td className="py-2 px-2 text-xs text-right">{m.heures_dimanche || 0}h</td>
                      <td className="py-2 px-2 text-xs text-right">{m.taux_horaire_base}€</td>
                      <td className="py-2 px-2 text-xs text-right">{(m.montant_ifm || 0).toFixed(0)}€</td>
                      <td className="py-2 px-2 text-xs text-right">{(m.montant_icp || 0).toFixed(0)}€</td>
                      <td className="py-2 px-2 text-xs text-right font-semibold">{(m.total_brut || 0).toFixed(0)}€</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="flex items-center justify-between mt-4">
              <p className="text-sm text-muted-foreground">{missions.length} missions salariées ce mois</p>
              <button onClick={handleExport} disabled={exporting} className="btn-primary flex items-center gap-2 disabled:opacity-50">
                {exporting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                {exporting ? 'Export en cours…' : '📥 Générer l\'export'}
              </button>
            </div>
          </>
        ) : (
          <EtatVide icone={FileSpreadsheet} titre="Aucune mission salariée terminée" sousTitre={`Aucune mission avec bulletin de paie en ${moisLabel}. Les notes d'honoraires (libéraux) ne sont pas incluses dans cet export.`} />
        )}
      </div>

      <p className="text-xs text-muted-foreground italic">
        ⚠️ Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
        Les missions libérales (notes d'honoraires) ne sont pas incluses dans cet export.
      </p>
    </LayoutApp>
  );
}
