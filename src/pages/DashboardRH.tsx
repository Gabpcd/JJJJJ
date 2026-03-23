import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { BarChart3, Users, TrendingUp, Download, Loader2, Target, DollarSign } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { format, subMonths, startOfMonth, endOfMonth } from 'date-fns';
import { fr } from 'date-fns/locale';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';

const COUT_MOYEN_SECTEUR = 28;

export default function DashboardRH() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [missions, setMissions] = useState<any[]>([]);
  const [allMissions, setAllMissions] = useState<any[]>([]);
  const [soignantMap, setSoignantMap] = useState<Record<string, any>>({});
  const [etabNom, setEtabNom] = useState('');

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      setLoading(true);
      const sixMonthsAgo = subMonths(new Date(), 6).toISOString();

      const [{ data: missionsData }, { data: soignantsData }, { data: allMissionsData }, { data: etabData }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, montant_ifm, montant_icp, soignant_assigne_id, statut, montant_commission_ttc')
          .eq('etablissement_id', user.id)
          .eq('statut', 'TERMINEE')
          .gte('fin_le', sixMonthsAgo)
          .order('fin_le', { ascending: true }),
        supabase.rpc('fn_mes_soignants_etablissement'),
        supabase
          .from('missions')
          .select('id, statut, soignant_assigne_id, debut_le')
          .eq('etablissement_id', user.id)
          .gte('cree_le', sixMonthsAgo),
        supabase.from('etablissements').select('nom').eq('id', user.id).single(),
      ]);

      const sgMap: Record<string, any> = {};
      if (Array.isArray(soignantsData)) {
        for (const s of soignantsData) sgMap[s.id] = s;
      }
      setSoignantMap(sgMap);
      setMissions((missionsData as any[]) || []);
      setAllMissions((allMissionsData as any[]) || []);
      setEtabNom(etabData?.nom || '');
      setLoading(false);
    };
    load();
  }, [user]);

  // Monthly cost data for chart
  const monthlyData = useMemo(() => {
    const months: { label: string; cout: number; soignants: Set<string>; date: Date }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d = subMonths(new Date(), i);
      const start = startOfMonth(d);
      const end = endOfMonth(d);
      const monthMissions = missions.filter(m => {
        const fin = new Date(m.fin_le);
        return fin >= start && fin <= end;
      });
      const soignantIds = new Set(monthMissions.map(m => m.soignant_assigne_id).filter(Boolean));
      months.push({
        label: format(d, 'MMM yy', { locale: fr }),
        cout: monthMissions.reduce((s, m) => s + (m.total_brut || 0), 0),
        soignants: soignantIds,
        date: d,
      });
    }
    return months;
  }, [missions]);

  // Fill rate
  const tauxRemplissage = useMemo(() => {
    if (allMissions.length === 0) return 0;
    const pourvues = allMissions.filter(m => m.soignant_assigne_id && ['ASSIGNEE', 'EN_COURS', 'TERMINEE'].includes(m.statut)).length;
    return Math.round((pourvues / allMissions.length) * 100);
  }, [allMissions]);

  // Top 5 soignants
  const topSoignants = useMemo(() => {
    const counts: Record<string, { count: number; heures: number; brut: number }> = {};
    for (const m of missions) {
      if (!m.soignant_assigne_id) continue;
      if (!counts[m.soignant_assigne_id]) counts[m.soignant_assigne_id] = { count: 0, heures: 0, brut: 0 };
      counts[m.soignant_assigne_id].count++;
      counts[m.soignant_assigne_id].heures += m.duree_heures || 0;
      counts[m.soignant_assigne_id].brut += m.total_brut || 0;
    }
    return Object.entries(counts)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 5)
      .map(([id, stats]) => ({ id, ...stats, sg: soignantMap[id] }));
  }, [missions, soignantMap]);

  // Current month stats
  const currentMonth = useMemo(() => {
    const now = new Date();
    const start = startOfMonth(now);
    const end = endOfMonth(now);
    const cm = missions.filter(m => {
      const fin = new Date(m.fin_le);
      return fin >= start && fin <= end;
    });
    const totalHeures = cm.reduce((s, m) => s + (m.duree_heures || 0), 0);
    const totalBrut = cm.reduce((s, m) => s + (m.total_brut || 0), 0);
    const coutMoyenHeure = totalHeures > 0 ? totalBrut / totalHeures : 0;
    return { missions: cm.length, heures: totalHeures, brut: totalBrut, coutMoyenHeure };
  }, [missions]);

  // Forecast
  const previsionMois = useMemo(() => {
    const now = new Date();
    const jourDansMois = now.getDate();
    const totalJours = endOfMonth(now).getDate();
    if (jourDansMois < 3) return currentMonth.brut;
    return Math.round((currentMonth.brut / jourDansMois) * totalJours);
  }, [currentMonth]);

  const handleGeneratePDF = async () => {
    setGenerating(true);
    try {
      const doc = new jsPDF();
      const now = new Date();
      const moisLabel = format(now, 'MMMM yyyy', { locale: fr });

      // Header
      doc.setFontSize(20);
      doc.setTextColor(23, 162, 184);
      doc.text('Jolene', 14, 20);
      doc.setFontSize(10);
      doc.setTextColor(100);
      doc.text(`Rapport RH mensuel — ${moisLabel}`, 14, 28);
      doc.text(`Établissement : ${etabNom}`, 14, 34);
      doc.text(`Généré le ${format(now, 'dd/MM/yyyy à HH:mm', { locale: fr })}`, 14, 40);

      doc.setDrawColor(200);
      doc.line(14, 44, 196, 44);

      // KPIs
      doc.setFontSize(14);
      doc.setTextColor(0);
      doc.text('Indicateurs du mois', 14, 54);
      doc.setFontSize(10);
      doc.text(`Missions terminées : ${currentMonth.missions}`, 14, 62);
      doc.text(`Heures totales : ${currentMonth.heures.toFixed(1)}h`, 14, 68);
      doc.text(`Coût total : ${currentMonth.brut.toFixed(2)} €`, 14, 74);
      doc.text(`Coût moyen/heure : ${currentMonth.coutMoyenHeure.toFixed(2)} € (secteur : ${COUT_MOYEN_SECTEUR} €)`, 14, 80);
      doc.text(`Taux de remplissage : ${tauxRemplissage}%`, 14, 86);

      // Soignants table
      doc.setFontSize(14);
      doc.text('Soignants utilisés', 14, 100);

      const tableData = topSoignants.map(s => [
        `${s.sg?.prenom || ''} ${s.sg?.nom || ''}`,
        s.sg?.profession || '',
        String(s.count),
        `${s.heures.toFixed(1)}h`,
        `${s.brut.toFixed(2)} €`,
      ]);

      autoTable(doc, {
        startY: 104,
        head: [['Soignant', 'Profession', 'Missions', 'Heures', 'Montant brut']],
        body: tableData,
        theme: 'striped',
        headStyles: { fillColor: [23, 162, 184] },
        styles: { fontSize: 9 },
      });

      // Cost chart (simplified table)
      const finalY = (doc as any).lastAutoTable?.finalY || 150;
      doc.setFontSize(14);
      doc.text('Coût staffing — 6 derniers mois', 14, finalY + 14);

      autoTable(doc, {
        startY: finalY + 18,
        head: [['Mois', 'Coût total', 'Soignants']],
        body: monthlyData.map(m => [m.label, `${m.cout.toFixed(2)} €`, String(m.soignants.size)]),
        theme: 'striped',
        headStyles: { fillColor: [23, 162, 184] },
        styles: { fontSize: 9 },
      });

      // Footer
      const pageHeight = doc.internal.pageSize.height;
      doc.setFontSize(8);
      doc.setTextColor(150);
      doc.text('Jolene — Rapport généré automatiquement. Données à titre indicatif.', 14, pageHeight - 10);

      doc.save(`rapport_rh_${format(now, 'yyyy-MM')}.pdf`);
      afficherNotification({ type: 'succes', message: '✅ Rapport PDF généré et téléchargé' });
    } catch {
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la génération du PDF' });
    }
    setGenerating(false);
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  const chartData = monthlyData.map(m => ({ name: m.label, cout: Math.round(m.cout), soignants: m.soignants.size }));

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <BarChart3 className="h-6 w-6 text-primary" /> Gestion RH
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Analyse de vos coûts de staffing et suivi des soignants</p>
        </div>
        <button
          onClick={handleGeneratePDF}
          disabled={generating}
          className="btn-primary flex items-center gap-2 text-sm disabled:opacity-50"
        >
          {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
          {generating ? 'Génération…' : 'Rapport du mois (PDF)'}
        </button>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions?statut=TERMINEE')}>
          <DollarSign className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(currentMonth.brut)}</p>
          <p className="text-xs text-muted-foreground">Coût total ce mois</p>
        </div>
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/pool-urgence')}>
          <Users className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{new Set(missions.filter(m => {
            const fin = new Date(m.fin_le);
            return fin >= startOfMonth(new Date()) && fin <= endOfMonth(new Date());
          }).map(m => m.soignant_assigne_id)).size}</p>
          <p className="text-xs text-muted-foreground">Soignants ce mois</p>
        </div>
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/missions')}>
          <Target className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{tauxRemplissage}%</p>
          <p className="text-xs text-muted-foreground">Taux de remplissage</p>
        </div>
        <div className="card-base text-center cursor-pointer hover:shadow-md transition-shadow" onClick={() => navigate('/etablissement/gestion-rh')}>
          <TrendingUp className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-2xl font-bold text-foreground">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 1 }).format(currentMonth.coutMoyenHeure)}</p>
          <p className="text-xs text-muted-foreground">Coût moyen / heure</p>
        </div>
      </div>

      {/* Forecasts */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className="card-base">
          <h3 className="font-semibold text-foreground mb-1">📈 Prévision</h3>
          <p className="text-sm text-muted-foreground">
            À ce rythme, votre budget staffing ce mois sera de <span className="font-bold text-foreground">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(previsionMois)}</span>
          </p>
        </div>
        <div className="card-base">
          <h3 className="font-semibold text-foreground mb-1">📊 Comparaison secteur</h3>
          <p className="text-sm text-muted-foreground">
            Votre coût moyen/heure : <span className="font-bold text-foreground">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(currentMonth.coutMoyenHeure)}</span> — Moyenne du secteur : <span className="font-bold text-foreground">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(COUT_MOYEN_SECTEUR)}</span>
            {currentMonth.coutMoyenHeure > 0 && currentMonth.coutMoyenHeure < COUT_MOYEN_SECTEUR && (
              <span className="text-xs text-primary ml-1">✅ En dessous de la moyenne</span>
            )}
            {currentMonth.coutMoyenHeure >= COUT_MOYEN_SECTEUR && (
              <span className="text-xs text-destructive ml-1">⚠️ Au-dessus de la moyenne</span>
            )}
          </p>
        </div>
      </div>

      {/* Chart */}
      <div className="card-base mb-6">
        <h2 className="text-lg font-bold text-foreground mb-4">Coût total staffing — 6 derniers mois</h2>
        {chartData.some(d => d.cout > 0) ? (
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
              <XAxis dataKey="name" className="text-xs fill-muted-foreground" />
              <YAxis className="text-xs fill-muted-foreground" />
              <Tooltip
                contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))', borderRadius: '8px' }}
                labelStyle={{ color: 'hsl(var(--foreground))' }}
                formatter={(value: number) => [new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(value), 'Coût']}
              />
              <Bar dataKey="cout" fill="hsl(var(--primary))" radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <EtatVide icone={BarChart3} titre="Pas encore de données" sousTitre="Les coûts apparaîtront une fois vos premières missions terminées." />
        )}
      </div>

      {/* Soignants par mois chart */}
      <div className="card-base mb-6">
        <h2 className="text-lg font-bold text-foreground mb-4">Soignants différents par mois</h2>
        {chartData.some(d => d.soignants > 0) ? (
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
              <XAxis dataKey="name" className="text-xs fill-muted-foreground" />
              <YAxis className="text-xs fill-muted-foreground" allowDecimals={false} />
              <Tooltip
                contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))', borderRadius: '8px' }}
                formatter={(value: number) => [value, 'Soignants']}
              />
              <Bar dataKey="soignants" fill="hsl(var(--accent))" radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        ) : null}
      </div>

      {/* Top 5 soignants */}
      <div className="card-base mb-6">
        <h2 className="text-lg font-bold text-foreground mb-4">Top 5 soignants les plus sollicités</h2>
        {topSoignants.length > 0 ? (
          <div className="space-y-3">
            {topSoignants.map((s, i) => (
              <div key={s.id} className="flex items-center justify-between py-2 border-b border-border/50 last:border-0">
                <div className="flex items-center gap-3">
                  <span className="text-lg font-bold text-muted-foreground w-6">#{i + 1}</span>
                  <div>
                    <p className="text-sm font-medium text-foreground">{s.sg?.prenom} {s.sg?.nom}</p>
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-muted-foreground">{s.sg?.profession}</span>
                      {s.sg?.score_fiabilite != null && (
                        <span className="text-xs text-primary font-medium">Score : {s.sg.score_fiabilite}</span>
                      )}
                      {Array.isArray(s.sg?.specialites) && s.sg.specialites.length > 0 && (
                        <div className="flex gap-1">
                          {(s.sg.specialites as string[]).slice(0, 2).map((sp: string) => (
                            <span key={sp} className="text-[10px] bg-primary/10 text-primary px-1.5 py-0.5 rounded">{sp}</span>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-sm font-semibold text-foreground">{s.count} missions</p>
                  <p className="text-xs text-muted-foreground">{s.heures.toFixed(0)}h — {s.brut.toFixed(0)} €</p>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <EtatVide icone={Users} titre="Aucun soignant" sousTitre="Publiez vos premières missions pour voir vos statistiques." />
        )}
      </div>
    </LayoutApp>
  );
}
