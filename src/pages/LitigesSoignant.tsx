import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Scale, PlusCircle, ChevronRight } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { FilDiscussionLitige } from '@/components/FilDiscussionLitige';
import { TimelineLitige } from '@/components/litige/TimelineLitige';
import { CompteARebours7j } from '@/components/litige/CompteARebours7j';
import { BoutonsActionLitige } from '@/components/litige/BoutonsActionLitige';
import { statutBadgeV2, estResolu } from '@/lib/statutLitige';

type FiltreStatut = 'TOUS' | 'OUVERT' | 'MEDIATION' | 'ACTION_ATTENDUE' | 'RESOLU' | 'FERME';

export default function LitigesSoignant() {
  usePageTitle('Mes litiges');
  return (
    <LayoutApp role="SOIGNANT">
      <LitigesSoignantContent />
    </LayoutApp>
  );
}

export function LitigesSoignantContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState<FiltreStatut>('TOUS');
  const [expandedId, setExpandedId] = useState<string | null>(null);

  // New dispute modal
  const [showNew, setShowNew] = useState(false);
  const [missionsTerminees, setMissionsTerminees] = useState<any[]>([]);
  const [selectedMissionId, setSelectedMissionId] = useState('');
  const [newMotif, setNewMotif] = useState('');
  const [creating, setCreating] = useState(false);

  const charger = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('litiges')
      .select('*, missions(id, intitule, debut_le, fin_le, etablissement_id, etablissements(nom))')
      .eq('soignant_id', user.id)
      .order('cree_le', { ascending: false });
    setLitiges(data || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const filteredLitiges = useMemo(() => {
    if (filtre === 'TOUS') return litiges;
    return litiges.filter(l => statutBadgeV2(l.statut).groupe === filtre || (filtre === 'RESOLU' && (statutBadgeV2(l.statut).groupe === 'RESOLU_ACCORD' || statutBadgeV2(l.statut).groupe === 'RESOLU_DECISION')));
  }, [litiges, filtre]);

  const counts = useMemo(() => ({
    total: litiges.length,
    ouvert: litiges.filter(l => statutBadgeV2(l.statut).groupe === 'OUVERT').length,
    mediation: litiges.filter(l => statutBadgeV2(l.statut).groupe === 'MEDIATION').length,
    actionAttendue: litiges.filter(l => statutBadgeV2(l.statut).groupe === 'ACTION_ATTENDUE').length,
    resolu: litiges.filter(l => statutBadgeV2(l.statut).groupe === 'RESOLU_ACCORD' || statutBadgeV2(l.statut).groupe === 'RESOLU_DECISION').length,
    ferme: litiges.filter(l => statutBadgeV2(l.statut).groupe === 'FERME').length,
  }), [litiges]);

  const openNewLitige = async () => {
    if (!user) return;
    try {
      const [{ data: missions, error: e1 }, { data: existingLitiges, error: e2 }] = await Promise.all([
        supabase.from('missions')
          .select('id, intitule, debut_le, fin_le, etablissement_id, etablissements(nom)')
          .eq('soignant_assigne_id', user.id)
          .in('statut', ['TERMINEE', 'EN_COURS'])
          .order('fin_le', { ascending: false })
          .limit(50),
        supabase.from('litiges')
          .select('mission_id')
          .eq('soignant_id', user.id),
      ]);
      if (e1 || e2) { toast.error('Impossible de charger les missions.'); return; }
      const litigesMissionIds = new Set((existingLitiges || []).map((l: any) => l.mission_id));
      setMissionsTerminees((missions || []).filter((m: any) => !litigesMissionIds.has(m.id)));
      setSelectedMissionId('');
      setNewMotif('');
      setShowNew(true);
    } catch {
      toast.error('Erreur lors du chargement des missions.');
    }
  };

  const creerLitige = async () => {
    if (!selectedMissionId || !newMotif.trim()) {
      toast.error('Sélectionne une mission et saisis un motif.');
      return;
    }
    if (newMotif.trim().length < 10) {
      toast.error('Le motif doit contenir au moins 10 caractères.');
      return;
    }
    setCreating(true);
    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: selectedMissionId,
      p_motif: newMotif.trim(),
    });
    setCreating(false);
    if (error) { toast.error('Une erreur est survenue. Réessaie.'); return; }
    if ((data as any)?.error) { toast.error((data as any).error); return; }
    toast.success('Litige ouvert avec succès.');
    setShowNew(false);
    charger();
  };

  if (loading) return <ChargementPage />;

  return (
    <>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Scale className="h-6 w-6 text-primary" /> Mes litiges
          </h2>
          <p className="text-sm text-muted-foreground mt-1">Suis tes contestations de missions</p>
        </div>
        <BoutonY2K onClick={openNewLitige} className="gap-1.5">
          <PlusCircle className="h-4 w-4" /> Ouvrir un litige
        </BoutonY2K>
      </div>

      {/* Counters */}
      {litiges.length > 0 && (
        <div className="flex gap-2 mb-4 overflow-x-auto pb-1">
          {[
            { id: 'TOUS' as FiltreStatut, label: 'Tous', count: counts.total },
            { id: 'OUVERT' as FiltreStatut, label: 'Ouverts', count: counts.ouvert },
            { id: 'MEDIATION' as FiltreStatut, label: 'Médiation', count: counts.mediation },
            { id: 'ACTION_ATTENDUE' as FiltreStatut, label: 'Revue admin', count: counts.actionAttendue },
            { id: 'RESOLU' as FiltreStatut, label: 'Résolus', count: counts.resolu },
            { id: 'FERME' as FiltreStatut, label: 'Fermés', count: counts.ferme },
          ].filter(f => f.id === 'TOUS' || f.count > 0).map(f => (
            <button
              key={f.id}
              onClick={() => setFiltre(f.id)}
              className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border transition-colors whitespace-nowrap ${
                filtre === f.id
                  ? 'bg-primary text-primary-foreground border-primary'
                  : 'bg-card text-muted-foreground border-border hover:bg-muted/50'
              }`}
            >
              {f.label}
              <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-bold ${
                filtre === f.id ? 'bg-primary-foreground/20' : 'bg-muted'
              }`}>{f.count}</span>
            </button>
          ))}
        </div>
      )}

      {/* Litiges list */}
      {filteredLitiges.length === 0 ? (
        <EmptyState icone={<Scale />} mascotte="happy" titre={filtre === 'TOUS' ? 'Aucun litige' : `Aucun litige ${filtre.toLowerCase()}`} description="Tu n'as aucun litige en cours." variant="success" />
      ) : (
        <div className="space-y-3">
          {filteredLitiges.map(l => {
            const badge = statutBadgeV2(l.statut);
            const isExpanded = expandedId === l.id;
            const mission = l.missions;
            const showCountdown = l.statut === 'MEDIATION_EN_COURS' && !estResolu(l.statut);
            return (
              <div key={l.id} className="card-base overflow-hidden">
                {/* Litige header — always visible, clickable */}
                <div
                  className="flex items-center gap-3 cursor-pointer"
                  onClick={() => setExpandedId(isExpanded ? null : l.id)}
                >
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1 flex-wrap">
                      <Badge variant="outline" className={`text-[10px] ${badge.classes}`}>
                        <badge.icon className="h-3 w-3 mr-1" />
                        {badge.label}
                      </Badge>
                      <span className="text-[10px] text-muted-foreground">
                        {format(new Date(l.cree_le), "d MMM yyyy", { locale: fr })}
                      </span>
                      {showCountdown && <CompteARebours7j creeLe={l.cree_le} />}
                    </div>
                    <p className="text-sm font-semibold text-foreground truncate">
                      {mission?.intitule || 'Mission'}
                    </p>
                    <p className="text-xs text-muted-foreground truncate">
                      🏥 {mission?.etablissements?.nom || '—'}
                      {mission?.debut_le && ` · ${format(new Date(mission.debut_le), 'd MMM yyyy', { locale: fr })}`}
                    </p>
                    <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">
                      Motif : {l.motif}
                    </p>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    {mission?.id && (
                      <button
                        onClick={(e) => { e.stopPropagation(); navigate(`/soignant/missions/${mission.id}`); }}
                        className="text-xs text-primary hover:underline flex items-center gap-0.5"
                        title="Voir la mission"
                      >
                        Détail <ChevronRight className="h-3 w-3" />
                      </button>
                    )}
                    <ChevronRight className={`h-4 w-4 text-muted-foreground transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
                  </div>
                </div>

                {/* Expanded: timeline + actions + discussion thread */}
                {isExpanded && (
                  <div className="border-t border-border mt-3 pt-3 space-y-3">
                    <TimelineLitige statut={l.statut} />
                    <BoutonsActionLitige litige={l} role="SOIGNANT" onUpdate={charger} />
                    <FilDiscussionLitige litige={l} onUpdate={charger} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Modal nouveau litige */}
      <DialogResponsive open={showNew} onOpenChange={setShowNew}>
        <DialogResponsiveContent>
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Ouvrir un nouveau litige</DialogResponsiveTitle>
          </DialogResponsiveHeader>
          <DialogResponsiveBody className="space-y-4">
            <div className="rounded-xl bg-warning/5 border border-warning/20 p-3">
              <p className="text-xs text-warning font-medium">
                ⚠️ Un litige déclenche une procédure de résolution entre toi et l'établissement. Privilégie d'abord la messagerie pour résoudre le problème.
              </p>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Mission concernée</label>
              {missionsTerminees.length === 0 ? (
                <p className="text-sm text-muted-foreground">Aucune mission éligible</p>
              ) : (
                <Select value={selectedMissionId} onValueChange={setSelectedMissionId}>
                  <SelectTrigger><SelectValue placeholder="Sélectionner une mission" /></SelectTrigger>
                  <SelectContent>
                    {missionsTerminees.map(m => (
                      <SelectItem key={m.id} value={m.id}>
                        {m.intitule} — {m.etablissements?.nom || ''} — {m.debut_le ? format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr }) : ''}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Motif du litige</label>
              <Textarea value={newMotif} onChange={e => setNewMotif(e.target.value)} placeholder="Décris le problème rencontré (minimum 10 caractères)..." rows={4} maxLength={1000} />
              <p className="text-[10px] text-muted-foreground mt-1 text-right">{newMotif.length}/1000</p>
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K variant="ghost" onClick={() => setShowNew(false)}>Annuler</BoutonY2K>
            <BoutonY2K onClick={creerLitige} disabled={creating || !selectedMissionId || newMotif.trim().length < 10}>
              {creating ? 'Création…' : '⚠️ Ouvrir le litige'}
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>
    </>
  );
}
