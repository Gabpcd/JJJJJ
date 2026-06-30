import { usePageTitle } from '@/hooks/usePageTitle';
import { telechargerOuPartagerPdf } from '@/lib/telechargement';
import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { BarChart3, Users, TrendingUp, Download, Loader2, Target, Coins, Calendar, Briefcase, CheckCircle, Activity } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import type jsPDF from 'jspdf';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { AnalyticsContent } from './AnalyticsEtablissement';
import { Progress } from '@/components/ui/progress';

// Coût moyen horaire intérim soignant en France — source : DREES / DGOS, actualisé avril 2025
const COUT_MOYEN_SECTEUR = 28;
const fmtEur = (v: number, decimals = 0) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: decimals }).format(v);

export default function DashboardRH() {
  usePageTitle('Tableau RH');
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const initialTab = searchParams.get('tab') === 'analytics' ? 'analytics' : 'rh';
  const [activeTab, setActiveTab] = useState<'rh' | 'analytics'>(initialTab);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [stats, setStats] = useState<any>(null);
  const [detailMois, setDetailMois] = useState<'prec' | 'courant' | 'previsionnel' | null>(null);

  useEffect(() => {
    if (!user || !etablissementId) return;
    const load = async () => {
      setLoading(true);
      const { data, error } = await supabase.rpc('fn_stats_rh_etablissement' as any);
      if (error) {
        logger.warn('[DashboardRH] RPC error', error);
      } else {
        setStats(data);
      }
      setLoading(false);
    };
    load();
  }, [user, etablissementId]);

  useEffect(() => {
    if (loading || !stats) return;
    const vue = searchParams.get('vue');
    if (!vue) return;
    setTimeout(() => {
      document.getElementById(vue)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 100);
  }, [loading, searchParams, stats]);

  const handleGeneratePDF = async () => {
    if (!stats) return;
    setGenerating(true);
    try {
      const { default: jsPDF } = await import('jspdf');
      const { default: autoTable } = await import('jspdf-autotable');
      const doc = new jsPDF();
      const now = new Date();
      const moisLabel = format(now, 'MMMM yyyy', { locale: fr });

      doc.setFontSize(20);
      doc.setTextColor(23, 162, 184);
      doc.text('Jolene', 14, 20);
      doc.setFontSize(10);
      doc.setTextColor(100);
      doc.text(`Rapport RH — ${moisLabel}`, 14, 28);
      doc.text(`Généré le ${format(now, 'dd/MM/yyyy à HH:mm', { locale: fr })}`, 14, 34);
      doc.setDrawColor(200);
      doc.line(14, 38, 196, 38);

      doc.setFontSize(14);
      doc.setTextColor(0);
      doc.text('Indicateurs', 14, 48);
      doc.setFontSize(10);
      doc.text(`Missions terminées : ${stats.terminees_total} (dont ${stats.terminees_mois_prec} mois précédent)`, 14, 56);
      doc.text(`Coût total terminé : ${fmtEur(stats.cout_total_termine, 2)}`, 14, 62);
      doc.text(`Coût moyen/heure : ${fmtEur(stats.cout_moyen_heure, 2)} (secteur : ${COUT_MOYEN_SECTEUR} €)`, 14, 68);
      doc.text(`Taux de remplissage : ${stats.taux_remplissage}%`, 14, 74);
      doc.text(`Soignants mobilisés : ${stats.soignants_total}`, 14, 80);
      doc.text(`Budget prévisionnel : ${fmtEur(stats.cout_previsionnel_total ?? stats.cout_previsionnel_brut ?? 0, 2)} (${stats.assignees_total} mission${stats.assignees_total > 1 ? 's' : ''} à venir)`, 14, 86);

      if (stats.top_soignants?.length > 0) {
        doc.setFontSize(14);
        doc.text('Top soignants', 14, 100);
        autoTable(doc, {
          startY: 104,
          head: [['Soignant', 'Profession', 'Missions', 'Total facturé', 'Score']],
          body: stats.top_soignants.map((s: any) => [
            s.nom, s.profession, String(s.nb_missions), fmtEur(s.total_facture, 2), String(s.score_fiabilite ?? '-'),
          ]),
          theme: 'striped',
          headStyles: { fillColor: [23, 162, 184] },
          styles: { fontSize: 9 },
        });
      }

      const pageHeight = doc.internal.pageSize.height;
      doc.setFontSize(8);
      doc.setTextColor(150);
      doc.text('Jolene — Rapport généré automatiquement.', 14, pageHeight - 10);
      await telechargerOuPartagerPdf(doc, `rapport_rh_${format(now, 'yyyy-MM')}.pdf`);
      afficherNotification({ type: 'succes', message: '✅ Rapport PDF téléchargé' });
    } catch {
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la génération du PDF' });
    }
    setGenerating(false);
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  if (!stats) return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <EmptyState icone={<BarChart3 />} mascotte="empty" titre="Données indisponibles" description="Impossible de charger les statistiques RH." />
    </LayoutApp>
  );

  const coutTotalMoisPrec = (stats.cout_mois_prec ?? 0) + (stats.commission_mois_prec ?? 0);
  const coutTotalCeMois = (stats.cout_ce_mois ?? 0) + (stats.commission_ce_mois ?? 0);

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <BarChart3 className="h-6 w-6 text-primary" /> Tableau RH
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Coûts de staffing, suivi des soignants et analytics</p>
        </div>
        <button onClick={handleGeneratePDF} disabled={generating} className="btn-primary flex items-center gap-2 text-sm disabled:opacity-50">
          {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
          {generating ? 'Génération…' : 'Rapport (PDF)'}
        </button>
      </div>

      <Tabs
        value={activeTab}
        onValueChange={(v) => {
          setActiveTab(v as 'rh' | 'analytics');
          if (v === 'analytics') setSearchParams({ tab: 'analytics' }, { replace: true });
          else setSearchParams({}, { replace: true });
        }}
      >
        <TabsList className="mb-4 w-full grid grid-cols-2">
          <TabsTrigger value="rh" className="gap-1.5">
            <BarChart3 className="h-4 w-4" /> Statistiques RH
          </TabsTrigger>
          <TabsTrigger value="analytics" className="gap-1.5">
            <Activity className="h-4 w-4" /> Analytics
          </TabsTrigger>
        </TabsList>

        <TabsContent value="rh">
      {/* KPI Row 1 — Financier */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
        <div className={`card-base text-center cursor-pointer hover:shadow-md transition-shadow ${detailMois === 'prec' ? 'ring-2 ring-primary' : ''}`} onClick={() => setDetailMois(detailMois === 'prec' ? null : 'prec')}>
          <Coins className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{fmtEur(coutTotalMoisPrec)}</p>
          <p className="text-xs text-muted-foreground">Coût {stats.mois_precedent || 'mois précédent'}</p>
          {(stats.commission_mois_prec ?? 0) > 0 && (
            <p className="text-[10px] text-muted-foreground">dont {fmtEur(stats.commission_mois_prec)} de commission Jolene</p>
          )}
        </div>
        <div className={`card-base text-center cursor-pointer hover:shadow-md transition-shadow ${detailMois === 'courant' ? 'ring-2 ring-primary' : ''}`} onClick={() => setDetailMois(detailMois === 'courant' ? null : 'courant')}>
          <Coins className="h-5 w-5 text-info mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{fmtEur(coutTotalCeMois)}</p>
          <p className="text-xs text-muted-foreground">Coût {stats.mois_en_cours || 'mois en cours'}</p>
          {(stats.commission_ce_mois ?? 0) > 0 && (
            <p className="text-[10px] text-muted-foreground">dont {fmtEur(stats.commission_ce_mois)} de commission Jolene</p>
          )}
        </div>
        <div className={`card-base text-center cursor-pointer hover:shadow-md transition-shadow ${detailMois === 'previsionnel' ? 'ring-2 ring-primary' : ''}`} onClick={() => setDetailMois(detailMois === 'previsionnel' ? null : 'previsionnel')}>
          <Briefcase className="h-5 w-5 text-warning mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{fmtEur(stats.cout_previsionnel_total ?? stats.cout_previsionnel ?? 0)}</p>
          <p className="text-xs text-muted-foreground">Budget prévisionnel</p>
          <p className="text-[10px] text-muted-foreground">{stats.assignees_total} mission{stats.assignees_total > 1 ? 's' : ''} à venir</p>
          {(stats.cout_previsionnel_brut ?? 0) > 0 && (
            <p className="text-[10px] text-muted-foreground">{fmtEur(stats.cout_previsionnel_brut)} soignants + {fmtEur(stats.commission_previsionnelle ?? 0)} commission</p>
          )}
        </div>
        <div className="card-base text-center">
          <TrendingUp className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{fmtEur(stats.cout_moyen_heure, 2)}</p>
          <p className="text-xs text-muted-foreground">Coût moyen / heure</p>
          <p className="text-[10px] text-muted-foreground">
            Secteur : {COUT_MOYEN_SECTEUR} €
            {stats.cout_moyen_heure > 0 && stats.cout_moyen_heure < COUT_MOYEN_SECTEUR && <span className="text-primary ml-1">✅</span>}
            {stats.cout_moyen_heure >= COUT_MOYEN_SECTEUR && <span className="text-destructive ml-1">⚠️</span>}
          </p>
        </div>
      </div>

      {/* Détail inline missions du mois sélectionné */}
      {detailMois && (() => {
        const isPrev = detailMois === 'previsionnel';
        const detailMissions = detailMois === 'prec' ? stats.missions_mois_prec
          : detailMois === 'courant' ? stats.missions_ce_mois
          : isPrev ? stats.prochaines_missions
          : [];
        const detailTitre = detailMois === 'prec' ? stats.mois_precedent
          : detailMois === 'courant' ? stats.mois_en_cours
          : 'Budget prévisionnel';
        const messageVide = isPrev
          ? 'Aucune mission planifiée'
          : `Aucune mission terminée ${detailMois === 'prec' ? `en ${stats.mois_precedent || 'mois précédent'}` : `en ${stats.mois_en_cours || 'mois en cours'}`}`;

        const missionsConfirmees = isPrev ? (detailMissions || []).filter((m: any) => m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS') : [];
        const missionsOuvertes = isPrev ? (detailMissions || []).filter((m: any) => m.statut === 'OUVERTE') : [];

        const renderMissionRow = (m: any, grise = false) => (
          <button key={m.mission_id} onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)}
            className={`w-full flex items-center justify-between p-3 rounded-lg border border-border hover:bg-muted/30 transition-colors text-left ${grise ? 'opacity-60' : ''}`}>
            <div>
              <p className={`font-medium text-sm ${grise ? 'text-muted-foreground' : 'text-foreground'}`}>{m.intitule}</p>
              <p className="text-xs text-muted-foreground">
                {m.soignant_nom} · {m.soignant_profession} · {Math.round(m.heures || 0)}h
              </p>
            </div>
            <div className="text-right flex items-center gap-2">
              {isPrev && m.statut && (
                <BadgeY2K variant={m.statut === 'ASSIGNEE' ? 'success' : m.statut === 'OUVERTE' ? 'warning' : 'info'}>
                  {m.statut === 'ASSIGNEE' ? '✅ Assignée' : m.statut === 'EN_COURS' ? '▶️ En cours' : '🟠 Ouverte'}
                </BadgeY2K>
              )}
              <div>
                <p className={`font-semibold text-sm ${grise ? 'text-muted-foreground' : 'text-foreground'}`}>{fmtEur(m.total_brut)}</p>
                {m.montant_commission_ttc > 0 && (
                  <p className="text-[10px] text-muted-foreground">+ {fmtEur(m.montant_commission_ttc)} com.</p>
                )}
              </div>
            </div>
          </button>
        );

        return (
          <div className="card-base mb-4">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold text-foreground">Détail — {detailTitre}</h3>
              <button onClick={() => setDetailMois(null)} className="text-xs text-primary hover:underline">Fermer</button>
            </div>
            {isPrev ? (
              <>
                {missionsConfirmees.length > 0 && (
                  <div className="mb-4">
                    <p className="text-sm font-semibold text-foreground mb-2">
                      ✅ Missions confirmées ({missionsConfirmees.length}) — {fmtEur(missionsConfirmees.reduce((s: number, m: any) => s + (m.total_brut || 0), 0))}
                    </p>
                    <div className="space-y-2">{missionsConfirmees.map((m: any) => renderMissionRow(m))}</div>
                  </div>
                )}
                {missionsOuvertes.length > 0 && (
                  <div>
                    <p className="text-sm font-semibold text-warning mb-2">
                      🟠 Missions ouvertes — en attente de soignant ({missionsOuvertes.length})
                    </p>
                    <div className="space-y-2">{missionsOuvertes.map((m: any) => renderMissionRow(m, true))}</div>
                    <p className="text-xs text-muted-foreground mt-2 italic">
                      Le coût des missions ouvertes n'est pas inclus dans le budget prévisionnel car aucun soignant n'est encore assigné.
                    </p>
                  </div>
                )}
                {missionsConfirmees.length === 0 && missionsOuvertes.length === 0 && (
                  <p className="text-sm text-muted-foreground text-center py-4">{messageVide}</p>
                )}
              </>
            ) : detailMissions?.length > 0 ? (
              <div className="space-y-2">
                {detailMissions.map((m: any) => renderMissionRow(m))}
              </div>
            ) : (
              <p className="text-sm text-muted-foreground text-center py-4">{messageVide}</p>
            )}
          </div>
        );
      })()}

      {/* KPI Row 2 — Opérationnel */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <div className="card-base">
          <div className="flex items-center gap-2 mb-2">
            <Target className="h-5 w-5 text-primary" />
            <span className="font-semibold text-foreground">Taux de remplissage</span>
          </div>
          <p className="text-xl sm:text-3xl font-bold text-foreground mb-2">{stats.taux_remplissage}%</p>
          <Progress value={stats.taux_remplissage} className="h-2" />
        </div>
        <div className="card-base cursor-pointer hover:shadow-md transition-shadow" onClick={() => {
          document.getElementById('top-soignants')?.scrollIntoView({ behavior: 'smooth' });
        }}>
          <div className="flex items-center gap-2 mb-2">
            <Users className="h-5 w-5 text-info" />
            <span className="font-semibold text-foreground">Soignants mobilisés</span>
          </div>
          <p className="text-xl sm:text-3xl font-bold text-foreground">{stats.soignants_total}</p>
          <p className="text-xs text-muted-foreground">{stats.soignants_ce_mois} ce mois</p>
        </div>
        <div className="card-base cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions?statut=TERMINEE')}>
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="h-5 w-5 text-success" />
            <span className="font-semibold text-foreground">Missions terminées</span>
          </div>
          <p className="text-xl sm:text-3xl font-bold text-foreground">{stats.terminees_total}</p>
          <p className="text-xs text-muted-foreground">{stats.terminees_mois_prec} en {stats.mois_precedent || 'mois précédent'}</p>
        </div>
      </div>

      {/* Prévision */}
      <div className="card-base mb-6">
        <h3 className="font-semibold text-foreground mb-1 flex items-center gap-2">📈 Prévision</h3>
        <p className="text-sm text-muted-foreground">
          {(stats.cout_previsionnel_total ?? stats.cout_previsionnel ?? 0) > 0 ? (
            <>Budget prévisionnel : <span className="font-bold text-foreground">{fmtEur(stats.cout_previsionnel_total ?? stats.cout_previsionnel)}</span> (<span className="font-bold text-foreground">{fmtEur(stats.cout_previsionnel_brut ?? stats.cout_previsionnel ?? 0)}</span> soignants + <span className="font-bold text-foreground">{fmtEur(stats.commission_previsionnelle ?? 0)}</span> commission Jolene) pour <span className="font-bold text-foreground">{stats.assignees_total}</span> mission{stats.assignees_total > 1 ? 's' : ''} à venir ({stats.heures_prevues ?? 0}h)</>
          ) : (
            <>Aucune mission planifiée.</>
          )}
        </p>
      </div>

      {/* Comparaison secteur */}
      {stats.cout_moyen_heure > 0 && (
        <div className="card-base mb-6">
          <h3 className="font-semibold text-foreground mb-1 flex items-center gap-2">📊 Comparaison secteur</h3>
          <p className="text-sm text-muted-foreground">
            Coût moyen/heure soignant : <span className="font-bold text-foreground">{fmtEur(stats.cout_moyen_heure, 2)}</span> (hors commission) — Moyenne du secteur : <span className="font-bold text-foreground">{fmtEur(COUT_MOYEN_SECTEUR)}</span>
            {stats.cout_moyen_heure < COUT_MOYEN_SECTEUR && <span className="text-primary ml-2">✅ En dessous de la moyenne</span>}
            {stats.cout_moyen_heure >= COUT_MOYEN_SECTEUR && <span className="text-destructive ml-2">⚠️ Au-dessus de la moyenne</span>}
          </p>
        </div>
      )}

      {/* Prochaines missions */}
      {stats.prochaines_missions?.length > 0 && (() => {
        const colonnes: ColonneTableau<any>[] = [
          { cle: 'intitule', titre: 'Mission' },
          { cle: 'soignant', titre: 'Soignant' },
          { cle: 'date', titre: 'Date' },
          { cle: 'brut', titre: 'Total brut', align: 'right' },
          { cle: 'commission', titre: 'Commission', align: 'right' },
          { cle: 'statut', titre: 'Statut' },
        ];
        const badgeStatut = (statut: string) => (
          <BadgeY2K variant={statut === 'ASSIGNEE' ? 'success' : statut === 'OUVERTE' ? 'warning' : 'info'}>
            {statut === 'ASSIGNEE' ? '✅ Assignée' : statut === 'EN_COURS' ? '▶️ En cours' : '🟠 Ouverte'}
          </BadgeY2K>
        );
        return (
          <div className="card-base mb-6">
            <h2 className="text-lg font-bold text-foreground mb-4 flex items-center gap-2">
              <Calendar className="h-5 w-5 text-primary" /> Prochaines missions
            </h2>
            <TableOuCartes
              colonnes={colonnes}
              donnees={stats.prochaines_missions}
              getId={(m: any) => m.mission_id}
              onClickLigne={(m: any) => navigate(`/etablissement/missions/${m.mission_id}`)}
              renduCellule={(m: any, col) => {
                switch (col.cle) {
                  case 'intitule':
                    return <span className="font-medium text-foreground line-clamp-1">{m.intitule}</span>;
                  case 'soignant':
                    return <span className="text-sm text-muted-foreground">{m.soignant_nom || '—'}</span>;
                  case 'date':
                    return <span className="text-xs whitespace-nowrap">{m.debut_le ? new Date(m.debut_le).toLocaleDateString('fr-FR') : '—'}</span>;
                  case 'brut':
                    return <span className="font-medium tabular-nums">{fmtEur(m.total_brut ?? 0)}</span>;
                  case 'commission':
                    return <span className="text-xs tabular-nums">{m.montant_commission_ttc ? fmtEur(m.montant_commission_ttc) : '—'}</span>;
                  case 'statut':
                    return badgeStatut(m.statut);
                  default:
                    return null;
                }
              }}
              renduCarte={(m: any) => (
                <div className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <p className="font-medium text-foreground line-clamp-2 flex-1">{m.intitule}</p>
                    {badgeStatut(m.statut)}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {m.debut_le ? new Date(m.debut_le).toLocaleDateString('fr-FR') : '—'}
                    {m.soignant_nom && <> · {m.soignant_nom}</>}
                  </p>
                  <div className="flex items-center justify-between pt-1">
                    <span className="text-sm font-semibold tabular-nums">{fmtEur(m.total_brut ?? 0)}</span>
                    {m.montant_commission_ttc > 0 && (
                      <span className="text-xs text-muted-foreground tabular-nums">+ {fmtEur(m.montant_commission_ttc)} com.</span>
                    )}
                  </div>
                </div>
              )}
            />
          </div>
        );
      })()}

      {/* Top soignants */}
      <div id="top-soignants" className="card-base mb-6">
        <h2 className="text-lg font-bold text-foreground mb-4 flex items-center gap-2">
          <Users className="h-5 w-5 text-primary" /> Top soignants
        </h2>
        {(() => {
          const colonnes: ColonneTableau<any>[] = [
            { cle: 'rang', titre: '#', largeur: 'w-12' },
            { cle: 'nom', titre: 'Soignant' },
            { cle: 'profession', titre: 'Profession' },
            { cle: 'score', titre: 'Score', align: 'right' },
            { cle: 'note', titre: 'Note', align: 'right' },
            { cle: 'missions', titre: 'Missions', align: 'right' },
            { cle: 'total', titre: 'Total facturé', align: 'right' },
          ];
          const donnees = (stats.top_soignants || []).map((s: any, i: number) => ({ ...s, _rang: i + 1 }));
          return (
            <TableOuCartes
              colonnes={colonnes}
              donnees={donnees}
              getId={(s: any) => s.soignant_id || `rang-${s._rang}`}
              onClickLigne={(s: any) => s.soignant_id && navigate(`/etablissement/soignants/${s.soignant_id}`)}
              etatVide={<EmptyState icone={<Users />} mascotte="empty" titre="Aucun soignant" description="Les statistiques apparaîtront une fois vos premières missions terminées." />}
              renduCellule={(s: any, col) => {
                switch (col.cle) {
                  case 'rang':
                    return <span className="text-lg font-bold text-muted-foreground">#{s._rang}</span>;
                  case 'nom':
                    return <span className="font-medium text-foreground">{s.nom}</span>;
                  case 'profession':
                    return <span className="text-sm text-muted-foreground">{s.profession}</span>;
                  case 'score':
                    return s.score_fiabilite != null
                      ? <span className="text-sm text-primary font-medium tabular-nums">{s.score_fiabilite}</span>
                      : <span className="text-xs text-muted-foreground">—</span>;
                  case 'note':
                    return s.note_moyenne != null && s.note_moyenne > 0
                      ? <span className="text-sm text-warning font-medium tabular-nums">⭐ {s.note_moyenne.toFixed(1)}</span>
                      : <span className="text-xs text-muted-foreground">—</span>;
                  case 'missions':
                    return <span className="font-semibold tabular-nums">{s.nb_missions}</span>;
                  case 'total':
                    return <span className="font-semibold tabular-nums">{fmtEur(s.total_facture, 2)}</span>;
                  default:
                    return null;
                }
              }}
              renduCarte={(s: any) => (
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0">
                    <span className="text-lg font-bold text-muted-foreground w-6 shrink-0">#{s._rang}</span>
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{s.nom}</p>
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-xs text-muted-foreground">{s.profession}</span>
                        {s.score_fiabilite != null && (
                          <span className="text-xs text-primary font-medium">Score : {s.score_fiabilite}</span>
                        )}
                        {s.note_moyenne != null && s.note_moyenne > 0 && (
                          <span className="text-xs text-warning font-medium">⭐ {s.note_moyenne.toFixed(1)}</span>
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <p className="text-sm font-semibold text-foreground">{s.nb_missions} mission{s.nb_missions > 1 ? 's' : ''}</p>
                    <p className="text-xs text-muted-foreground tabular-nums">{fmtEur(s.total_facture, 2)}</p>
                  </div>
                </div>
              )}
            />
          );
        })()}
      </div>
        </TabsContent>

        <TabsContent value="analytics">
          <AnalyticsContent />
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}
