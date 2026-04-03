import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { BarChart3, Users, TrendingUp, Download, Loader2, Target, Coins, Calendar, Briefcase, CheckCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';

const COUT_MOYEN_SECTEUR = 28;
const fmtEur = (v: number, decimals = 0) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: decimals }).format(v);

export default function DashboardRH() {
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [stats, setStats] = useState<any>(null);
  const [detailMois, setDetailMois] = useState<'prec' | 'courant' | null>(null);

  useEffect(() => {
    if (!user || !etablissementId) return;
    const load = async () => {
      setLoading(true);
      const { data, error } = await supabase.rpc('fn_stats_rh_etablissement' as any);
      if (error) {
        console.error('[DashboardRH] RPC error', error);
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
      doc.text(`Budget prévisionnel : ${fmtEur(stats.cout_previsionnel, 2)} (${stats.assignees_total} missions à venir)`, 14, 86);

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
      doc.save(`rapport_rh_${format(now, 'yyyy-MM')}.pdf`);
      afficherNotification({ type: 'succes', message: '✅ Rapport PDF téléchargé' });
    } catch {
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la génération du PDF' });
    }
    setGenerating(false);
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  if (!stats) return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <EtatVide icone={BarChart3} titre="Données indisponibles" sousTitre="Impossible de charger les statistiques RH." />
    </LayoutApp>
  );

  const coutTotalMoisPrec = (stats.cout_mois_prec ?? 0) + (stats.commission_mois_prec ?? 0);
  const coutTotalCeMois = (stats.cout_ce_mois ?? 0) + (stats.commission_ce_mois ?? 0);

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <BarChart3 className="h-6 w-6 text-primary" /> Gestion RH
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Analyse de vos coûts de staffing et suivi des soignants</p>
        </div>
        <button onClick={handleGeneratePDF} disabled={generating} className="btn-primary flex items-center gap-2 text-sm disabled:opacity-50">
          {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
          {generating ? 'Génération…' : 'Rapport (PDF)'}
        </button>
      </div>

      {/* KPI Row 1 — Financier */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions?statut=TERMINEE')}>
          <Coins className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{fmtEur(coutTotalMoisPrec)}</p>
          <p className="text-xs text-muted-foreground">Coût mois précédent</p>
          <p className="text-[10px] text-muted-foreground">{stats.mois_precedent}</p>
          {(stats.commission_mois_prec ?? 0) > 0 && (
            <p className="text-[10px] text-muted-foreground">dont {fmtEur(stats.commission_mois_prec)} de commission Jolene</p>
          )}
        </div>
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions?statut=TERMINEE')}>
          <Coins className="h-5 w-5 text-info mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{fmtEur(coutTotalCeMois)}</p>
          <p className="text-xs text-muted-foreground">Coût ce mois</p>
          <p className="text-[10px] text-muted-foreground">{stats.mois_en_cours}</p>
          {(stats.commission_ce_mois ?? 0) > 0 && (
            <p className="text-[10px] text-muted-foreground">dont {fmtEur(stats.commission_ce_mois)} de commission Jolene</p>
          )}
        </div>
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions?statut=ASSIGNEE')}>
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

      {/* KPI Row 2 — Opérationnel */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <div className="card-base">
          <div className="flex items-center gap-2 mb-2">
            <Target className="h-5 w-5 text-primary" />
            <span className="font-semibold text-foreground">Taux de remplissage</span>
          </div>
          <p className="text-3xl font-bold text-foreground mb-2">{stats.taux_remplissage}%</p>
          <Progress value={stats.taux_remplissage} className="h-2" />
        </div>
        <div className="card-base cursor-pointer hover:shadow-md transition-shadow" onClick={() => {
          document.getElementById('top-soignants')?.scrollIntoView({ behavior: 'smooth' });
        }}>
          <div className="flex items-center gap-2 mb-2">
            <Users className="h-5 w-5 text-info" />
            <span className="font-semibold text-foreground">Soignants mobilisés</span>
          </div>
          <p className="text-3xl font-bold text-foreground">{stats.soignants_total}</p>
          <p className="text-xs text-muted-foreground">{stats.soignants_ce_mois} ce mois</p>
        </div>
        <div className="card-base cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions?statut=TERMINEE')}>
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="h-5 w-5 text-success" />
            <span className="font-semibold text-foreground">Missions terminées</span>
          </div>
          <p className="text-3xl font-bold text-foreground">{stats.terminees_total}</p>
          <p className="text-xs text-muted-foreground">{stats.terminees_mois_prec} le mois précédent</p>
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
      {stats.prochaines_missions?.length > 0 && (
        <div className="card-base mb-6">
          <h2 className="text-lg font-bold text-foreground mb-4 flex items-center gap-2">
            <Calendar className="h-5 w-5 text-primary" /> Prochaines missions
          </h2>
          <div className="space-y-2">
            {stats.prochaines_missions.map((m: any) => (
              <button
                key={m.mission_id}
                onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)}
                className="w-full flex items-center justify-between p-3 rounded-xl border border-border hover:bg-muted/30 transition-colors text-left"
              >
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-foreground truncate">{m.intitule}</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {m.debut_le ? new Date(m.debut_le).toLocaleDateString('fr-FR') : '—'} · {fmtEur(m.total_brut ?? 0)}{m.montant_commission_ttc ? ` + ${fmtEur(m.montant_commission_ttc)} com.` : ''}
                    {m.soignant_nom && <> · {m.soignant_nom}</>}
                  </p>
                </div>
                <Badge variant={m.statut === 'ASSIGNEE' ? 'default' : 'secondary'} className={m.statut === 'OUVERTE' ? 'bg-warning/10 text-warning border-warning/30' : ''}>
                  {m.statut === 'ASSIGNEE' ? '✅ Assignée' : m.statut === 'EN_COURS' ? '▶️ En cours' : '🟠 Ouverte'}
                </Badge>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Top soignants */}
      <div id="top-soignants" className="card-base mb-6">
        <h2 className="text-lg font-bold text-foreground mb-4 flex items-center gap-2">
          <Users className="h-5 w-5 text-primary" /> Top soignants
        </h2>
        {stats.top_soignants?.length > 0 ? (
          <div className="space-y-3">
            {stats.top_soignants.map((s: any, i: number) => (
              <button key={i} onClick={() => s.soignant_id && navigate(`/etablissement/soignants/${s.soignant_id}`)} className="w-full flex items-center justify-between py-2 border-b border-border/50 last:border-0 hover:bg-muted/30 rounded-lg transition-colors text-left">
                <div className="flex items-center gap-3">
                  <span className="text-lg font-bold text-muted-foreground w-6">#{i + 1}</span>
                  <div>
                    <p className="text-sm font-medium text-foreground">{s.nom}</p>
                    <div className="flex items-center gap-2">
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
                <div className="text-right">
                  <p className="text-sm font-semibold text-foreground">{s.nb_missions} mission{s.nb_missions > 1 ? 's' : ''}</p>
                  <p className="text-xs text-muted-foreground">{fmtEur(s.total_facture, 2)}</p>
                </div>
              </button>
            ))}
          </div>
        ) : (
          <EtatVide icone={Users} titre="Aucun soignant" sousTitre="Les statistiques apparaîtront une fois vos premières missions terminées." />
        )}
      </div>
    </LayoutApp>
  );
}
