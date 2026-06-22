import { usePageTitle } from '@/hooks/usePageTitle';
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileSpreadsheet, Download, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { telechargerOuPartager } from '@/lib/telechargement';

type FormatExport = 'Standard' | 'Silae' | 'Sage';

function downloadCSV(content: string, filename: string) {
  void telechargerOuPartager(content, filename, 'text/csv');
}

const BOM = '﻿';

function generateStandardCSV(missions: any[], sgMap: Record<string, any>): string {
  const headers = ['Nom', 'Prenom', 'Matricule_RPPS', 'Mission', 'Date_debut', 'Date_fin', 'Heures_travaillees', 'Taux_horaire', 'Maj_nuit', 'Maj_dimanche', 'Maj_ferie', 'IFM', 'ICP', 'Brut', 'Cotisations_salariales', 'Net'];
  const rows = missions.map((m: any) => {
    const sg = sgMap[m.soignant_assigne_id];
    const brut = m.total_brut || 0;
    // Taux de cotisations salariales estimé à 22% — source : barème URSSAF 2025, profils soignants intérimaires
    const cotis = brut * 0.22;
    const net = brut - cotis;
    return [
      sg?.nom || 'Soignant inconnu', sg?.prenom || '', sg?.numero_rpps || sg?.id?.substring(0, 8) || '',
      m.intitule || '', format(new Date(m.debut_le), 'dd/MM/yyyy'), format(new Date(m.fin_le), 'dd/MM/yyyy'),
      m.duree_heures || 0, m.taux_horaire_base || 0,
      (m.montant_majoration_nuit || 0).toFixed(2), (m.montant_majoration_dimanche || 0).toFixed(2), (m.montant_majoration_ferie || 0).toFixed(2),
      (m.montant_ifm || 0).toFixed(2), (m.montant_icp || 0).toFixed(2),
      brut.toFixed(2), cotis.toFixed(2), net.toFixed(2),
    ].join(';');
  });
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function generateSilaeCSV(missions: any[], sgMap: Record<string, any>): string {
  const headers = ['matricule', 'nom', 'prenom', 'date_debut', 'date_fin', 'heures', 'taux_horaire', 'brut', 'ifm', 'icp', 'total_brut'];
  const rows = missions.map((m: any) => {
    const sg = sgMap[m.soignant_assigne_id];
    return [
      sg?.numero_rpps || sg?.id?.substring(0, 8) || '', sg?.nom || '', sg?.prenom || '',
      format(new Date(m.debut_le), 'dd/MM/yyyy'), format(new Date(m.fin_le), 'dd/MM/yyyy'),
      m.duree_heures || 0, m.taux_horaire_base || 0,
      ((m.duree_heures || 0) * (m.taux_horaire_base || 0)).toFixed(2),
      (m.montant_ifm || 0).toFixed(2), (m.montant_icp || 0).toFixed(2), (m.total_brut || 0).toFixed(2),
    ].join(';');
  });
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function generateSageCSV(missions: any[], sgMap: Record<string, any>): string {
  const headers = ['code_societe', 'matricule', 'rubrique', 'base', 'taux', 'montant'];
  const rows: string[] = [];
  for (const m of missions) {
    const sg = sgMap[m.soignant_assigne_id];
    const matricule = sg?.numero_rpps || sg?.id?.substring(0, 8) || '';
    const code = 'SD001';
    rows.push([code, matricule, '100', m.duree_heures || 0, m.taux_horaire_base || 0, ((m.duree_heures || 0) * (m.taux_horaire_base || 0)).toFixed(2)].join(';'));
    if (m.montant_ifm > 0) rows.push([code, matricule, '200', 1, (m.montant_ifm || 0).toFixed(2), (m.montant_ifm || 0).toFixed(2)].join(';'));
    if (m.montant_icp > 0) rows.push([code, matricule, '210', 1, (m.montant_icp || 0).toFixed(2), (m.montant_icp || 0).toFixed(2)].join(';'));
    if (m.montant_majoration_nuit > 0) rows.push([code, matricule, '300', m.heures_nuit || 0, '', (m.montant_majoration_nuit || 0).toFixed(2)].join(';'));
    if (m.montant_majoration_dimanche > 0) rows.push([code, matricule, '310', m.heures_dimanche || 0, '', (m.montant_majoration_dimanche || 0).toFixed(2)].join(';'));
    if (m.montant_majoration_ferie > 0) rows.push([code, matricule, '320', m.heures_ferie || 0, '', (m.montant_majoration_ferie || 0).toFixed(2)].join(';'));
  }
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function fmt(v: number) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function ExportPaie() {
  usePageTitle('Export Paie');
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState<FormatExport | null>(null);
  const [mois, setMois] = useState(String(new Date().getMonth() + 1));
  const [annee, setAnnee] = useState(String(new Date().getFullYear()));
  const [missions, setMissions] = useState<any[]>([]);
  const [soignantMap, setSoignantMap] = useState<Record<string, any>>({});

  useEffect(() => {
    if (!user || !etablissementId) return;
    const load = async () => {
      setLoading(true);
      const m = Number(mois);
      const a = Number(annee);
      const debutMois = new Date(a, m - 1, 1).toISOString();
      const finMois = new Date(a, m, 0, 23, 59, 59).toISOString();

      const [{ data: missionsData }, { data: soignantsData }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, heures_nuit, heures_dimanche, heures_ferie, taux_horaire_base, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, montant_ifm, montant_icp, total_brut, soignant_assigne_id, type_paiement_soignant, presences(pointage_arrivee_le, pointage_depart_le)')
          .eq('etablissement_id', etablissementId)
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

      // Fallback: fetch soignant names directly if RPC returned empty
      if (Object.keys(sgMap).length === 0 && missionsData) {
        const sgIds = [...new Set((missionsData as any[]).map((m: any) => m.soignant_assigne_id).filter(Boolean))];
        if (sgIds.length > 0) {
          const { data: sgDirect } = await supabase.from('soignants').select('id, prenom, nom, profession, score_fiabilite, numero_rpps').in('id', sgIds);
          if (sgDirect) for (const s of sgDirect) sgMap[s.id] = s;
        }
      }
      setSoignantMap(sgMap);
      setMissions((missionsData as any[]) || []);
      setLoading(false);
    };
    load();
  }, [user, etablissementId, mois, annee]);

  const handleExport = async (fmt: FormatExport) => {
    if (!user || missions.length === 0) return;
    setExporting(fmt);
    const moisStr = mois.padStart(2, '0');
    let content: string;
    let filename: string;
    switch (fmt) {
      case 'Standard':
        content = generateStandardCSV(missions, soignantMap);
        filename = `export_paie_${moisStr}_${annee}.csv`;
        break;
      case 'Silae':
        content = generateSilaeCSV(missions, soignantMap);
        filename = `export_silae_${moisStr}_${annee}.csv`;
        break;
      case 'Sage':
        content = generateSageCSV(missions, soignantMap);
        filename = `export_sage_${moisStr}_${annee}.csv`;
        break;
    }
    downloadCSV(content, filename);

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'EXPORT_RH_PAIE',
      p_type_ressource: 'etablissement', p_id_ressource: user.id, p_cle_s3: null,
      p_details: { logiciel: fmt, mois: Number(mois), annee: Number(annee), nb_missions: missions.length },
      p_ip: null, p_navigateur: navigator.userAgent,
    });

    setExporting(null);
    afficherNotification({ type: 'succes', message: `✅ Export ${fmt} généré — ${missions.length} missions` });
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  const moisLabel = format(new Date(Number(annee), Number(mois) - 1), 'MMMM yyyy', { locale: fr });

  const FORMATS: { id: FormatExport; label: string; desc: string }[] = [
    { id: 'Standard', label: 'Standard (CSV)', desc: 'Nom, Prénom, RPPS, Heures, Majorations, IFM/ICP, Brut, Cotisations, Net' },
    { id: 'Silae', label: 'Silae', desc: 'Format Silae — point-virgule, UTF-8 BOM' },
    { id: 'Sage', label: 'Sage Paie', desc: 'Format Sage — multi-rubriques ventilées' },
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
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Mois</label>
            <Select value={mois} onValueChange={setMois}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {Array.from({ length: 12 }, (_, i) => (
                  <SelectItem key={i + 1} value={String(i + 1)}>{format(new Date(2026, i), 'MMMM', { locale: fr })}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Année</label>
            <Select value={annee} onValueChange={setAnnee}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {[2024, 2025, 2026].map(a => <SelectItem key={a} value={String(a)}>{a}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>
      </div>

      {/* Export format buttons */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        {FORMATS.map(f => (
          <div key={f.id} className="card-base flex flex-col justify-between">
            <div className="mb-3">
              <h3 className="font-semibold text-foreground text-sm">{f.label}</h3>
              <p className="text-xs text-muted-foreground mt-1">{f.desc}</p>
            </div>
            <Button
              onClick={() => handleExport(f.id)}
              disabled={missions.length === 0 || exporting !== null}
              className="gap-2 w-full"
            >
              {exporting === f.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
              {exporting === f.id ? 'Export…' : 'Télécharger'}
            </Button>
          </div>
        ))}
      </div>

      {/* Preview table */}
      <h2 className="text-base font-bold text-foreground mb-3">Aperçu — {moisLabel}</h2>
      {missions.length > 0 ? (
        <div className="overflow-x-auto scroll-hint border border-border rounded-xl">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-muted/30">
                <th className="text-left py-2.5 px-3 text-xs text-muted-foreground font-medium">Soignant</th>
                <th className="text-left py-2.5 px-3 text-xs text-muted-foreground font-medium">Mission</th>
                <th className="text-left py-2.5 px-3 text-xs text-muted-foreground font-medium">Dates</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Heures</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Taux</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Maj. nuit</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Maj. dim.</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Maj. férié</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">IFM</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">ICP</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Brut</th>
                <th className="text-right py-2.5 px-3 text-xs text-muted-foreground font-medium">Net est.</th>
              </tr>
            </thead>
            <tbody>
              {missions.map((m: any) => {
                const sg = soignantMap[m.soignant_assigne_id];
                const brut = m.total_brut || 0;
                const net = brut * 0.78;
                return (
                  <tr key={m.id} className="border-b border-border/50 hover:bg-muted/20 cursor-pointer" onClick={() => navigate(`/etablissement/presences/mission/${m.id}`)}>
                    <td className="py-2 px-3 text-xs font-medium">{sg?.prenom && sg?.nom ? `${sg.prenom} ${sg.nom}` : 'Soignant inconnu'}</td>
                    <td className="py-2 px-3 text-xs text-muted-foreground">{m.intitule}</td>
                    <td className="py-2 px-3 text-xs text-muted-foreground whitespace-nowrap">
                      <div>{format(new Date(m.debut_le), 'dd/MM/yyyy HH:mm')} → {format(new Date(m.fin_le), 'dd/MM/yyyy HH:mm')}</div>
                      {m.presences?.[0]?.pointage_arrivee_le && m.presences?.[0]?.pointage_depart_le && (
                        <div className="text-[10px] text-primary">
                          Pointage : {format(new Date(m.presences[0].pointage_arrivee_le), 'HH:mm')} → {format(new Date(m.presences[0].pointage_depart_le), 'HH:mm')}
                        </div>
                      )}
                    </td>
                    <td className="py-2 px-3 text-xs text-right">{m.duree_heures}h</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(m.taux_horaire_base || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(m.montant_majoration_nuit || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(m.montant_majoration_dimanche || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(m.montant_majoration_ferie || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(m.montant_ifm || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(m.montant_icp || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right font-medium">{fmt(brut)}</td>
                    <td className="py-2 px-3 text-xs text-right font-semibold text-success">{fmt(net)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <p className="text-xs text-muted-foreground px-3 py-2">{missions.length} missions salariées · cliquez sur une ligne pour voir le détail des pointages</p>
        </div>
      ) : (
        <EmptyState icone={<FileSpreadsheet />} mascotte="empty" titre="Aucune mission salariée terminée" description={`Aucune mission avec bulletin de paie en ${moisLabel}.`} cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
      )}

      <p className="text-xs text-muted-foreground italic mt-4">
        ⚠️ Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
      </p>
    </LayoutApp>
  );
}
