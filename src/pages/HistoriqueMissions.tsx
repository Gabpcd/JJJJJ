import { useState, useEffect, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { ModalCotisations } from '@/components/ModalCotisations';
import { BoutonNoterMission } from '@/components/BoutonNoterMission';
// Sprint 8 ter-G PR 4 — lazy load wizard litige (code splitting, ~10KB)
const WizardOuvertureLitige = lazy(() =>
  import('@/components/litige/WizardOuvertureLitige').then((m) => ({
    default: m.WizardOuvertureLitige,
  })),
);
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ClipboardList, MessageCircle, AlertTriangle, Download, ChevronRight } from 'lucide-react';
import { toast } from 'sonner';
import { telechargerOuPartager } from '@/lib/telechargement';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

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
  const [wizardLitige, setWizardLitige] = useState<{ id: string; intitule: string } | null>(null);

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

  const exporterCSV = async () => {
    if (filtered.length === 0) { toast('Aucune mission à exporter pour cette période.', { icon: 'ℹ️' }); return; }
    const header = 'Date,Mission,Établissement,Heures,Montant net\n';
    const rows = filtered.map(m => {
      const net = m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);
      return `${format(new Date(m.debut_le), 'dd/MM/yyyy')},${m.intitule},${m.etablissements?.nom || ''},${m.duree_heures || 0},${net.toFixed(2)}`;
    }).join('\n');
    await telechargerOuPartager(header + rows, `historique-missions-${new Date().toISOString().slice(0, 10)}.csv`, 'text/csv');
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
        <BoutonY2K variant="secondary" size="sm" onClick={exporterCSV} className="gap-1.5">
          <Download className="h-4 w-4" /> Exporter CSV
        </BoutonY2K>
      </div>

      {(() => {
        const colonnes: ColonneTableau<any>[] = [
          { cle: 'mission', titre: 'Mission' },
          { cle: 'etab', titre: 'Établissement' },
          { cle: 'date', titre: 'Date' },
          { cle: 'heures', titre: 'Heures', align: 'right' },
          { cle: 'net', titre: 'Net estimé', align: 'right' },
          { cle: 'actions', titre: '', align: 'right', largeur: 'w-32' },
        ];

        const netDe = (m: any) => m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);

        return (
          <TableOuCartes
            colonnes={colonnes}
            donnees={filtered}
            getId={(m: any) => m.id}
            etatVide={<EmptyState icone={<ClipboardList />} mascotte="empty" titre="Aucune mission terminée" description="Vos missions terminées apparaîtront ici." />}
            renduCellule={(m: any, col) => {
              switch (col.cle) {
                case 'mission':
                  return <span className="font-medium text-foreground">{m.intitule}</span>;
                case 'etab':
                  return <span className="text-muted-foreground">{m.etablissements?.nom || '—'}</span>;
                case 'date':
                  return <span className="text-xs text-muted-foreground">{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</span>;
                case 'heures':
                  return <span className="text-sm">{m.duree_heures}h</span>;
                case 'net':
                  return (
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); setCotisationsMissionId(m.id); }}
                      className="font-semibold text-primary hover:underline"
                    >
                      {fmt(netDe(m))}
                    </button>
                  );
                case 'actions': {
                  const aLitige = litiges.has(m.id);
                  return (
                    <div className="flex items-center justify-end gap-1">
                      {aLitige && <span className="text-[10px] text-destructive font-medium">⚠️ Litige</span>}
                      <BoutonY2K size="sm" variant="secondary" className="h-8 text-xs" onClick={(e) => { e.stopPropagation(); navigate(`/soignant/missions/${m.id}`); }}>
                        Voir
                      </BoutonY2K>
                    </div>
                  );
                }
                default:
                  return null;
              }
            }}
            renduCarte={(m: any) => {
              const presence = m.presences?.[0];
              const heuresReelles = presence?.pointage_arrivee_le && presence?.pointage_depart_le
                ? ((new Date(presence.pointage_depart_le).getTime() - new Date(presence.pointage_arrivee_le).getTime()) / 3600000).toFixed(1)
                : null;
              const aLitige = litiges.has(m.id);
              return (
                <div className="space-y-3">
                  <div className="flex items-start justify-between gap-3">
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
                    <div className="text-right shrink-0">
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); setCotisationsMissionId(m.id); }}
                        className="font-bold text-primary text-sm hover:underline"
                      >
                        {fmt(netDe(m))}
                      </button>
                      <p className="text-[10px] text-muted-foreground">{m.duree_heures}h</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 pt-3 border-t border-border flex-wrap">
                    <BoutonY2K
                      size="sm"
                      variant="primary"
                      className="gap-1.5 text-xs min-h-[44px]"
                      onClick={(e) => { e.stopPropagation(); navigate(`/soignant/missions/${m.id}`); }}
                    >
                      Voir <ChevronRight className="h-3.5 w-3.5" />
                    </BoutonY2K>
                    <BoutonNoterMission
                      missionId={m.id}
                      sens="SOIGNANT_VERS_ETAB"
                      missionIntitule={m.intitule}
                      variant="secondary"
                    />
                    <BoutonY2K variant="ghost" size="sm" className="gap-1.5 text-xs min-h-[44px]" onClick={(e) => { e.stopPropagation(); ouvrirConversation(m.etablissement_id); }}>
                      <MessageCircle className="h-3.5 w-3.5" /> Contacter
                    </BoutonY2K>
                    {!aLitige && (
                      <BoutonY2K
                        variant="ghost"
                        size="sm"
                        className="gap-1.5 text-xs min-h-[44px] text-warning hover:text-warning"
                        onClick={(e) => { e.stopPropagation(); setWizardLitige({ id: m.id, intitule: m.intitule }); }}
                      >
                        <AlertTriangle className="h-3.5 w-3.5" /> Signaler
                      </BoutonY2K>
                    )}
                    {aLitige && (
                      <span className="text-[10px] text-destructive font-medium">⚠️ Litige en cours</span>
                    )}
                  </div>
                </div>
              );
            }}
          />
        );
      })()}

      {missions.length === (page + 1) * PAGE_SIZE && filtered.length > 0 && (
        <button onClick={() => setPage(p => p + 1)} className="btn-secondary w-full mt-4">Charger plus de missions</button>
      )}

      <ModalCotisations missionId={cotisationsMissionId} open={!!cotisationsMissionId} onClose={() => setCotisationsMissionId(null)} />

      {wizardLitige && (
        <Suspense fallback={null}>
          <WizardOuvertureLitige
            missionId={wizardLitige.id}
            missionIntitule={wizardLitige.intitule}
            onClose={() => setWizardLitige(null)}
            onSuccess={() => {
              setLitiges(prev => new Set(prev).add(wizardLitige.id));
            }}
          />
        </Suspense>
      )}
    </>
  );
}
