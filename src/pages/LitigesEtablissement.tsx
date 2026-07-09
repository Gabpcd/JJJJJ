import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Scale, PlusCircle, MessageCircle, User, AlertTriangle } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { FilDiscussionLitige } from '@/components/FilDiscussionLitige';
import { ReclamationsContent } from './MesReclamations';
import { TimelineLitige } from '@/components/litige/TimelineLitige';
import { CompteARebours7j } from '@/components/litige/CompteARebours7j';
import { BoutonsActionLitige } from '@/components/litige/BoutonsActionLitige';
import { statutBadgeV2, estResolu } from '@/lib/statutLitige';

export default function LitigesEtablissement() {
  usePageTitle('Litiges & contestations');
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const initialTab = searchParams.get('tab') === 'reclamations' ? 'reclamations' : 'litiges';
  const [activeTab, setActiveTab] = useState<'litiges' | 'reclamations'>(initialTab);
  const { user, etablissementId } = useEtablissementScope();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  // New dispute modal
  const [showNew, setShowNew] = useState(false);
  const [missionsTerminees, setMissionsTerminees] = useState<any[]>([]);
  const [selectedMissionId, setSelectedMissionId] = useState('');
  const [newMotif, setNewMotif] = useState('');
  const [creating, setCreating] = useState(false);

  const charger = async () => {
    if (!user || !etablissementId) return;
    const { data, error } = await supabase.rpc('fn_litiges_etablissement' as any);
    if (error) {
      toast.error('Erreur lors du chargement des litiges.');
      setLoading(false);
      return;
    }
    setLitiges(Array.isArray(data) ? data : []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, etablissementId]);

  const openNewLitige = async () => {
    if (!user || !etablissementId) return;
    const [{ data: missions }, { data: existingLitiges }] = await Promise.all([
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, soignant_assigne_id')
        .eq('etablissement_id', etablissementId)
        .not('soignant_assigne_id', 'is', null)
        .in('statut', ['TERMINEE', 'EN_COURS'])
        .order('fin_le', { ascending: false })
        .limit(50),
      supabase.from('litiges')
        .select('mission_id')
        .eq('etablissement_id', etablissementId),
    ]);
    const litigesMissionIds = new Set((existingLitiges || []).map((l: any) => l.mission_id));
    setMissionsTerminees((missions || []).filter((m: any) => !litigesMissionIds.has(m.id)));
    setSelectedMissionId('');
    setNewMotif('');
    setShowNew(true);
  };

  const creerLitige = async () => {
    if (!selectedMissionId || !newMotif.trim() || !etablissementId) {
      toast.error('Veuillez sélectionner une mission et saisir un motif.');
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
    if (error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    if ((data as any)?.error) { toast.error((data as any).error); return; }
    toast.success('Litige ouvert avec succès.');
    setShowNew(false);
    charger();
  };

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Scale className="h-6 w-6 text-primary" /> Litiges & contestations
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Gérez les litiges mission et vos réclamations générales</p>
      </div>

      <Tabs
        value={activeTab}
        onValueChange={(v) => {
          setActiveTab(v as 'litiges' | 'reclamations');
          if (v === 'reclamations') setSearchParams({ tab: 'reclamations' }, { replace: true });
          else setSearchParams({}, { replace: true });
        }}
      >
        <TabsList className="mb-4 w-full grid grid-cols-2">
          <TabsTrigger value="litiges" className="gap-1.5">
            <Scale className="h-4 w-4" /> Litiges mission
          </TabsTrigger>
          <TabsTrigger value="reclamations" className="gap-1.5">
            <MessageCircle className="h-4 w-4" /> Réclamations générales
          </TabsTrigger>
        </TabsList>

        <TabsContent value="litiges">
      {loading ? <ChargementPage /> : (<>
      <div className="flex items-center justify-between mb-6">
        <div>
          <p className="text-sm text-muted-foreground">Contestations sur vos missions (pointage, paiement, qualité)</p>
        </div>
        <BoutonY2K onClick={openNewLitige} className="gap-1.5">
          <PlusCircle className="h-4 w-4" /> Ouvrir un litige
        </BoutonY2K>
      </div>

      {/* Lot 11 / D10 : registre sobre sur le conflit — pas de mascotte, état
          vide rassurant qui n'invite pas au litige. */}
      {litiges.length === 0 ? (
        <EmptyState
          icone={<Scale />}
          titre="Aucun litige en cours"
          description="Tout est en ordre sur vos missions. Si un désaccord survient, vous pourrez le signaler depuis la mission concernée."
          variant="info"
        />
      ) : (
        <div className="space-y-4">
          {litiges.map((l: any) => {
            const isExpanded = expandedId === l.litige_id;
            const badge = statutBadgeV2(l.statut);
            const showCountdown = l.statut === 'MEDIATION_EN_COURS' && !estResolu(l.statut);
            const litigeFull = {
              id: l.litige_id,
              statut: l.statut,
              motif: l.motif,
              cree_le: l.cree_le,
              accord_soignant: l.accord_soignant,
              accord_etablissement: l.accord_etablissement,
              accord_soignant_le: l.accord_soignant_le,
              accord_etablissement_le: l.accord_etablissement_le,
              soignant_id: l.soignant_id,
              etablissement_id: l.etablissement_id,
              resolution: l.resolution,
              missions: { intitule: l.mission_intitule },
            };
            return (
              <div key={l.litige_id} className="card-base">
                {/* Summary row */}
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <button
                      onClick={() => navigate(`/etablissement/missions/${l.mission_id}`)}
                      className="font-semibold text-sm text-foreground hover:text-primary hover:underline text-left"
                    >
                      {l.mission_intitule || 'Mission'}
                    </button>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      <User className="inline-block h-3 w-3 mr-0.5 align-text-bottom" aria-hidden="true" />{l.soignant_nom} · {l.soignant_profession}
                      {l.mission_debut && ` · ${format(new Date(l.mission_debut), 'd MMM yyyy', { locale: fr })}`}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1 truncate" title={l.motif}>
                      <span className="font-medium">Motif :</span> {l.motif}
                    </p>
                    {l.dernier_message && (
                      <p className="text-xs text-muted-foreground mt-1 truncate flex items-center gap-1" title={l.dernier_message}>
                        <MessageCircle className="h-3 w-3" />
                        {l.dernier_message}
                      </p>
                    )}
                  </div>
                  <div className="flex flex-col items-end gap-2 shrink-0">
                    <Badge variant="outline" className={`text-[10px] ${badge.classes}`}>
                      <badge.icon className="h-3 w-3 mr-1" />
                      {badge.label}
                    </Badge>
                    {showCountdown && <CompteARebours7j creeLe={l.cree_le} />}
                    {l.nb_messages > 0 && (
                      <span className="text-[10px] text-muted-foreground">{l.nb_messages} message{l.nb_messages > 1 ? 's' : ''}</span>
                    )}
                  </div>
                </div>

                {/* Toggle discussion */}
                <div className="mt-3 pt-2 border-t border-border">
                  <button
                    onClick={() => setExpandedId(isExpanded ? null : l.litige_id)}
                    className="text-xs font-medium text-primary hover:underline"
                  >
                    {isExpanded ? '▲ Masquer la discussion' : '▼ Voir le litige'}
                  </button>
                </div>

                {isExpanded && (
                  <div className="mt-3 space-y-3">
                    <TimelineLitige statut={l.statut} />
                    <BoutonsActionLitige litige={litigeFull} role="ETABLISSEMENT" onUpdate={charger} />
                    <FilDiscussionLitige litige={litigeFull} onUpdate={charger} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
      </>)}
        </TabsContent>

        <TabsContent value="reclamations">
          <ReclamationsContent role="ADMIN_ETABLISSEMENT" />
        </TabsContent>
      </Tabs>

      {/* Modal nouveau litige */}
      <DialogResponsive open={showNew} onOpenChange={setShowNew}>
        <DialogResponsiveContent>
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Ouvrir un nouveau litige</DialogResponsiveTitle>
          </DialogResponsiveHeader>
          <DialogResponsiveBody className="space-y-4">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Mission concernée</label>
              {missionsTerminees.length === 0 ? (
                <p className="text-sm text-muted-foreground">Aucune mission éligible (missions sans litige existant)</p>
              ) : (
                <Select value={selectedMissionId} onValueChange={setSelectedMissionId}>
                  <SelectTrigger><SelectValue placeholder="Sélectionner une mission" /></SelectTrigger>
                  <SelectContent>
                    {missionsTerminees.map(m => (
                      <SelectItem key={m.id} value={m.id}>
                        {m.intitule} — {m.debut_le ? format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr }) : ''}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Motif du litige</label>
              <Textarea value={newMotif} onChange={e => setNewMotif(e.target.value)} placeholder="Décrivez le problème rencontré..." rows={4} />
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K variant="ghost" onClick={() => setShowNew(false)}>Annuler</BoutonY2K>
            <BoutonY2K onClick={creerLitige} disabled={creating || !selectedMissionId || !newMotif.trim()}>
              {creating ? 'Création…' : <><AlertTriangle className="inline-block h-4 w-4 mr-1 align-text-bottom" aria-hidden="true" />Ouvrir le litige</>}
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>
    </LayoutApp>
  );
}
