import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { CarteKPI } from '@/components/CarteKPI';
import { BoutonFavori } from '@/components/BoutonFavori';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { JaugeScoreFiabilite } from '@/components/JaugeScoreFiabilite';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Slider } from '@/components/ui/slider';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Flame, Users, UserCheck, Trophy, Bell, BellRing, Send, MapPin, Clock, MessageCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { PROFESSIONS } from '@/lib/constantes';

interface SoignantPool {
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

export default function PoolUrgenceEtablissement({ isAdmin = false }: { isAdmin?: boolean }) {
  const { user } = useAuth();
  const Layout = isAdmin 
    ? ({ children }: { children: React.ReactNode }) => <LayoutAdmin>{children}</LayoutAdmin>
    : ({ children }: { children: React.ReactNode }) => <LayoutApp role="ADMIN_ETABLISSEMENT">{children}</LayoutApp>;
  const navigate = useNavigate();
  const [soignants, setSoignants] = useState<SoignantPool[]>([]);
  const [historique, setHistorique] = useState<HistoriqueUrgence[]>([]);
  const [loading, setLoading] = useState(true);
  const [alerterTousOpen, setAlerterTousOpen] = useState(false);
  const [etablissementsAdmin, setEtablissementsAdmin] = useState<Array<{ id: string; nom: string }>>([]);
  const [selectedEtablissementId, setSelectedEtablissementId] = useState('');

  // Filters
  const [filtreProfession, setFiltreProfession] = useState<string>('TOUTES');
  const [filtreDispo, setFiltreDispo] = useState(false);
  const [filtreRayonMax, setFiltreRayonMax] = useState(50);
  const [filtreScoreMin, setFiltreScoreMin] = useState(0);

  const etablissementId = isAdmin ? selectedEtablissementId : user?.id || '';

  useEffect(() => {
    if (!isAdmin) return;

    const loadEtablissements = async () => {
      const { data, error } = await supabase
        .from('etablissements')
        .select('id, nom')
        .is('supprime_le', null)
        .order('nom', { ascending: true });

      if (error) {
        toast.error(error.message);
        return;
      }

      const etablissements = (data ?? []) as Array<{ id: string; nom: string }>;
      setEtablissementsAdmin(etablissements);
      setSelectedEtablissementId((current) => current || etablissements[0]?.id || '');
    };

    loadEtablissements();
  }, [isAdmin]);

  useEffect(() => {
    if (!etablissementId) return;
    loadData();
  }, [etablissementId]);

  const loadData = async () => {
    setLoading(true);
    const [poolRes, histRes] = await Promise.all([
      supabase.rpc('fn_pool_urgence_etablissement' as any, { p_etablissement_id: etablissementId }),
      supabase
        .from('missions')
        .select('id, intitule, debut_le, statut, cree_le, soignant_assigne_id, soignants(prenom, nom)')
        .eq('etablissement_id', etablissementId)
        .eq('est_urgente', true)
        .order('debut_le', { ascending: false })
        .limit(20),
    ]);
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
    setLoading(false);
  };

  const filtered = useMemo(() => {
    return soignants.filter((s) => {
      if (filtreProfession !== 'TOUTES' && s.profession !== filtreProfession) return false;
      if (filtreDispo && s.en_mission_maintenant) return false;
      if (s.distance_km !== null && s.distance_km > filtreRayonMax) return false;
      if (s.score_fiabilite < filtreScoreMin) return false;
      return true;
    });
  }, [soignants, filtreProfession, filtreDispo, filtreRayonMax, filtreScoreMin]);

  const kpiTotal = soignants.length;
  const kpiDisponibles = soignants.filter((s) => !s.en_mission_maintenant).length;
  const kpiUrgencesMois = historique.filter((h) => {
    const d = new Date(h.debut_le);
    const now = new Date();
    return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear() && h.statut === 'TERMINEE';
  }).length;

  const alerterSoignant = async (s: SoignantPool) => {
    toast.success(`🚨 Alerte envoyée à ${s.prenom} ${s.nom}`);
  };

  const alerterTous = async () => {
    setAlerterTousOpen(false);
    toast.success(`🚨 Alerte envoyée à ${filtered.filter(s => !s.en_mission_maintenant).length} soignants du pool`);
  };

  const professions = useMemo(() => {
    const set = new Set(soignants.map((s) => s.profession));
    return Array.from(set);
  }, [soignants]);

  const professionLabel = (code: string) => {
    const found = PROFESSIONS.find((p) => p.valeur === code);
    return found ? found.label : code;
  };

  if (loading) {
    return (
      <Layout>
        <div className="max-w-6xl mx-auto space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {[1, 2, 3].map(i => (
              <div key={i} className="card-base animate-pulse h-24" />
            ))}
          </div>
          <div className="card-base animate-pulse h-64" />
        </div>
      </Layout>
    );
  }

  return (
    <Layout>
      <div className="max-w-6xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Flame className="h-6 w-6 text-destructive" />
            Pool d'urgence
          </h1>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
            {isAdmin && (
              <div className="min-w-[240px]">
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
              disabled={filtered.filter(s => !s.en_mission_maintenant).length === 0}
            >
              <BellRing className="h-4 w-4 mr-1" />
              Alerter tout le pool 🚨
            </Button>
          </div>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <CarteKPI
            icone={Users}
            valeur={kpiTotal}
            label="Soignants dans le pool"
            couleurIcone="text-destructive"
            couleurFond="bg-destructive/10"
          />
          <CarteKPI
            icone={UserCheck}
            valeur={kpiDisponibles}
            label="Disponibles maintenant"
            couleurIcone="text-success"
            couleurFond="bg-success/10"
          />
          <CarteKPI
            icone={Trophy}
            valeur={kpiUrgencesMois}
            label="Urgences pourvues ce mois"
            couleurIcone="text-warning"
            couleurFond="bg-warning/10"
          />
        </div>

        {/* Filters */}
        <div className="card-base">
          <p className="text-sm font-semibold text-foreground mb-3">Filtres</p>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-end">
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Profession</label>
              <Select value={filtreProfession} onValueChange={setFiltreProfession}>
                <SelectTrigger><SelectValue /></SelectTrigger>
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
              <Slider value={[filtreRayonMax]} min={5} max={100} step={5} onValueChange={(v) => setFiltreRayonMax(v[0])} />
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">
                Score min : <span className="font-bold text-primary">{filtreScoreMin}</span>
              </label>
              <Slider value={[filtreScoreMin]} min={0} max={100} step={5} onValueChange={(v) => setFiltreScoreMin(v[0])} />
            </div>
            <div className="flex items-center gap-2">
              <Switch checked={filtreDispo} onCheckedChange={setFiltreDispo} />
              <span className="text-sm text-foreground">Disponibles uniquement</span>
            </div>
          </div>
        </div>

        {/* Table */}
        {filtered.length === 0 ? (
          <EtatVide
            icone={Flame}
            titre="Aucun soignant dans le pool"
            sousTitre="Aucun soignant n'a activé le pool d'urgence correspondant à vos critères."
          />
        ) : (
          <div className="card-base p-0 overflow-hidden">
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
                          onClick={async (e) => {
                            e.stopPropagation();
                            const base = isAdmin ? '/admin/messagerie' : '/etablissement/messagerie';
                            const { data, error } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: s.soignant_id, p_mission_id: null });
                            console.log('fn_obtenir_conversation pool:', { data, error });
                            if (data) navigate(`${base}?conv=${data}`);
                          }}
                          className="h-7 w-7 rounded-full bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors shrink-0"
                          title="Contacter"
                        >
                          <MessageCircle className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary" className="text-xs">{professionLabel(s.profession)}</Badge>
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
                          <Badge className="bg-warning/20 text-warning border-warning/30 text-[10px]">🏅</Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      {s.en_mission_maintenant ? (
                        <Badge variant="destructive" className="text-[10px]">En mission</Badge>
                      ) : (
                        <Badge className="bg-success/20 text-success border-success/30 text-[10px]">Disponible</Badge>
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
                          disabled={s.en_mission_maintenant}
                          title="Alerter pour une urgence"
                        >
                          <Bell className="h-3 w-3" />
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="text-xs h-7 px-2"
                          onClick={() => navigate(isAdmin ? `/admin/missions` : `/etablissement/missions/creer?urgence=true&soignant=${s.soignant_id}`)}
                          title="Proposer une mission urgente"
                        >
                          <Send className="h-3 w-3" />
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="text-xs h-7 px-2"
                          onClick={async () => {
                            const base = isAdmin ? '/admin/messagerie' : '/etablissement/messagerie';
                            const { data } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: s.soignant_id, p_mission_id: null });
                            if (data) navigate(`${base}?conv=${data}`);
                          }}
                          title="Contacter"
                        >
                          <MessageCircle className="h-3 w-3" />
                        </Button>
                        <BoutonFavori soignantId={s.soignant_id} etablissementId={etablissementId} />
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        {/* Historique urgences */}
        {historique.length > 0 && (
          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
              <Clock className="h-5 w-5 text-muted-foreground" />
              Historique des urgences
            </h2>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Mission</TableHead>
                  <TableHead>Date</TableHead>
                  <TableHead>Remplaçant</TableHead>
                  <TableHead>Délai de réponse</TableHead>
                  <TableHead>Statut</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {historique.map((h) => {
                  const delaiMin = h.soignant_assigne_id
                    ? Math.round((new Date(h.debut_le).getTime() - new Date(h.cree_le).getTime()) / 60000)
                    : null;
                  return (
                    <TableRow key={h.id} className="cursor-pointer hover:bg-muted/50" onClick={() => navigate(`/etablissement/missions/${h.id}`)}>
                      <TableCell className="font-medium text-sm">{h.intitule}</TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {format(new Date(h.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })}
                      </TableCell>
                      <TableCell className="text-sm">
                        {h.soignant_prenom ? `${h.soignant_prenom} ${h.soignant_nom}` : <span className="text-muted-foreground">—</span>}
                      </TableCell>
                      <TableCell className="text-sm">
                        {delaiMin !== null && delaiMin > 0 ? (
                          <Badge variant="secondary" className="text-[10px]">{delaiMin < 60 ? `${delaiMin} min` : `${Math.round(delaiMin / 60)}h`}</Badge>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant={h.statut === 'TERMINEE' ? 'default' : h.statut === 'OUVERTE' ? 'destructive' : 'secondary'}
                          className="text-[10px]"
                        >
                          {h.statut}
                        </Badge>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </div>

      {/* Modal alerter tout le pool */}
      <ModalConfirmation
        ouvert={alerterTousOpen}
        titre="Alerter tout le pool d'urgence"
        message={`Envoyer l'alerte à ${filtered.filter(s => !s.en_mission_maintenant).length} soignants disponibles dans le pool ?`}
        labelConfirmer="Envoyer l'alerte 🚨"
        variante="danger"
        onConfirmer={alerterTous}
        onFermer={() => setAlerterTousOpen(false)}
      />
    </Layout>
  );
}
