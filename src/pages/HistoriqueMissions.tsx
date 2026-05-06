import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { ModalCotisations } from '@/components/ModalCotisations';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ClipboardList, MessageCircle, AlertTriangle, Download } from 'lucide-react';
import { toast } from 'sonner';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Button } from '@/components/ui/button';

function fmt(v: number) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function HistoriqueMissions() {
  usePageTitle('Historique missions');
  return (
    <LayoutApp role="SOIGNANT">
      <HistoriqueMissionsContent />
    </LayoutApp>
  );
}

export function HistoriqueMissionsContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [missions, setMissions] = useState<any[]>([]);
  const [litiges, setLitiges] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const PAGE_SIZE = 50;
  const [moisFiltre, setMoisFiltre] = useState('TOUS');
  const [cotisationsMissionId, setCotisationsMissionId] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const [{ data: ms }, { data: lits }] = await Promise.all([
        supabase.from('missions').select(`
          id, intitule, service, debut_le, fin_le, duree_heures,
          taux_horaire_base, net_a_payer, net_estime, total_brut, statut, etablissement_id,
          presences(pointage_arrivee_le, pointage_depart_le)
        `).eq('soignant_assigne_id', user.id).eq('statut', 'TERMINEE')
          .order('debut_le', { ascending: false }).range(0, (page + 1) * PAGE_SIZE - 1),
        supabase.from('litiges').select('mission_id').eq('soignant_id', user.id),
      ]);
      const enriched = ms ? await enrichirEtablissements(ms as any) : [];
      if (page === 0) setMissions(enriched);
      else setMissions(prev => [...prev, ...enriched]);
      setLitiges(new Set((lits || []).map((l: any) => l.mission_id)));
      setLoading(false);
    };
    load();
  }, [user, page]);

  const moisDisponibles = useMemo(() => {
    const set = new Set<string>();
    missions.forEach(m => {
      if (typeof m.debut_le === 'string' && m.debut_le.length >= 7) {
        set.add(m.debut_le.substring(0, 7));
      }
    });
    return Array.from(set).sort().reverse();
  }, [missions]);

  const filtered = useMemo(() => {
    if (moisFiltre === 'TOUS') return missions;
    return missions.filter(m => m.debut_le.startsWith(moisFiltre));
  }, [missions, moisFiltre]);

  const exporterCSV = () => {
    const header = 'Date,Mission,Établissement,Heures,Montant net\n';
    const rows = filtered.map(m => {
      const net = m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);
      return `${format(new Date(m.debut_le), 'dd/MM/yyyy')},${m.intitule},${m.etablissements?.nom || ''},${m.duree_heures || 0},${net.toFixed(2)}`;
    }).join('\n');
    const blob = new Blob([header + rows], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `historique-missions-${new Date().toISOString().slice(0, 10)}.csv`; a.click();
    URL.revokeObjectURL(url);
  };

  const ouvrirConversation = async (etablissementId: string) => {
    try {
      const { data } = await supabase.rpc('fn_user_id_pour_etablissement' as any, { p_etablissement_id: etablissementId });
      if (data) navigate(`/soignant/messagerie?dest=${data}`);
    } catch { toast.error('Impossible d\'ouvrir la conversation.'); }
  };

  if (loading) return <ChargementPage />;

  return (
    <>
      <div className="mb-6">
        <h2 className="text-lg font-bold text-foreground">Historique des missions</h2>
        <p className="text-sm text-muted-foreground mt-1">{missions.length} mission{missions.length > 1 ? 's' : ''} terminée{missions.length > 1 ? 's' : ''}</p>
      </div>

      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Select value={moisFiltre} onValueChange={setMoisFiltre}>
          <SelectTrigger className="w-48"><SelectValue placeholder="Filtrer par mois" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="TOUS">Tous les mois</SelectItem>
            {moisDisponibles.map(m => (
              <SelectItem key={m} value={m}>{format(new Date(m + '-01'), 'MMMM yyyy', { locale: fr })}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button variant="outline" size="sm" onClick={exporterCSV} className="gap-1.5">
          <Download className="h-4 w-4" /> Exporter CSV
        </Button>
      </div>

      {filtered.length > 0 ? (
        <div className="space-y-3">
          {filtered.map(m => {
            const net = m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);
            const presence = m.presences?.[0];
            const heuresReelles = presence?.pointage_arrivee_le && presence?.pointage_depart_le
              ? ((new Date(presence.pointage_depart_le).getTime() - new Date(presence.pointage_arrivee_le).getTime()) / 3600000).toFixed(1)
              : null;
            const aLitige = litiges.has(m.id);

            return (
              <div key={m.id} className="card-base hover:shadow-md transition-shadow">
                <div className="flex items-start justify-between cursor-pointer" onClick={() => navigate(`/soignant/missions/${m.id}`)}>
                  <div className="flex-1 min-w-0">
                    <h3 className="font-semibold text-sm text-foreground truncate">{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-0.5">🏥 {m.etablissements?.nom || '—'}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      📅 {format(new Date(m.debut_le), "d MMM yyyy · HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                    </p>
                    {heuresReelles && (
                      <p className="text-xs text-muted-foreground mt-0.5">⏱️ Heures pointées : {heuresReelles}h</p>
                    )}
                  </div>
                  <div className="text-right shrink-0 ml-3">
                    <p className="font-bold text-primary text-sm cursor-pointer hover:underline" onClick={(e) => { e.stopPropagation(); setCotisationsMissionId(m.id); }}>{fmt(net)}</p>
                    <p className="text-[10px] text-muted-foreground">{m.duree_heures}h</p>
                  </div>
                </div>
                <div className="flex items-center gap-2 mt-3 pt-3 border-t border-border">
                  <Button variant="ghost" size="sm" className="gap-1.5 text-xs h-8" onClick={() => ouvrirConversation(m.etablissement_id)}>
                    <MessageCircle className="h-3.5 w-3.5" /> Contacter
                  </Button>
                  <Button variant="ghost" size="sm" className={`gap-1.5 text-xs h-8 text-warning hover:text-warning ${aLitige ? 'invisible' : ''}`} onClick={() => navigate(`/soignant/missions/${m.id}`)}>
                    <AlertTriangle className="h-3.5 w-3.5" /> Ouvrir un litige
                  </Button>
                  {aLitige && (
                    <span className="text-[10px] text-destructive font-medium">⚠️ Litige en cours</span>
                  )}
                </div>
              </div>
            );
          })}
          {missions.length === (page + 1) * PAGE_SIZE && (
            <button onClick={() => setPage(p => p + 1)} className="btn-secondary w-full mt-4">Charger plus de missions</button>
          )}
        </div>
      ) : (
        <EtatVide icone={ClipboardList} titre="Aucune mission terminée" sousTitre="Vos missions terminées apparaîtront ici." />
      )}

      <ModalCotisations missionId={cotisationsMissionId} open={!!cotisationsMissionId} onClose={() => setCotisationsMissionId(null)} />
    </>
  );
}
