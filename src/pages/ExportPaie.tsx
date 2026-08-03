import { usePageTitle } from '@/hooks/usePageTitle';
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, FileSpreadsheet, Download, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { telechargerOuPartager } from '@/lib/telechargement';
import { chargerCreneauxMissionsPagines } from '@/lib/mission-creneaux-pagines';
import {
  bornesMoisPaieParis,
  construireExportPaiePeriode,
  type MissionExportPaiePeriode,
} from '@/lib/export-paie-planning';
import { cleMoisParis, formatParis } from '@/lib/date-heure-paris';

type FormatExport = 'Standard' | 'Silae' | 'Sage';

async function downloadCSV(content: string, filename: string) {
  await telechargerOuPartager(content, filename, 'text/csv');
}

const BOM = '﻿';

function generateStandardCSV(missions: MissionExportPaiePeriode[], sgMap: Record<string, any>): string {
  const headers = ['Nom', 'Prenom', 'Matricule_RPPS', 'Mission', 'Date_heure_debut', 'Date_heure_fin', 'Heures_travaillees', 'Taux_horaire', 'Maj_nuit_mission_periode', 'Maj_dimanche_mission_periode', 'Maj_ferie_mission_periode', 'IFM_mission_periode', 'ICP_mission_periode', 'Brut_mission_periode'];
  const rows = missions.flatMap((m) => {
    const sg = sgMap[m.soignant_assigne_id];
    return m.creneaux_export.map((creneau, index) => [
        sg?.nom || '', sg?.prenom || '', sg?.numero_rpps || sg?.id?.substring(0, 8) || '',
        m.intitule || '', formatParis(creneau.debut, 'dd/MM/yyyy HH:mm'), formatParis(creneau.fin, 'dd/MM/yyyy HH:mm'),
        creneau.duree_heures, m.taux_horaire_base || 0,
        index === 0 ? (Number(m.montant_majoration_nuit) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.montant_majoration_dimanche) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.montant_majoration_ferie) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.montant_ifm) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.montant_icp) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.total_brut) || 0).toFixed(2) : '',
      ].join(';'));
  });
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function generateSilaeCSV(missions: MissionExportPaiePeriode[], sgMap: Record<string, any>): string {
  const headers = ['matricule', 'nom', 'prenom', 'date_heure_debut', 'date_heure_fin', 'heures', 'taux_horaire', 'brut', 'ifm', 'icp', 'total_brut'];
  const rows = missions.flatMap((m) => {
    const sg = sgMap[m.soignant_assigne_id];
    return m.creneaux_export.map((creneau, index) => [
        sg?.numero_rpps || sg?.id?.substring(0, 8) || '', sg?.nom || '', sg?.prenom || '',
        formatParis(creneau.debut, 'dd/MM/yyyy HH:mm'), formatParis(creneau.fin, 'dd/MM/yyyy HH:mm'),
        creneau.duree_heures, m.taux_horaire_base || 0,
        (creneau.duree_heures * (Number(m.taux_horaire_base) || 0)).toFixed(2),
        index === 0 ? (Number(m.montant_ifm) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.montant_icp) || 0).toFixed(2) : '',
        index === 0 ? (Number(m.total_brut) || 0).toFixed(2) : '',
      ].join(';'));
  });
  return BOM + [headers.join(';'), ...rows].join('\n');
}

function generateSageCSV(missions: MissionExportPaiePeriode[], sgMap: Record<string, any>): string {
  const headers = ['code_societe', 'matricule', 'date_heure_debut', 'date_heure_fin', 'rubrique', 'base', 'taux', 'montant'];
  const rows: string[] = [];
  for (const m of missions) {
    const sg = sgMap[m.soignant_assigne_id];
    const matricule = sg?.numero_rpps || sg?.id?.substring(0, 8) || '';
    const code = 'SD001';
    m.creneaux_export.forEach((creneau) => {
      const commun = [code, matricule, formatParis(creneau.debut, 'dd/MM/yyyy HH:mm'), formatParis(creneau.fin, 'dd/MM/yyyy HH:mm')];
      rows.push([...commun, '100', creneau.duree_heures, m.taux_horaire_base || 0, (creneau.duree_heures * (Number(m.taux_horaire_base) || 0)).toFixed(2)].join(';'));
    });
    const communMission = [code, matricule, '', ''];
    if (Number(m.montant_ifm) > 0) rows.push([...communMission, '200', 1, Number(m.montant_ifm).toFixed(2), Number(m.montant_ifm).toFixed(2)].join(';'));
    if (Number(m.montant_icp) > 0) rows.push([...communMission, '210', 1, Number(m.montant_icp).toFixed(2), Number(m.montant_icp).toFixed(2)].join(';'));
    if (Number(m.montant_majoration_nuit) > 0) rows.push([...communMission, '300', Number(m.heures_nuit) || 0, '', Number(m.montant_majoration_nuit).toFixed(2)].join(';'));
    if (Number(m.montant_majoration_dimanche) > 0) rows.push([...communMission, '310', Number(m.heures_dimanche) || 0, '', Number(m.montant_majoration_dimanche).toFixed(2)].join(';'));
    if (Number(m.montant_majoration_ferie) > 0) rows.push([...communMission, '320', Number(m.heures_ferie) || 0, '', Number(m.montant_majoration_ferie).toFixed(2)].join(';'));
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
  const [anneeCourante, moisCourant] = cleMoisParis(new Date()).split('-');
  const [mois, setMois] = useState(String(Number(moisCourant)));
  const [annee, setAnnee] = useState(anneeCourante);
  const [missions, setMissions] = useState<MissionExportPaiePeriode[]>([]);
  const [soignantMap, setSoignantMap] = useState<Record<string, any>>({});
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    if (!user || !etablissementId) return;
    let actif = true;
    const load = async () => {
      setLoading(true);
      setErreurChargement(null);
      setMissions([]);
      setSoignantMap({});
      try {
        const m = Number(mois);
        const a = Number(annee);
        const bornes = bornesMoisPaieParis(a, m);

        const [missionsResult, soignantsResult] = await Promise.all([
          supabase
            .from('missions')
            .select('id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, heures_nuit, heures_dimanche, heures_ferie, taux_horaire_base, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, montant_ifm, montant_icp, total_brut, soignant_assigne_id, type_paiement_soignant, statut, presences(valide_par_etablissement, valide_auto_72h_le, valide_le)')
            .eq('etablissement_id', etablissementId)
            .in('statut', ['TERMINEE', 'EN_COURS'])
            .eq('type_paiement_soignant', 'BULLETIN_PAIE')
            .lt('debut_le', bornes.fin.toISOString())
            .gt('fin_le', bornes.debut.toISOString())
            .order('debut_le', { ascending: true }),
          supabase.rpc('fn_mes_soignants_etablissement'),
        ]);
        if (missionsResult.error) throw missionsResult.error;
        if (soignantsResult.error) throw soignantsResult.error;

        const missionsSources = (missionsResult.data ?? []) as any[];
        const creneaux = await chargerCreneauxMissionsPagines(
          missionsSources.map((mission) => mission.id),
          { exclurePauses: false },
        );
        const missionsPeriode = construireExportPaiePeriode(missionsSources, creneaux, a, m);

        const sgMap: Record<string, any> = {};
        if (Array.isArray(soignantsResult.data)) {
          for (const s of soignantsResult.data) sgMap[s.id] = s;
        }

        // Repli RLS explicite lorsque le RPC ne renvoie aucun profil.
        if (Object.keys(sgMap).length === 0 && missionsPeriode.length > 0) {
          const sgIds = [...new Set(missionsPeriode.map((mission: any) => mission.soignant_assigne_id).filter(Boolean))];
          const sgDirectResult = await supabase
            .from('soignants')
            .select('id, prenom, nom, profession, score_fiabilite, numero_rpps')
            .in('id', sgIds);
          if (sgDirectResult.error) throw sgDirectResult.error;
          for (const s of sgDirectResult.data ?? []) sgMap[s.id] = s;
        }

        const profilManquant = missionsPeriode.find((mission: any) => (
          !mission.soignant_assigne_id || !sgMap[mission.soignant_assigne_id]
        ));
        if (profilManquant) {
          throw new Error(`Le profil du soignant de la mission « ${profilManquant.intitule || profilManquant.id} » est indisponible.`);
        }

        if (!actif) return;
        setSoignantMap(sgMap);
        setMissions(missionsPeriode);
      } catch (error: any) {
        if (!actif) return;
        setErreurChargement(error?.message || 'Les données de paie ne peuvent pas être vérifiées.');
      } finally {
        if (actif) setLoading(false);
      }
    };
    void load();
    return () => { actif = false; };
  }, [user, etablissementId, mois, annee, reloadKey]);

  const handleExport = async (fmt: FormatExport) => {
    if (!user || missions.length === 0) return;
    setExporting(fmt);
    try {
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

      const auditResult = await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'EXPORT_RH_PAIE',
        p_type_ressource: 'etablissement', p_id_ressource: etablissementId, p_cle_s3: null,
        p_details: { logiciel: fmt, mois: Number(mois), annee: Number(annee), nb_missions: missions.length },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      if (auditResult.error) throw auditResult.error;

      await downloadCSV(content, filename);
      afficherNotification({ type: 'succes', message: `✅ Export ${fmt} généré — ${missions.length} mission${missions.length > 1 ? 's' : ''}` });
    } catch (error: any) {
      afficherNotification({ type: 'erreur', message: error?.message || `L'export ${fmt} n'a pas pu être généré.` });
    } finally {
      setExporting(null);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  if (erreurChargement) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="card-base border-destructive/30 bg-destructive/5" role="alert">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-destructive mt-0.5 shrink-0" />
            <div>
              <h1 className="font-semibold text-foreground">Export de paie bloqué</h1>
              <p className="text-sm text-muted-foreground mt-1">{erreurChargement}</p>
              <p className="text-xs text-muted-foreground mt-1">Aucun fichier n'est généré tant que les créneaux, validations et profils ne sont pas tous vérifiables.</p>
              <div className="mt-4 flex flex-wrap gap-2">
                <Button onClick={() => navigate('/etablissement/presences?tab=alertes')}>Voir les présences à régulariser</Button>
                <Button variant="outline" onClick={() => setReloadKey((valeur) => valeur + 1)}>Réessayer</Button>
              </div>
            </div>
          </div>
        </div>
      </LayoutApp>
    );
  }

  const moisLabel = formatParis(`${annee}-${mois.padStart(2, '0')}-01T12:00:00`, 'MMMM yyyy');

  const FORMATS: { id: FormatExport; label: string; desc: string }[] = [
    { id: 'Standard', label: 'Standard (CSV)', desc: 'Nom, Prénom, RPPS, heures, majorations, IFM/ICP et brut à transmettre au moteur de paie' },
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
                  <SelectItem key={i + 1} value={String(i + 1)}>{formatParis(`2026-${String(i + 1).padStart(2, '0')}-01T12:00:00`, 'MMMM')}</SelectItem>
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
              </tr>
            </thead>
            <tbody>
              {missions.map((m) => {
                const sg = soignantMap[m.soignant_assigne_id];
                const brut = Number(m.total_brut) || 0;
                return (
                  <tr key={m.id} className="border-b border-border/50 hover:bg-muted/20 cursor-pointer" onClick={() => navigate(`/etablissement/presences/mission/${m.id}`)}>
                    <td className="py-2 px-3 text-xs font-medium">{sg?.prenom && sg?.nom ? `${sg.prenom} ${sg.nom}` : 'Soignant inconnu'}</td>
                    <td className="py-2 px-3 text-xs text-muted-foreground">{m.intitule}</td>
                    <td className="py-2 px-3 text-xs text-muted-foreground whitespace-nowrap space-y-1">
                      {m.creneaux_export.map((creneau) => (
                        <div key={`${creneau.debut}-${creneau.fin}`}>
                          {formatParis(creneau.debut, 'dd/MM/yyyy HH:mm')} → {formatParis(creneau.fin, 'dd/MM/yyyy HH:mm')}
                          <span className="ml-1 text-[10px]">({creneau.duree_heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} h)</span>
                        </div>
                      ))}
                      <div className="text-[10px] text-primary">
                        {m.planning_source === 'EFFECTIF' ? 'Pointages effectifs validés' : 'Planning prévisionnel validé'}
                      </div>
                    </td>
                    <td className="py-2 px-3 text-xs text-right">{m.duree_heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })}h</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(Number(m.taux_horaire_base) || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(Number(m.montant_majoration_nuit) || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(Number(m.montant_majoration_dimanche) || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(Number(m.montant_majoration_ferie) || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(Number(m.montant_ifm) || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right">{fmt(Number(m.montant_icp) || 0)}</td>
                    <td className="py-2 px-3 text-xs text-right font-medium">{fmt(brut)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <p className="text-xs text-muted-foreground px-3 py-2">{missions.length} mission{missions.length > 1 ? 's' : ''} salariée{missions.length > 1 ? 's' : ''} · cliquez sur une ligne pour voir le détail des pointages</p>
        </div>
      ) : (
        <EmptyState icone={<FileSpreadsheet />} mascotte="empty" titre="Aucune période salariée validée" description={`Aucun créneau validé avec bulletin de paie en ${moisLabel}.`} cta={{ label: 'Publier une mission', onClick: () => navigate('/etablissement/missions/creer') }} />
      )}

      <p className="text-xs text-muted-foreground italic mt-4">
        ⚠️ Simulation à titre indicatif. Les heures proviennent des créneaux exacts validés ; les montants des missions couvrant plusieurs mois sont ventilés au prorata de ces heures. L’export est bloqué si des majorations ne peuvent pas être attribuées avec certitude. Seuls les montants calculés par le moteur de paie font foi.
      </p>
    </LayoutApp>
  );
}
