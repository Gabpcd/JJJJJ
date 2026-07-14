import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { BoutonFavori } from '@/components/BoutonFavori';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { JaugeScoreFiabilite } from '@/components/JaugeScoreFiabilite';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EmptyState } from '@/components/ui/EmptyState';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Slider } from '@/components/ui/slider';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
} from '@/components/ui/DialogResponsive';
import { Flame, Users, UserCheck, Trophy, Bell, BellRing, Send, MapPin, Clock, MessageCircle, Plus, ChevronDown } from 'lucide-react';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { PROFESSIONS, BADGES_STATUT } from '@/lib/constantes';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { logger } from '@/lib/logger';
import { cn } from '@/lib/utils';
import { usePageTitle } from '@/hooks/usePageTitle';

interface SoignantPool {
  id: string;
  soignant_id: string;
  prenom: string;
  nom: string;
  profession: string;
  score_fiabilite: number;
  pool_urgence_rayon_km: number;
  distance_km: number | null;
  missions_urgence_terminees: number;
  en_mission_maintenant: boolean;
  derniere_mission_chez_nous: string | null;
  bio: string | null;
  avatar_url: string | null;
  est_favori: boolean;
}

interface HistoriqueUrgence {
  id: string;
  intitule: string;
  debut_le: string;
  statut: string;
  soignant_prenom: string | null;
  soignant_nom: string | null;
  cree_le: string;
  soignant_assigne_id: string | null;
}

interface MissionOuverte {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  taux_horaire_base: number | null;
  profession_requise: string;
  mode_attribution: string | null;
  type_contrat_recherche: string | null;
  etablissements: { nom: string } | null;
}

function PoolLayout({ isAdmin, children }: { isAdmin: boolean; children: React.ReactNode }) {
  return isAdmin
    ? <LayoutAdmin>{children}</LayoutAdmin>
    : <LayoutApp role="ADMIN_ETABLISSEMENT">{children}</LayoutApp>;
}

export default function PoolUrgenceEtablissement({ isAdmin = false }: { isAdmin?: boolean }) {
  usePageTitle(isAdmin ? "Admin · Pool d'urgence" : "Pool d'urgence");
  const { user, etablissementId: scopedEtablissementId } = useEtablissementScope();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [soignants, setSoignants] = useState<SoignantPool[]>([]);
  const [historique, setHistorique] = useState<HistoriqueUrgence[]>([]);
  const [loading, setLoading] = useState(true);
  const [alerterTousOpen, setAlerterTousOpen] = useState(false);
  const [etablissementsAdmin, setEtablissementsAdmin] = useState<Array<{ id: string; nom: string }>>([]);
  const [selectedEtablissementId, setSelectedEtablissementId] = useState('');

  // Mission proposal modal
  const [proposerModalOpen, setProposerModalOpen] = useState(false);
  const [proposerSoignant, setProposerSoignant] = useState<SoignantPool | null>(null);
  const [missionsOuvertes, setMissionsOuvertes] = useState<MissionOuverte[]>([]);
  const [loadingMissions, setLoadingMissions] = useState(false);
  const [assigningMissionId, setAssigningMissionId] = useState<string | null>(null);

  // Filters
  const [filtreProfession, setFiltreProfession] = useState<string>('TOUTES');
  const [filtreDispo, setFiltreDispo] = useState(false);
  const [filtreRayonMax, setFiltreRayonMax] = useState(50);
  const [filtreScoreMin, setFiltreScoreMin] = useState(0);
  const [filtreHistorique, setFiltreHistorique] = useState<'TOUT' | 'POURVUES_MOIS'>('TOUT');
  const [historiqueOuvert, setHistoriqueOuvert] = useState(false);
  const [kpiUrgencesMois, setKpiUrgencesMois] = useState<number | null>(null);
  const chargementPoolRef = useRef(0);

  const etablissementId = isAdmin ? selectedEtablissementId : scopedEtablissementId || '';

  useEffect(() => {
    if (!isAdmin) return;

    const loadEtablissements = async () => {
      const { data, error } = await supabase
        .from('etablissements')
        .select('id, nom')
        .is('supprime_le', null)
        .order('nom', { ascending: true });

      if (error) { toast.error('Erreur lors du chargement des établissements.'); return; }
      const etablissements = (data ?? []) as Array<{ id: string; nom: string }>;
      setEtablissementsAdmin(etablissements);
      setSelectedEtablissementId((current) => current || etablissements[0]?.id || '');
      if (etablissements.length === 0) setLoading(false);
    };

    loadEtablissements();
  }, [isAdmin]);

  useEffect(() => {
    if (searchParams.get('disponibles') === '1') setFiltreDispo(true);
    if (searchParams.get('historique') === 'pourvues_mois') {
      setFiltreHistorique('POURVUES_MOIS');
      setHistoriqueOuvert(true);
    }
  }, [searchParams]);

  const loadData = useCallback(async () => {
    const numeroChargement = ++chargementPoolRef.current;
    setLoading(true);
    setSoignants([]);
    setHistorique([]);
    setKpiUrgencesMois(null);
    const debutMois = new Date();
    debutMois.setDate(1);
    debutMois.setHours(0, 0, 0, 0);
    const debutMoisSuivant = new Date(debutMois);
    debutMoisSuivant.setMonth(debutMoisSuivant.getMonth() + 1);

    const [poolRes, histRes, kpiRes] = await Promise.all([
      supabase.rpc('fn_pool_urgence_etablissement' as any, { p_etablissement_id: etablissementId }),
      supabase
        .from('missions')
        .select('id, intitule, debut_le, statut, cree_le, soignant_assigne_id, soignants(prenom, nom)')
        .eq('etablissement_id', etablissementId)
        .eq('est_urgente', true)
        .order('debut_le', { ascending: false })
        .limit(100),
      supabase
        .from('missions')
        .select('id', { count: 'exact', head: true })
        .eq('etablissement_id', etablissementId)
        .eq('est_urgente', true)
        .not('soignant_assigne_id', 'is', null)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .gte('debut_le', debutMois.toISOString())
        .lt('debut_le', debutMoisSuivant.toISOString()),
    ]);
    if (numeroChargement !== chargementPoolRef.current) return;
    if (poolRes.error || histRes.error || kpiRes.error) {
      toast.error("Le pool d'urgence n'a pas pu être chargé complètement.");
    }
    if (poolRes.data) setSoignants(poolRes.data as any);
    if (histRes.data) {
      setHistorique(
        (histRes.data as any[]).map((m: any) => ({
          id: m.id,
          intitule: m.intitule,
          debut_le: m.debut_le,
          statut: m.statut,
          soignant_prenom: m.soignants?.prenom || null,
          soignant_nom: m.soignants?.nom || null,
          cree_le: m.cree_le,
          soignant_assigne_id: m.soignant_assigne_id,
        }))
      );
    }
    setKpiUrgencesMois(kpiRes.error ? null : (kpiRes.count ?? 0));
    setLoading(false);
  }, [etablissementId]);

  useEffect(() => {
    if (!etablissementId) {
      chargementPoolRef.current += 1;
      setSoignants([]);
      setHistorique([]);
      setKpiUrgencesMois(null);
      setLoading(false);
      return;
    }
    void loadData();
    return () => { chargementPoolRef.current += 1; };
  }, [etablissementId, loadData]);

  const filtered = useMemo(() => {
    return soignants
      .filter((s) => {
        if (filtreProfession !== 'TOUTES' && s.profession !== filtreProfession) return false;
        if (filtreDispo && s.en_mission_maintenant) return false;
        if (s.distance_km !== null && s.distance_km > filtreRayonMax) return false;
        if (s.score_fiabilite < filtreScoreMin) return false;
        return true;
      })
      // Disponibles d'abord (tri stable : l'ordre d'origine est conservé au sein de chaque groupe)
      .sort((a, b) => Number(a.en_mission_maintenant) - Number(b.en_mission_maintenant));
  }, [soignants, filtreProfession, filtreDispo, filtreRayonMax, filtreScoreMin]);

  const kpiTotal = soignants.length;
  const kpiDisponibles = soignants.filter((s) => !s.en_mission_maintenant).length;
  // File de travail : les urgences encore à pourvoir en tête de page, le reste en historique replié.
  const urgencesAPourvoir = useMemo(
    () =>
      historique
        .filter((h) => h.statut === 'OUVERTE' && !h.soignant_assigne_id)
        .sort((a, b) => a.debut_le.localeCompare(b.debut_le)),
    [historique]
  );

  const historiqueClos = useMemo(
    () => historique.filter((h) => !(h.statut === 'OUVERTE' && !h.soignant_assigne_id)),
    [historique]
  );

  const historiqueAffiche = useMemo(() => {
    if (filtreHistorique !== 'POURVUES_MOIS') return historiqueClos;
    const now = new Date();
    return historiqueClos.filter((h) => {
      const d = new Date(h.debut_le);
      return Boolean(h.soignant_assigne_id)
        && ['ASSIGNEE', 'EN_COURS', 'TERMINEE'].includes(h.statut)
        && d.getMonth() === now.getMonth()
        && d.getFullYear() === now.getFullYear();
    });
  }, [historiqueClos, filtreHistorique]);

  const alerterSoignant = async (s: SoignantPool) => {
    const { error } = await supabase.functions.invoke('send-push', {
      body: {
        destinataire_id: s.soignant_id,
        titre: '🚨 Mission urgente disponible',
        corps: 'Un établissement a besoin de vous en urgence.',
        lien: '/soignant/missions',
      },
    });
    if (error) toast.error("Erreur lors de l'envoi de l'alerte");
    else toast.success(`🚨 Alerte envoyée à ${s.prenom} ${s.nom}`);
  };

  const ouvrirConversation = async (soignantId: string) => {
    const base = isAdmin ? '/admin/messagerie' : '/etablissement/messagerie';
    const { data, error } = isAdmin
      ? await supabase.rpc('fn_obtenir_conversation', {
          p_autre_id: soignantId,
          p_mission_id: null,
        })
      : await supabase.rpc(
          'fn_obtenir_conversation_pool_etablissement' as any,
          {
            p_soignant_id: soignantId,
            p_etablissement_id: etablissementId,
          } as any,
        );
    logger.debug('conversation pool:', { data, error });
    if (error || !data) toast.error("La conversation n'a pas pu être ouverte.");
    else navigate(`${base}?conv=${data}`);
  };

  const alerterTous = async () => {
    setAlerterTousOpen(false);
    const disponibles = filtered.filter(s => !s.en_mission_maintenant);
    let sent = 0;
    for (const s of disponibles) {
      const { error } = await supabase.functions.invoke('send-push', {
        body: { destinataire_id: s.soignant_id, titre: '🚨 Mission urgente', corps: 'Remplacement urgent disponible.', lien: '/soignant/missions' },
      });
      if (!error) sent++;
    }
    toast.success(`🚨 Alerte envoyée à ${sent}/${disponibles.length} soignants`);
  };

  const ouvrirProposerMission = async (s: SoignantPool) => {
    setProposerSoignant(s);
    setProposerModalOpen(true);
    setLoadingMissions(true);

    const { data } = await supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, taux_horaire_base, profession_requise, mode_attribution, type_contrat_recherche, etablissements(nom)')
      .eq('etablissement_id', etablissementId)
      .eq('statut', 'OUVERTE')
      .is('soignant_assigne_id', null)
      .order('debut_le', { ascending: true })
      .limit(20);

    setMissionsOuvertes((data as MissionOuverte[]) || []);
    setLoadingMissions(false);
  };

  const assignerMission = async (mission: MissionOuverte) => {
    if (!proposerSoignant || !user) return;

    const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!UUID_REGEX.test(proposerSoignant.soignant_id)) {
      logger.warn('[PoolUrgence] assignation pool error: soignant_id invalide', proposerSoignant.soignant_id);
      toast.error('Le profil sélectionné est invalide. Actualisez la page puis réessayez.');
      return;
    }

    setAssigningMissionId(mission.id);
    logger.debug('pool: proposing mission to soignant', { mission_id: mission.id, soignant_id: proposerSoignant.soignant_id });

    const { data: proposition, error: candError } = await supabase.rpc('fn_proposer_mission_soignant' as any, {
      p_mission_id: mission.id,
      p_soignant_id: proposerSoignant.soignant_id,
      p_choix_contrat: null,
    });

    if (candError || (proposition as any)?.error) {
      logger.warn('[PoolUrgence] assignation pool error', candError || proposition);
      const message = (proposition as any)?.choix_requis
        ? 'Cette proposition exige de choisir le type de contrat depuis la fiche de la mission.'
        : ((proposition as any)?.message || (proposition as any)?.error || 'Impossible de proposer cette mission. Veuillez réessayer.');
      toast.error(message);
      setAssigningMissionId(null);
      return;
    }

    // La RPC métier crée la notification applicative. L'email est un complément
    // best-effort et ne doit jamais créer une seconde candidature.
    try {
      const { data: session } = await supabase.auth.getSession();
      const token = session?.session?.access_token;
      if (token) {
        const supabaseUrl = SUPABASE_URL;
        fetch(`${supabaseUrl}/functions/v1/send-email`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            type: 'MISSION_PROPOSEE',
            destinataire_id: proposerSoignant.soignant_id,
            data: {
              prenom: proposerSoignant.prenom,
              mission: mission.intitule,
              etablissement: mission.etablissements?.nom || 'Établissement Jolene',
              date: format(new Date(mission.debut_le), 'dd/MM/yyyy', { locale: fr }),
              heure_debut: format(new Date(mission.debut_le), 'HH:mm'),
              heure_fin: format(new Date(mission.fin_le), 'HH:mm'),
              taux_horaire: mission.taux_horaire_base != null ? String(mission.taux_horaire_base) : '',
              mission_id: mission.id,
            },
          }),
        }).catch(err => logger.warn('[PoolUrgence] email send error', err));
      }
    } catch (notifErr) {
      logger.warn('[PoolUrgence] notification error (non-bloquant)', notifErr);
    }

    toast.success(`Mission proposée à ${proposerSoignant.prenom} 📩 — en attente de réponse`);
    setProposerModalOpen(false);
    loadData();
    setAssigningMissionId(null);
  };

  const professions = useMemo(() => {
    const set = new Set(soignants.map((s) => s.profession));
    return Array.from(set);
  }, [soignants]);

  const professionLabel = (code: string) => {
    const found = PROFESSIONS.find((p) => p.valeur === code);
    return found ? found.label : code;
  };

  const statutMissionLabel = (statut: string) => BADGES_STATUT[statut]?.label
    ?? statut.toLocaleLowerCase('fr-FR').replace(/_/g, ' ').replace(/^./, (lettre) => lettre.toLocaleUpperCase('fr-FR'));
  const statutMissionVariant = (statut: string): 'success' | 'warning' | 'error' | 'info' => {
    if (statut === 'TERMINEE') return 'success';
    if (statut === 'OUVERTE' || statut === 'ABSENCE' || statut === 'ANNULEE_PAR_SOIGNANT') return 'error';
    if (statut === 'ASSIGNEE' || statut === 'EN_COURS' || statut === 'LITIGE') return 'warning';
    return 'info';
  };
  const detailMissionPath = (missionId: string) => isAdmin
    ? `/admin/missions/${missionId}`
    : `/etablissement/missions/${missionId}`;

  if (loading) {
    return (
      <PoolLayout isAdmin={isAdmin}>
        <div className="max-w-6xl mx-auto space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {[1, 2, 3].map(i => (
              <div key={i} className="card-base animate-pulse h-24" />
            ))}
          </div>
          <div className="card-base animate-pulse h-64" />
        </div>
      </PoolLayout>
    );
  }

  return (
    <PoolLayout isAdmin={isAdmin}>
      <div className="max-w-6xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Flame className="h-6 w-6 text-destructive" />
            Pool d'urgence
          </h1>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
            {isAdmin && (
              <div className="w-full sm:min-w-[240px] sm:w-auto">
                <Select value={selectedEtablissementId} onValueChange={setSelectedEtablissementId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Choisir un établissement" />
                  </SelectTrigger>
                  <SelectContent>
                    {etablissementsAdmin.map((etablissement) => (
                      <SelectItem key={etablissement.id} value={etablissement.id}>
                        {etablissement.nom}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
            <Button
              variant="destructive"
              onClick={() => setAlerterTousOpen(true)}
              disabled={urgencesAPourvoir.length === 0 || filtered.filter(s => !s.en_mission_maintenant).length === 0}
            >
              <BellRing className="h-4 w-4 mr-1" />
              Alerter tout le pool 🚨
            </Button>
          </div>
        </div>

        {/* Urgences à pourvoir — la raison d'être de la page, affichées en tête */}
        {urgencesAPourvoir.length > 0 && (
          <section aria-label="Urgences à pourvoir" className="card-base border-destructive/40">
            <h2 className="text-base font-semibold text-foreground flex items-center gap-2">
              <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
                {urgencesAPourvoir.length}
              </span>
              Urgences à pourvoir
            </h2>
            <p className="text-xs text-muted-foreground mt-1 mb-3">
              Ces missions urgentes attendent encore un remplaçant. Alertez le pool ou proposez-les à un soignant disponible.
            </p>
            <div className="hidden overflow-x-auto md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Mission</TableHead>
                  <TableHead>Début prévu</TableHead>
                  <TableHead>Créée le</TableHead>
                  <TableHead>Statut</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {urgencesAPourvoir.map((h) => (
                  <TableRow key={h.id} className="cursor-pointer hover:bg-muted/50" onClick={() => navigate(detailMissionPath(h.id))}>
                    <TableCell className="font-medium text-sm">{h.intitule}</TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {format(new Date(h.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })}
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {format(new Date(h.cree_le), 'dd/MM/yyyy HH:mm', { locale: fr })}
                    </TableCell>
                    <TableCell>
                      <BadgeY2K variant="error" size="sm">À pourvoir</BadgeY2K>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            </div>
            <div className="space-y-2 md:hidden">
              {urgencesAPourvoir.map((mission) => (
                <button
                  key={mission.id}
                  type="button"
                  onClick={() => navigate(detailMissionPath(mission.id))}
                  className="w-full rounded-xl border border-destructive/20 p-3 text-left hover:bg-muted/50"
                >
                  <span className="mb-2 flex items-start justify-between gap-2">
                    <span className="text-sm font-semibold text-foreground">{mission.intitule}</span>
                    <BadgeY2K variant="error" size="sm">À pourvoir</BadgeY2K>
                  </span>
                  <span className="block text-xs text-muted-foreground">Début : {format(new Date(mission.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })}</span>
                  <span className="block text-xs text-muted-foreground">Créée : {format(new Date(mission.cree_le), 'dd/MM/yyyy HH:mm', { locale: fr })}</span>
                </button>
              ))}
            </div>
          </section>
        )}

        {/* KPIs */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <CarteKPIY2K
            icone={<Users className="h-4 w-4" />}
            valeur={kpiTotal}
            label="Soignants dans le pool"
            variant="holographic"
          />
          <CarteKPIY2K
            icone={<UserCheck className="h-4 w-4" />}
            valeur={kpiDisponibles}
            label="Disponibles maintenant"
            variant="default"
            onClick={() => {
              setFiltreDispo(true);
              setSearchParams((current) => {
                const next = new URLSearchParams(current);
                next.set('disponibles', '1');
                return next;
              }, { replace: true });
            }}
          />
          <CarteKPIY2K
            icone={<Trophy className="h-4 w-4" />}
            valeur={kpiUrgencesMois ?? '—'}
            label="Urgences pourvues ce mois"
            variant="default"
            onClick={() => {
              setFiltreHistorique('POURVUES_MOIS');
              setHistoriqueOuvert(true);
              setSearchParams({ historique: 'pourvues_mois' }, { replace: true });
              document.getElementById('historique-urgences')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }}
          />
        </div>

        {/* Filters */}
        <div className="card-base">
          <p className="text-sm font-semibold text-foreground mb-3">Filtres</p>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-end">
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Profession</label>
              <Select value={filtreProfession} onValueChange={setFiltreProfession}>
                <SelectTrigger aria-label="Filtrer par profession"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="TOUTES">Toutes</SelectItem>
                  {professions.map((p) => (
                    <SelectItem key={p} value={p}>{professionLabel(p)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">
                Rayon max : <span className="font-bold text-primary">{filtreRayonMax} km</span>
              </label>
              <Slider aria-label="Rayon maximal en kilomètres" value={[filtreRayonMax]} min={5} max={100} step={5} onValueChange={(v) => setFiltreRayonMax(v[0])} />
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">
                Score min : <span className="font-bold text-primary">{filtreScoreMin}</span>
              </label>
              <Slider aria-label="Score de fiabilité minimal" value={[filtreScoreMin]} min={0} max={100} step={5} onValueChange={(v) => setFiltreScoreMin(v[0])} />
            </div>
            <div className="flex items-center gap-2">
              <Switch
                id="filtre-disponibles-pool"
                checked={filtreDispo}
                onCheckedChange={(checked) => {
                  setFiltreDispo(checked);
                  setSearchParams((current) => {
                    const next = new URLSearchParams(current);
                    if (checked) next.set('disponibles', '1');
                    else next.delete('disponibles');
                    return next;
                  }, { replace: true });
                }}
              />
              <label htmlFor="filtre-disponibles-pool" className="text-sm text-foreground">Disponibles uniquement</label>
            </div>
          </div>
        </div>

        {/* Table */}
        {filtered.length === 0 ? (
          <EmptyState
            icone={<Flame />}
            mascotte="empty"
            titre="Aucun soignant dans le pool"
            description="Publiez une mission urgente et les soignants du pool seront notifiés."
            cta={isAdmin
              ? { label: 'Voir toutes les missions', onClick: () => navigate('/admin/missions') }
              : { label: 'Publier une mission urgente', onClick: () => navigate('/etablissement/missions/creer') }}
          />
        ) : (
          <div className="card-base p-0 overflow-hidden">
            <div className="hidden overflow-x-auto md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Soignant</TableHead>
                  <TableHead>Profession</TableHead>
                  <TableHead>Fiabilité</TableHead>
                  <TableHead>Rayon</TableHead>
                  <TableHead>Distance</TableHead>
                  <TableHead>Urgences</TableHead>
                  <TableHead>Disponibilité</TableHead>
                  <TableHead>Dernière mission</TableHead>
                  <TableHead className="hidden lg:table-cell">Bio</TableHead>
                  <TableHead>Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((s) => (
                  <TableRow key={s.soignant_id} className="group">
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <div
                          className="flex items-center gap-2 cursor-pointer hover:opacity-80"
                          onClick={() => navigate(isAdmin ? `/admin/utilisateurs/${s.soignant_id}` : `/etablissement/soignants/${s.soignant_id}`)}
                        >
                          <AvatarDisplay src={s.avatar_url} prenom={s.prenom} nom={s.nom} size={32} rounded="full" />
                          <span className="font-medium text-foreground text-sm underline-offset-2 hover:underline">{s.prenom} {s.nom}</span>
                        </div>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            ouvrirConversation(s.soignant_id);
                          }}
                          className="h-7 w-7 rounded-full bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors shrink-0"
                          title="Contacter"
                          aria-label={`Contacter ${s.prenom} ${s.nom}`}
                        >
                          <MessageCircle className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </TableCell>
                    <TableCell>
                      <BadgeY2K variant="info">{professionLabel(s.profession)}</BadgeY2K>
                    </TableCell>
                    <TableCell>
                      <JaugeScoreFiabilite score={s.score_fiabilite} />
                    </TableCell>
                    <TableCell>
                      <span className="text-sm text-muted-foreground">{s.pool_urgence_rayon_km} km</span>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1 text-sm">
                        <MapPin className="h-3 w-3 text-muted-foreground" />
                        {s.distance_km !== null ? `${s.distance_km} km` : '—'}
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1">
                        <span className="font-bold text-foreground text-sm">{s.missions_urgence_terminees}</span>
                        {s.missions_urgence_terminees > 5 && (
                          <BadgeY2K variant="warning" size="sm">🏅</BadgeY2K>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      {s.en_mission_maintenant ? (
                        <BadgeY2K variant="error" size="sm">En mission</BadgeY2K>
                      ) : (
                        <BadgeY2K variant="success" size="sm">Disponible</BadgeY2K>
                      )}
                    </TableCell>
                    <TableCell>
                      <span className="text-xs text-muted-foreground">
                        {s.derniere_mission_chez_nous
                          ? format(new Date(s.derniere_mission_chez_nous), 'dd MMM yyyy', { locale: fr })
                          : 'Jamais'}
                      </span>
                    </TableCell>
                    <TableCell className="hidden lg:table-cell">
                      <span className="text-xs text-muted-foreground line-clamp-1 max-w-[120px]">
                        {s.bio || '—'}
                      </span>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1">
                        <Button
                          size="sm"
                          variant="destructive"
                          className="text-xs h-7 px-2"
                          onClick={() => alerterSoignant(s)}
                          disabled={s.en_mission_maintenant || urgencesAPourvoir.length === 0}
                          title="Alerter pour une urgence"
                          aria-label={`Alerter ${s.prenom} ${s.nom} pour une urgence`}
                        >
                          <Bell className="h-3 w-3" />
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="text-xs h-7 px-2"
                          onClick={() => ouvrirProposerMission(s)}
                          title="Proposer une mission"
                          aria-label={`Proposer une mission à ${s.prenom} ${s.nom}`}
                        >
                          <Send className="h-3 w-3" />
                        </Button>
                        {!isAdmin && <BoutonFavori soignantId={s.soignant_id} etablissementId={etablissementId} />}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            </div>
            <div className="space-y-3 p-3 md:hidden">
              {filtered.map((soignant) => (
                <article key={soignant.soignant_id} className="rounded-xl border border-border p-3">
                  <div className="flex items-start justify-between gap-2">
                    <button
                      type="button"
                      onClick={() => navigate(isAdmin ? `/admin/utilisateurs/${soignant.soignant_id}` : `/etablissement/soignants/${soignant.soignant_id}`)}
                      className="flex min-w-0 items-center gap-2 text-left"
                    >
                      <AvatarDisplay src={soignant.avatar_url} prenom={soignant.prenom} nom={soignant.nom} size={40} rounded="full" />
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-semibold text-foreground">{soignant.prenom} {soignant.nom}</span>
                        <span className="block text-xs text-muted-foreground">{professionLabel(soignant.profession)}</span>
                      </span>
                    </button>
                    {soignant.en_mission_maintenant
                      ? <BadgeY2K variant="error" size="sm">En mission</BadgeY2K>
                      : <BadgeY2K variant="success" size="sm">Disponible</BadgeY2K>}
                  </div>
                  <dl className="mt-3 grid grid-cols-2 gap-2 text-xs">
                    <div><dt className="text-muted-foreground">Distance</dt><dd className="font-medium text-foreground">{soignant.distance_km != null ? `${soignant.distance_km} km` : '—'}</dd></div>
                    <div><dt className="text-muted-foreground">Rayon choisi</dt><dd className="font-medium text-foreground">{soignant.pool_urgence_rayon_km} km</dd></div>
                    <div><dt className="text-muted-foreground">Fiabilité</dt><dd className="font-medium text-foreground">{soignant.score_fiabilite}/100</dd></div>
                    <div><dt className="text-muted-foreground">Urgences réalisées</dt><dd className="font-medium text-foreground">{soignant.missions_urgence_terminees}</dd></div>
                  </dl>
                  <div className="mt-3 grid grid-cols-3 gap-2 border-t border-border pt-3">
                    <Button type="button" variant="outline" size="sm" onClick={() => ouvrirConversation(soignant.soignant_id)} aria-label={`Contacter ${soignant.prenom} ${soignant.nom}`}>
                      <MessageCircle className="h-4 w-4" aria-hidden="true" />
                    </Button>
                    <Button type="button" variant="destructive" size="sm" onClick={() => alerterSoignant(soignant)} disabled={soignant.en_mission_maintenant || urgencesAPourvoir.length === 0} aria-label={`Alerter ${soignant.prenom} ${soignant.nom}`}>
                      <Bell className="h-4 w-4" aria-hidden="true" />
                    </Button>
                    <Button type="button" variant="outline" size="sm" onClick={() => ouvrirProposerMission(soignant)} aria-label={`Proposer une mission à ${soignant.prenom} ${soignant.nom}`}>
                      <Send className="h-4 w-4" aria-hidden="true" />
                    </Button>
                  </div>
                </article>
              ))}
            </div>
          </div>
        )}

        {/* Historique urgences — replié par défaut (pattern « file de travail ») */}
        {historiqueClos.length > 0 && (
          <section id="historique-urgences" aria-label="Historique des urgences" className="card-base">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <button
                type="button"
                onClick={() => setHistoriqueOuvert((o) => !o)}
                aria-expanded={historiqueOuvert}
                className="flex items-center gap-2 text-base font-semibold text-muted-foreground hover:text-foreground transition-colors"
              >
                <Clock className="h-5 w-5" />
                Historique des urgences
                <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
                  {historiqueAffiche.length}
                </span>
                <ChevronDown className={cn('h-4 w-4 transition-transform', historiqueOuvert && 'rotate-180')} />
              </button>
              {filtreHistorique === 'POURVUES_MOIS' && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setFiltreHistorique('TOUT');
                    setSearchParams({}, { replace: true });
                  }}
                >
                  Voir tout l'historique
                </Button>
              )}
            </div>
            {historiqueOuvert && (
              <div className="mt-4">
                <div className="hidden overflow-x-auto md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Mission</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead>Remplaçant</TableHead>
                      <TableHead>Mission créée le</TableHead>
                      <TableHead>Statut</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {historiqueAffiche.map((h) => (
                        <TableRow key={h.id} className="cursor-pointer hover:bg-muted/50" onClick={() => navigate(detailMissionPath(h.id))}>
                          <TableCell className="font-medium text-sm">{h.intitule}</TableCell>
                          <TableCell className="text-sm text-muted-foreground">
                            {format(new Date(h.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })}
                          </TableCell>
                          <TableCell className="text-sm">
                            {h.soignant_prenom ? `${h.soignant_prenom} ${h.soignant_nom}` : <span className="text-muted-foreground">—</span>}
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">
                            {format(new Date(h.cree_le), 'dd/MM/yyyy HH:mm', { locale: fr })}
                          </TableCell>
                          <TableCell>
                            <BadgeY2K
                              variant={statutMissionVariant(h.statut)}
                              size="sm"
                            >
                              {statutMissionLabel(h.statut)}
                            </BadgeY2K>
                          </TableCell>
                        </TableRow>
                    ))}
                  </TableBody>
                </Table>
                </div>
                <div className="space-y-2 md:hidden">
                  {historiqueAffiche.map((mission) => (
                    <button
                      key={mission.id}
                      type="button"
                      onClick={() => navigate(detailMissionPath(mission.id))}
                      className="w-full rounded-xl border border-border p-3 text-left hover:bg-muted/50"
                    >
                      <span className="mb-2 flex items-start justify-between gap-2">
                        <span className="text-sm font-semibold text-foreground">{mission.intitule}</span>
                        <BadgeY2K variant={statutMissionVariant(mission.statut)} size="sm">{statutMissionLabel(mission.statut)}</BadgeY2K>
                      </span>
                      <span className="block text-xs text-muted-foreground">Mission : {format(new Date(mission.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })}</span>
                      <span className="block text-xs text-muted-foreground">Remplaçant : {mission.soignant_prenom ? `${mission.soignant_prenom} ${mission.soignant_nom}` : '—'}</span>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </section>
        )}
      </div>

      {/* Modal alerter tout le pool */}
      <ModalConfirmation
        ouvert={alerterTousOpen}
        titre="Alerter tout le pool d'urgence"
        message={`Envoyer l'alerte à ${filtered.filter(s => !s.en_mission_maintenant).length} soignant${filtered.filter(s => !s.en_mission_maintenant).length > 1 ? 's' : ''} disponible${filtered.filter(s => !s.en_mission_maintenant).length > 1 ? 's' : ''} dans le pool ?`}
        labelConfirmer="Envoyer l'alerte 🚨"
        variante="danger"
        onConfirmer={alerterTous}
        onFermer={() => setAlerterTousOpen(false)}
      />

      {/* Modal proposer mission */}
      <DialogResponsive open={proposerModalOpen} onOpenChange={setProposerModalOpen}>
        <DialogResponsiveContent maxWidth="md">
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>
              Proposer une mission à {proposerSoignant?.prenom} {proposerSoignant?.nom}
            </DialogResponsiveTitle>
          </DialogResponsiveHeader>
          <DialogResponsiveBody className="space-y-3">
            {loadingMissions ? (
              <p className="text-sm text-muted-foreground text-center py-4">Chargement des missions…</p>
            ) : missionsOuvertes.length === 0 ? (
              <div className="text-center py-4 space-y-3">
                <p className="text-sm text-muted-foreground">Aucune mission ouverte disponible.</p>
                <Button
                  variant="outline"
                  onClick={() => {
                    setProposerModalOpen(false);
                    navigate(isAdmin ? '/admin/missions' : `/etablissement/missions/creer?soignant_id=${proposerSoignant?.soignant_id}&profession=${proposerSoignant?.profession}`);
                  }}
                >
                  <Plus className="h-4 w-4 mr-1" />
                  Créer une nouvelle mission
                </Button>
              </div>
            ) : (
              <>
                <p className="text-sm text-muted-foreground">Sélectionnez une mission ouverte :</p>
                <div className="max-h-[300px] overflow-y-auto space-y-2">
                  {missionsOuvertes.map(m => (
                    <button
                      key={m.id}
                      onClick={() => assignerMission(m)}
                      disabled={assigningMissionId === m.id}
                      className="w-full text-left rounded-lg border p-3 hover:bg-accent/50 transition-colors disabled:opacity-50"
                    >
                      <p className="text-sm font-medium text-foreground">{m.intitule}</p>
                      <div className="flex items-center gap-2 mt-1 text-xs text-muted-foreground">
                        <span>{format(new Date(m.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })}</span>
                        <BadgeY2K variant="info" size="sm">{professionLabel(m.profession_requise)}</BadgeY2K>
                        {m.mode_attribution === 'CANDIDATURE' && <BadgeY2K variant="info" size="sm">Candidature</BadgeY2K>}
                      </div>
                    </button>
                  ))}
                </div>
                <div className="border-t pt-3">
                  <Button
                    variant="outline"
                    size="sm"
                    className="w-full"
                    onClick={() => {
                      setProposerModalOpen(false);
                      navigate(isAdmin ? '/admin/missions' : `/etablissement/missions/creer?soignant_id=${proposerSoignant?.soignant_id}&profession=${proposerSoignant?.profession}`);
                    }}
                  >
                    <Plus className="h-4 w-4 mr-1" />
                    Créer une nouvelle mission
                  </Button>
                </div>
              </>
            )}
          </DialogResponsiveBody>
        </DialogResponsiveContent>
      </DialogResponsive>
    </PoolLayout>
  );
}
