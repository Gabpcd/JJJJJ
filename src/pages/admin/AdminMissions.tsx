import React, { useState, useEffect } from 'react';
import { useSearchParams, Link, useNavigate } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { ExternalLink, Clock, CheckCircle, CheckCircle2, ChevronDown, History, PlayCircle, Send, ClipboardList, UserX, Building2, User, CalendarDays, FlaskConical } from 'lucide-react';
import { estMissionTestAdmin, formatEuroAdmin } from '@/lib/adminPresentation';

type FiltreStatut = 'TOUTES' | 'OUVERTE' | 'ASSIGNEE' | 'EN_COURS' | 'TERMINEE';

const FILTRES: { cle: FiltreStatut; label: string; icone: React.ElementType; couleur: string }[] = [
  { cle: 'TOUTES', label: 'Toutes', icone: ClipboardList, couleur: 'bg-muted text-foreground' },
  { cle: 'OUVERTE', label: 'Ouvertes', icone: Clock, couleur: 'bg-warning/10 text-warning' },
  { cle: 'ASSIGNEE', label: 'Assignées', icone: Send, couleur: 'bg-info/10 text-info' },
  { cle: 'EN_COURS', label: 'En cours', icone: PlayCircle, couleur: 'bg-primary/10 text-primary' },
  { cle: 'TERMINEE', label: 'Terminées', icone: CheckCircle, couleur: 'bg-success/10 text-success' },
];

const STATUT_LABEL: Record<string, string> = {
  OUVERTE: 'Ouverte',
  ASSIGNEE: 'Assignée',
  EN_COURS: 'En cours',
  TERMINEE: 'Terminée',
  ANNULEE: 'Annulée',
};

const SELECT_MISSIONS = 'id, intitule, statut, debut_le, fin_le, duree_heures, profession_requise, taux_horaire_base, net_estime, est_asap, est_urgente, soignant_assigne_id, etablissement_id, etablissements(nom, est_compte_test), soignants(prenom, nom, est_compte_test)';

const formatDate = (d: string) => d ? new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }).replace(/ /g, '\u00a0') : '—';
const formatHeure = (d: string) => d ? new Date(d).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '';
const formatEur = (v: number | null) => formatEuroAdmin(v);

function statutBadge(statut: string) {
  const map: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
    OUVERTE: 'warning',
    ASSIGNEE: 'info',
    EN_COURS: 'info',
    TERMINEE: 'success',
    ANNULEE: 'error',
  };
  return <BadgeY2K variant={map[statut] ?? 'info'} size="sm">{STATUT_LABEL[statut] ?? statut}</BadgeY2K>;
}

function urgenceBadge(m: any) {
  if (m.est_asap) return <BadgeY2K variant="error" size="sm">ASAP</BadgeY2K>;
  if (m.est_urgente) return <BadgeY2K variant="warning" size="sm">Urgente</BadgeY2K>;
  return null;
}

const COLONNES_HISTORIQUE: ColonneTableau<any>[] = [
  { cle: 'mission', titre: 'Mission' },
  { cle: 'etab', titre: 'Établissement' },
  { cle: 'soignant', titre: 'Soignant' },
  { cle: 'statut', titre: 'Statut' },
  { cle: 'debut', titre: 'Début' },
  { cle: 'duree', titre: 'Durée' },
  { cle: 'taux', titre: 'Taux horaire' },
  { cle: 'actions', titre: '', align: 'right' as const },
];

// Pas de colonnes Soignant/Statut/Actions : toutes ces missions sont ouvertes et non assignées.
const COLONNES_A_TRAITER: ColonneTableau<any>[] = [
  { cle: 'mission', titre: 'Mission' },
  { cle: 'etab', titre: 'Établissement' },
  { cle: 'debut', titre: 'Début' },
  { cle: 'duree', titre: 'Durée' },
  { cle: 'taux', titre: 'Taux horaire' },
];

export default function AdminMissions() {
  usePageTitle('Missions');
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  // Support both ?filtre= (legacy) and ?statut= (from AdminGroupes)
  const filtreParam = (searchParams.get('filtre') || searchParams.get('statut') || 'TOUTES').toUpperCase() as FiltreStatut;
  const groupeParam = searchParams.get('groupe') || null;
  const [filtre, setFiltre] = useState<FiltreStatut>(FILTRES.some(f => f.cle === filtreParam) ? filtreParam : 'TOUTES');
  const [missions, setMissions] = useState<any[]>([]);
  const [aTraiter, setATraiter] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [rechargement, setRechargement] = useState(0);
  const [groupeNom, setGroupeNom] = useState<string | null>(null);
  // Historique replié par défaut (file de travail Session D), mais déplié d'emblée
  // si la page est ouverte via un lien profond (?filtre=/?statut= ou ?groupe=).
  const [historiqueOuvert, setHistoriqueOuvert] = useState<boolean>(
    () => (FILTRES.some(f => f.cle === filtreParam) && filtreParam !== 'TOUTES') || !!groupeParam
  );

  // Task 6 — marquer absence sans prévenir
  const [absenceMissionId, setAbsenceMissionId] = useState<string | null>(null);
  const [absenceMotif, setAbsenceMotif] = useState('');
  const [absenceLoading, setAbsenceLoading] = useState(false);

  useEffect(() => {
    async function charger() {
      setLoading(true);

      // Si filtre par groupe, récupérer les etab IDs du groupe
      let etabIds: string[] | null = null;
      if (groupeParam) {
        const { data: grp } = await supabase
          .from('groupes_sante')
          .select('nom')
          .eq('id', groupeParam)
          .maybeSingle();
        if (grp) setGroupeNom((grp as any).nom);

        const { data: etabs } = await supabase
          .from('etablissements')
          .select('id')
          .eq('groupe_sante_id', groupeParam);
        etabIds = (etabs || []).map((e: any) => e.id);

        if (!etabIds || etabIds.length === 0) {
          // Groupe sans établissements → aucune mission
          setATraiter([]);
          setMissions([]);
          setLoading(false);
          return;
        }
      }

      // File « À traiter » : missions ouvertes sans soignant assigné,
      // indépendante du filtre de l'historique.
      let queryATraiter = supabase
        .from('missions')
        .select(SELECT_MISSIONS)
        .eq('statut', 'OUVERTE')
        .is('soignant_assigne_id', null)
        .order('debut_le', { ascending: true })
        .limit(200);

      let queryListe = supabase
        .from('missions')
        .select(SELECT_MISSIONS)
        .order('debut_le', { ascending: false })
        .limit(200);

      if (filtre !== 'TOUTES') {
        queryListe = queryListe.eq('statut', filtre);
      }

      if (etabIds && etabIds.length > 0) {
        queryATraiter = queryATraiter.in('etablissement_id', etabIds);
        queryListe = queryListe.in('etablissement_id', etabIds);
      }

      const [{ data: dataATraiter }, { data: dataListe }] = await Promise.all([queryATraiter, queryListe]);

      // Urgentes/ASAP d'abord, puis début le plus proche en premier.
      const triees = (dataATraiter ?? []).slice().sort((a: any, b: any) => {
        const urgA = (a.est_asap || a.est_urgente) ? 0 : 1;
        const urgB = (b.est_asap || b.est_urgente) ? 0 : 1;
        if (urgA !== urgB) return urgA - urgB;
        return (a.debut_le || '').localeCompare(b.debut_le || '');
      });
      setATraiter(triees);
      setMissions(dataListe ?? []);
      setLoading(false);
    }
    charger();
  }, [filtre, groupeParam, rechargement]);

  function changerFiltre(f: FiltreStatut) {
    setFiltre(f);
    const params: Record<string, string> = {};
    if (f !== 'TOUTES') params.filtre = f;
    if (groupeParam) params.groupe = groupeParam;
    setSearchParams(params);
  }

  const marquerAbsence = async () => {
    if (!absenceMissionId) return;
    if (!absenceMotif.trim()) { toast.error('Motif obligatoire (RGPD audit).'); return; }
    setAbsenceLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_marquer_absence_sans_prevenir' as any, {
      p_mission_id: absenceMissionId,
      p_motif: absenceMotif.trim(),
    });
    setAbsenceLoading(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || error?.message || 'Erreur.'); return; }
    toast.success('Absence sans prévenir enregistrée');
    setAbsenceMissionId(null);
    setAbsenceMotif('');
    // reload missions
    setRechargement(v => v + 1);
  };

  const renduCellule = (m: any, col: ColonneTableau<any>) => {
    const soignantNom = m.soignants ? `${m.soignants.prenom ?? ''} ${m.soignants.nom ?? ''}`.trim() : null;
    const etabNom = (m.etablissements as any)?.nom ?? null;
    switch (col.cle) {
      case 'mission':
        return (
          <span className="inline-flex items-center gap-2 flex-wrap">
            <Link
              to={`/admin/missions/${m.id}`}
              onClick={(e) => e.stopPropagation()}
              className="font-medium text-primary hover:underline inline-flex items-center gap-1 group"
            >
              {m.intitule}
              <ExternalLink className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity" />
            </Link>
            {estMissionTestAdmin(m) && (
              <BadgeY2K variant="warning" size="sm" icone={<FlaskConical className="h-3 w-3" />}>
                Donnée de test
              </BadgeY2K>
            )}
            {urgenceBadge(m)}
          </span>
        );
      case 'etab':
        return m.etablissement_id ? (
          <Link to={`/admin/utilisateurs/${m.etablissement_id}`} onClick={(e) => e.stopPropagation()} className="text-primary hover:underline text-sm">
            {etabNom ?? 'Établissement'}
          </Link>
        ) : '—';
      case 'soignant':
        return m.soignant_assigne_id ? (
          <Link to={`/admin/utilisateurs/${m.soignant_assigne_id}`} onClick={(e) => e.stopPropagation()} className="text-primary hover:underline text-sm">
            {soignantNom || 'Soignant'}
          </Link>
        ) : <span className="text-muted-foreground">Non assigné</span>;
      case 'statut':
        return statutBadge(m.statut);
      case 'debut':
        return (
          <span className="text-muted-foreground whitespace-nowrap">
            {formatDate(m.debut_le)}
            <span className="text-[10px] ml-1">{formatHeure(m.debut_le)}</span>
          </span>
        );
      case 'duree':
        return <span className="text-muted-foreground">{m.duree_heures ? `${m.duree_heures}h` : '—'}</span>;
      case 'taux':
        return <span className="text-muted-foreground">{formatEur(m.taux_horaire_base)}</span>;
      case 'actions':
        return m.soignant_assigne_id ? (
          <div onClick={(e) => e.stopPropagation()}>
            <BoutonY2K size="sm" variant="secondary" onClick={() => { setAbsenceMissionId(m.id); setAbsenceMotif(''); }} iconeGauche={<UserX className="h-3.5 w-3.5" />}>
              Absence
            </BoutonY2K>
          </div>
        ) : null;
      default:
        return null;
    }
  };

  const renduCarte = (m: any) => {
    const soignantNom = m.soignants ? `${m.soignants.prenom ?? ''} ${m.soignants.nom ?? ''}`.trim() : null;
    const etabNom = (m.etablissements as any)?.nom ?? null;
    return (
      <div className="space-y-2">
        <div className="flex items-start justify-between gap-2">
          <p className="font-semibold text-foreground inline-flex items-center gap-1 min-w-0">
            <span className="truncate">{m.intitule}</span>
            <ExternalLink className="h-3.5 w-3.5 text-primary shrink-0" />
          </p>
          <span className="inline-flex items-center gap-1.5 shrink-0">
            {estMissionTestAdmin(m) && (
              <BadgeY2K variant="warning" size="sm" icone={<FlaskConical className="h-3 w-3" />}>
                Test
              </BadgeY2K>
            )}
            {urgenceBadge(m)}
            {statutBadge(m.statut)}
          </span>
        </div>
        <div className="text-xs text-muted-foreground space-y-0.5">
          <p className="flex items-center gap-1.5"><Building2 className="h-3.5 w-3.5 shrink-0" /> {etabNom ?? '—'}</p>
          <p className="flex items-center gap-1.5"><User className="h-3.5 w-3.5 shrink-0" /> {soignantNom || 'Non assigné'}</p>
          <p className="flex items-center gap-1.5 whitespace-nowrap">
            <CalendarDays className="h-3.5 w-3.5 shrink-0" /> {formatDate(m.debut_le)} {formatHeure(m.debut_le)} · {m.duree_heures ? `${m.duree_heures}h` : '—'} · {formatEur(m.taux_horaire_base)}
          </p>
        </div>
        {m.soignant_assigne_id && (
          <div className="pt-1" onClick={(e) => e.stopPropagation()}>
            <BoutonY2K size="sm" variant="secondary" onClick={() => { setAbsenceMissionId(m.id); setAbsenceMotif(''); }} iconeGauche={<UserX className="h-3.5 w-3.5" />}>
              Absence
            </BoutonY2K>
          </div>
        )}
      </div>
    );
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  // L'historique exclut les missions déjà affichées dans « À traiter » (pas de doublon).
  const idsATraiter = new Set(aTraiter.map((m: any) => m.id));
  const historique = missions.filter((m: any) => !idsATraiter.has(m.id));

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Missions" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">
          Missions{groupeNom ? <span className="text-primary"> — {groupeNom}</span> : ''}
        </h1>

        {/* ── File de travail : missions ouvertes sans soignant assigné ── */}
        <section aria-label="Missions à traiter">
          <h2 className="flex items-center gap-2 text-sm font-bold text-foreground mb-3">
            {aTraiter.length > 0 ? (
              <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
                {aTraiter.length}
              </span>
            ) : (
              <CheckCircle2 className="h-4 w-4 text-emerald-500" />
            )}
            À traiter — missions ouvertes sans soignant
          </h2>
          {aTraiter.length === 0 ? (
            <EmptyState
              icone={<ClipboardList />}
              titre="Aucune mission en attente"
              description="Toutes les missions ouvertes ont un soignant assigné."
              variant="success"
            />
          ) : (
            <TableOuCartes
              colonnes={COLONNES_A_TRAITER}
              donnees={aTraiter}
              getId={(m: any) => m.id}
              onClickLigne={(m: any) => navigate(`/admin/missions/${m.id}`)}
              renduCellule={renduCellule}
              renduCarte={renduCarte}
            />
          )}
        </section>

        {/* ── Historique : liste complète avec filtres, repliée par défaut ── */}
        <section aria-label="Historique des missions">
          <button
            type="button"
            onClick={() => setHistoriqueOuvert(o => !o)}
            aria-expanded={historiqueOuvert}
            className="flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground transition-colors mb-3"
          >
            <History className="h-4 w-4" />
            Historique — toutes les missions
            <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
              {historique.length}
            </span>
            <ChevronDown className={`h-4 w-4 transition-transform ${historiqueOuvert ? 'rotate-180' : ''}`} />
          </button>

          {historiqueOuvert && (
            <div className="space-y-4">
              {/* Filtres */}
              <div className="flex flex-wrap gap-2">
                {FILTRES.map((f) => (
                  <button
                    key={f.cle}
                    onClick={() => changerFiltre(f.cle)}
                    className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all border ${
                      filtre === f.cle
                        ? `${f.couleur} border-current ring-1 ring-current/20`
                        : 'bg-muted/50 text-muted-foreground border-transparent hover:bg-muted'
                    }`}
                  >
                    <f.icone className="h-3.5 w-3.5" />
                    {f.label}
                  </button>
                ))}
              </div>

              <TableOuCartes
                colonnes={COLONNES_HISTORIQUE}
                donnees={historique}
                getId={(m: any) => m.id}
                onClickLigne={(m: any) => navigate(`/admin/missions/${m.id}`)}
                etatVide={
                  <EmptyState
                    titre="Aucune mission"
                    description={
                      filtre === 'OUVERTE'
                        ? 'Les missions ouvertes sans soignant assigné figurent dans la section « À traiter » ci-dessus.'
                        : filtre === 'TOUTES'
                          ? "Aucune mission dans l'historique."
                          : `Aucune mission avec le statut « ${STATUT_LABEL[filtre] ?? filtre} ».`
                    }
                  />
                }
                renduCellule={renduCellule}
                renduCarte={renduCarte}
              />
            </div>
          )}
        </section>
      </div>

      {/* Task 6 — Modal marquer absence sans prévenir */}
      {absenceMissionId && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setAbsenceMissionId(null)}>
          <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4 max-h-[90dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h2 className="text-lg font-bold text-foreground inline-flex items-center gap-2">
              <UserX className="h-5 w-5 text-warning" />Absence sans prévenir
            </h2>
            <p className="text-xs text-muted-foreground">Enregistre une absence non justifiée du soignant. Motif tracé RGPD.</p>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Motif * (RGPD audit)</span>
              <Textarea value={absenceMotif} onChange={(e) => setAbsenceMotif(e.target.value)} rows={3} placeholder="Décrivez les circonstances de l'absence…" disabled={absenceLoading} />
            </label>
            <div className="flex gap-2">
              <BoutonY2K variant="secondary" onClick={() => setAbsenceMissionId(null)} disabled={absenceLoading}>Annuler</BoutonY2K>
              <BoutonY2K variant="destructive" onClick={marquerAbsence} disabled={absenceLoading || !absenceMotif.trim()} loading={absenceLoading}>Confirmer absence</BoutonY2K>
            </div>
          </div>
        </div>
      )}
    </LayoutAdmin>
  );
}
