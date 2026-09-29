import { useEffect, useId, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, CheckCircle2, ChevronDown, Circle, Clock3, RefreshCw, TriangleAlert } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { avecDelai } from '@/lib/avecDelai';
import { listerCopiesBulletins } from '@/lib/copiesBulletins';
import { construireSuiviMission, type LecturesSuivi, type LectureSuivi, type MissionSuivie, type PlanningSuivi } from '@/lib/suiviMission';

interface Props {
  mission: MissionSuivie;
  role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT';
  candidatureEnvoyee?: boolean;
  litigeActif?: boolean;
  planning?: PlanningSuivi;
  onReessayerPlanning?: () => void;
  onOuvrirPlanning?: () => void;
}
const nonConcerne = { etat: 'non_concerne' } as const;
const initial: LecturesSuivi = { contrat: nonConcerne, presences: nonConcerne, documents: nonConcerne, paiements: nonConcerne, escrow: nonConcerne };

/** Remontage par compte, mission et rôle : aucune donnée du compte précédent ne survit. */
export function SuiviMission(props: Props) {
  const { user } = useAuth();
  if (!user) return null;
  return <SuiviMissionPourCompte key={`${user.id}:${props.role}:${props.mission.id}:${props.mission.etablissement_id}`}
    {...props} userId={user.id} />;
}

function SuiviMissionPourCompte({ mission, role, candidatureEnvoyee, litigeActif, planning, onReessayerPlanning, onOuvrirPlanning, userId }: Props & { userId: string }) {
  const titreId = useId();
  const detailId = useId();
  const estEtab = role === 'ADMIN_ETABLISSEMENT';
  const peutLireMission = Boolean(mission.soignant_assigne_id) && (estEtab || mission.soignant_assigne_id === userId);
  const [financeAutorisee, setFinanceAutorisee] = useState(false);
  const [lectures, setLectures] = useState<LecturesSuivi>(initial);
  const [revision, setRevision] = useState(0);
  const [detailOuvert, setDetailOuvert] = useState(false);

  useEffect(() => {
    if (!peutLireMission) {
      const inaccessible = { etat: 'restreint' } as const;
      setLectures(mission.soignant_assigne_id
        ? { contrat: inaccessible, presences: inaccessible, documents: inaccessible, paiements: inaccessible, escrow: inaccessible } : initial);
      setFinanceAutorisee(false);
      return;
    }
    let actif = true;
    const controller = new AbortController();
    const fin = setTimeout(() => controller.abort(), 10_000);
    const indisponible = { etat: 'indisponible' } as const;
    const chargement = { etat: 'chargement' } as const;
    setFinanceAutorisee(false);
    const regimeConnu = ['SALARIE', 'LIBERAL'].includes(mission.type_contrat_applique ?? '');
    setLectures({ contrat: chargement, presences: chargement, documents: regimeConnu ? chargement : nonConcerne, paiements: chargement, escrow: mission.type_contrat_applique === 'LIBERAL' ? chargement : nonConcerne });
    async function lire<T>(operation: PromiseLike<{ data: T[] | null; error: unknown }>): Promise<LectureSuivi<T>> {
      try {
        const { data, error } = await avecDelai(operation, 10_000);
        return !error && Array.isArray(data) ? { etat: 'disponible', lignes: data } : indisponible;
      } catch { return indisponible; }
    }
    async function lireFinances(): Promise<Pick<LecturesSuivi, 'documents' | 'paiements' | 'escrow'>> {
      let copiesAutorisees = !estEtab;
      if (estEtab) {
        try {
          const { data, error } = await avecDelai(supabase.rpc('fn_mes_permissions_etab', {
            p_etablissement_id: mission.etablissement_id,
          }).abortSignal(controller.signal), 10_000);
          const acces = data as { success?: boolean; etablissement_id?: string; permissions?: { lecture_paiement?: boolean; paiement?: boolean } } | null;
          if (error || !acces?.success || acces.etablissement_id !== mission.etablissement_id) {
            return { documents: indisponible, paiements: indisponible, escrow: indisponible };
          }
          if (!acces.permissions?.lecture_paiement && !acces.permissions?.paiement) {
            return { documents: { etat: 'restreint' }, paiements: { etat: 'restreint' }, escrow: { etat: 'restreint' } };
          }
          copiesAutorisees = acces.permissions?.paiement === true;
        } catch { return { documents: indisponible, paiements: indisponible, escrow: indisponible }; }
      }
      if (!actif || controller.signal.aborted) return { documents: indisponible, paiements: indisponible, escrow: indisponible };
      setFinanceAutorisee(true);
      const [documents, paiements, escrow] = await Promise.all([
        regimeConnu ? mission.type_contrat_applique === 'LIBERAL'
          ? lire(supabase.from('factures_honoraires').select('statut,type_document').eq('mission_id', mission.id).abortSignal(controller.signal))
          : copiesAutorisees
            ? lire(listerCopiesBulletins(estEtab ? mission.etablissement_id : null, mission.id)
              .then(copies => ({ data: copies.map(c => ({ statut: c.statut, type_document: 'COPIE_BULLETIN_OFFICIEL' })), error: null })))
            : Promise.resolve({ etat: 'restreint' } as const)
          : Promise.resolve(nonConcerne),
        lire(supabase.from('paiements_soignant').select('statut,confirme_par_soignant,conteste')
          .eq('mission_id', mission.id).abortSignal(controller.signal)),
        mission.type_contrat_applique === 'LIBERAL'
          ? lire<{ statut: string; paye_le: string | null }>(supabase.rpc('fn_suivi_escrow_mission' as any, { p_mission_id: mission.id }).abortSignal(controller.signal) as any)
          : Promise.resolve(nonConcerne),
      ]);
      return { documents, paiements, escrow };
    }
    void Promise.all([
      lire(supabase.from('contrats_mission').select('id,statut,signature_soignant,signature_etablissement')
        .eq('mission_id', mission.id).order('cree_le', { ascending: false }).limit(1).abortSignal(controller.signal)),
      lire(supabase.from('presences').select('pointage_arrivee_le,pointage_depart_le,valide_par_etablissement')
        .eq('mission_id', mission.id).abortSignal(controller.signal)),
      lireFinances(),
    ]).then(([contrat, presences, finances]) => {
      if (actif) setLectures({ contrat, presences, ...finances });
    }).finally(() => clearTimeout(fin));
    return () => { actif = false; clearTimeout(fin); controller.abort(); };
  }, [mission.id, mission.etablissement_id, mission.soignant_assigne_id, mission.statut, mission.type_contrat_applique, peutLireMission, estEtab, revision]);

  const etapes = construireSuiviMission(mission, lectures, { candidatureEnvoyee, litigeActif, planning });
  const reperes = etapes.filter(e => e.id !== 'attribution' && e.id !== 'mission');
  const contexte = etapes.filter(e => e.id === 'attribution' || e.id === 'mission');
  // Le dossier reste consultable sans inventer un verdict global jamais chargé.
  const etapesPrioritaires = etapes.filter(e => e.id !== 'conformite');
  const charge = Object.values(lectures).some(l => l.etat === 'chargement');
  const enErreur = Object.values(lectures).some(l => l.etat === 'indisponible');
  const accesLimite = Object.values(lectures).some(l => l.etat === 'restreint');
  // Une synthèse d’état, jamais un pourcentage d’accomplissement ou un solde financier.
  const prioritaire = etapesPrioritaires.find(e => e.id === 'mission' && e.etat === 'a_verifier')
    ?? etapesPrioritaires.find(e => e.etat === 'a_verifier')
    ?? etapesPrioritaires.find(e => e.etat === 'en_cours')
    ?? etapesPrioritaires.find(e => e.etat === 'inconnu')
    ?? etapes[etapes.length - 1];
  const libellesCourts = { attribution: 'Attrib.', conformite: 'Dossier', contrat: 'Contrat', planning: 'Prévu', mission: 'Mission', presence: 'Présence', heures: 'Valid.', document: 'Doc.', reglement: 'Règl.' };
  const contratId = lectures.contrat.etat === 'disponible' ? lectures.contrat.lignes[0]?.id : null;
  const base = estEtab ? '/etablissement' : '/soignant';
  const finances = estEtab ? '/etablissement/facturation' : '/soignant/mes-gains';
  const liens: Partial<Record<(typeof etapes)[number]['id'], { vers: string; texte: string }>> = {
    ...(!estEtab ? { conformite: { vers: '/soignant/documents', texte: 'Consulter mon dossier' } }
      : mission.soignant_assigne_id ? { conformite: { vers: `/etablissement/soignants/${mission.soignant_assigne_id}`, texte: 'Consulter le dossier du soignant' } } : {}),
    planning: { vers: '#planning-mission', texte: 'Voir les créneaux prévus' },
    ...(peutLireMission ? {
    ...(contratId ? { contrat: { vers: `/contrat/${contratId}`, texte: 'Consulter le contrat' } } : {}),
    presence: { vers: `${base}/presences/mission/${mission.id}`, texte: 'Voir les présences' },
    heures: { vers: `${base}/presences/mission/${mission.id}`, texte: 'Consulter la validation' },
    ...(financeAutorisee ? {
      ...(lectures.documents.etat !== 'restreint' ? { document: { vers: mission.type_contrat_applique === 'SALARIE'
        ? estEtab ? '/etablissement/export-paie' : '/soignant/mes-gains?tab=bulletins'
        : estEtab ? finances : '/soignant/mes-gains?tab=factures', texte: 'Consulter les documents' } } : {}),
      reglement: { vers: finances, texte: 'Consulter les finances' },
    } : {}),
    } : {}),
  };

  return <section aria-labelledby={titreId} className="card-base mb-4">
    <div className="flex items-center justify-between gap-2">
      <h2 id={titreId} className="font-semibold text-foreground">Suivi de la mission</h2>
      {(peutLireMission || planning?.etat === 'indisponible') && <button type="button" className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-primary hover:bg-primary/5 disabled:opacity-60"
        aria-label="Actualiser le suivi" title="Actualiser le suivi"
        disabled={charge} onClick={() => {
          setRevision(r => r + 1);
          if (planning?.etat === 'indisponible') onReessayerPlanning?.();
        }}>
        <RefreshCw aria-hidden="true" className={`h-4 w-4 ${charge ? 'animate-spin' : ''}`} />
      </button>}
    </div>
    <p data-testid="suivi-resume" className="mt-1 text-sm text-muted-foreground">
      {charge ? 'Vérification du suivi en cours…' : `${prioritaire.titre} · ${prioritaire.statut}`}
    </p>
    {litigeActif && <p className="mt-2 text-sm text-warning" role="status">Un litige est en cours sur cette mission.</p>}
    {planning?.etat === 'indisponible' && <p role="alert" className="mt-2 text-sm text-destructive">Le planning n’a pas pu être chargé. Actualisez le suivi pour réessayer.</p>}
    {enErreur && <p role="alert" className="mt-2 text-sm text-destructive">Une partie du suivi n’a pas pu être chargée. Les étapes concernées restent à vérifier.</p>}
    {accesLimite && <p className="mt-2 text-sm text-muted-foreground">Accès limité à certaines informations du suivi.</p>}
    <ol aria-label="Repères du suivi" className="mt-3 grid grid-cols-7 gap-1">
      {reperes.map(etape => {
        const Icone = etape.etat === 'confirme' ? CheckCircle2 : etape.etat === 'a_verifier' ? TriangleAlert : etape.etat === 'en_cours' ? Clock3 : Circle;
        const couleur = etape.etat === 'confirme' ? 'text-success' : etape.etat === 'a_verifier' ? 'text-warning' : 'text-muted-foreground';
        return <li key={etape.id} title={`${etape.titre} : ${etape.statut}`} className="flex min-w-0 flex-col items-center gap-1">
          <Icone aria-hidden="true" className={`h-4 w-4 ${couleur}`} />
          <span aria-hidden="true" className="text-[10px] text-muted-foreground">{libellesCourts[etape.id]}</span>
          <span className="sr-only">{etape.titre} : {etape.statut}</span>
        </li>;
      })}
    </ol>
    <button type="button" aria-expanded={detailOuvert} aria-controls={detailId}
      className="mt-2 flex min-h-11 w-full items-center justify-between gap-2 rounded-lg text-left text-sm font-medium text-primary hover:underline"
      onClick={() => setDetailOuvert(ouvert => !ouvert)}>
      {detailOuvert ? 'Masquer le détail du suivi' : 'Afficher le détail du suivi'}
      <ChevronDown aria-hidden="true" className={`h-4 w-4 shrink-0 ${detailOuvert ? 'rotate-180' : ''}`} />
    </button>
    <div id={detailId} hidden={!detailOuvert}>
    <div className="mt-3 grid gap-2 sm:grid-cols-2">
      {contexte.map(etape => <div key={etape.id} data-testid={`suivi-${etape.id}`} className="min-w-0 rounded-lg bg-muted/30 p-3">
        <h3 className="text-sm font-semibold">{etape.titre}</h3>
        <p className="text-sm" data-etat={etape.etat}>{etape.statut}</p>
        <p className="mt-1 text-xs text-muted-foreground">{etape.detail}</p>
      </div>)}
    </div>
    <ol className="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {reperes.map(etape => {
        const Icone = etape.etat === 'confirme' ? CheckCircle2 : etape.etat === 'a_verifier' ? TriangleAlert : etape.etat === 'en_cours' ? Clock3 : Circle;
        const couleur = etape.etat === 'confirme' ? 'text-success' : etape.etat === 'a_verifier' ? 'text-warning' : 'text-muted-foreground';
        const lien = liens[etape.id];
        return <li key={etape.id} data-testid={`suivi-${etape.id}`} className="min-w-0 rounded-xl border border-border p-3">
          <div className="flex items-center gap-2"><Icone aria-hidden="true" className={`h-4 w-4 shrink-0 ${couleur}`} /><h3 className="text-sm font-semibold">{etape.titre}</h3></div>
          <p className="mt-2 text-sm font-medium" data-etat={etape.etat}>{etape.statut}</p>
          <p className="mt-1 text-xs text-muted-foreground">{etape.detail}</p>
          {lien && (lien.vers.startsWith('#')
            ? <a className="mt-2 inline-flex min-h-11 items-center gap-1 text-sm text-primary hover:underline" href={lien.vers}
              onClick={() => {
                onOuvrirPlanning?.();
                // Le parent peut devoir remonter l’onglet qui contient le planning.
                requestAnimationFrame(() => {
                  const cible = document.getElementById('planning-mission');
                  cible?.focus({ preventScroll: true });
                  cible?.scrollIntoView({ block: 'start' });
                });
              }}>{lien.texte}<ArrowRight aria-hidden="true" className="h-3 w-3 shrink-0" /></a>
            : <Link className="mt-2 inline-flex min-h-11 items-center gap-1 text-sm text-primary hover:underline" to={lien.vers}>{lien.texte}<ArrowRight aria-hidden="true" className="h-3 w-3 shrink-0" /></Link>)}
        </li>;
      })}
    </ol>
    </div>
  </section>;
}
