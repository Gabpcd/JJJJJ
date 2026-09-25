import { useEffect, useId, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, CheckCircle2, Circle, Clock3, RefreshCw, TriangleAlert } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { avecDelai } from '@/lib/avecDelai';
import { construireSuiviMission, type LecturesSuivi, type LectureSuivi, type MissionSuivie } from '@/lib/suiviMission';

interface Props {
  mission: MissionSuivie;
  role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT';
  candidatureEnvoyee?: boolean;
  litigeActif?: boolean;
}
const nonConcerne = { etat: 'non_concerne' } as const;
const initial: LecturesSuivi = { contrat: nonConcerne, presences: nonConcerne, documents: nonConcerne, paiements: nonConcerne };

/** Remontage par compte, mission et rôle : aucune donnée du compte précédent ne survit. */
export function SuiviMission(props: Props) {
  const { user } = useAuth();
  if (!user) return null;
  return <SuiviMissionPourCompte key={`${user.id}:${props.role}:${props.mission.id}:${props.mission.etablissement_id}`}
    {...props} userId={user.id} />;
}

function SuiviMissionPourCompte({ mission, role, candidatureEnvoyee, litigeActif, userId }: Props & { userId: string }) {
  const titreId = useId();
  const estEtab = role === 'ADMIN_ETABLISSEMENT';
  const peutLireMission = Boolean(mission.soignant_assigne_id) && (estEtab || mission.soignant_assigne_id === userId);
  const [financeAutorisee, setFinanceAutorisee] = useState(false);
  const [lectures, setLectures] = useState<LecturesSuivi>(initial);
  const [revision, setRevision] = useState(0);

  useEffect(() => {
    if (!peutLireMission) {
      const inaccessible = { etat: 'restreint' } as const;
      setLectures(mission.soignant_assigne_id
        ? { contrat: inaccessible, presences: inaccessible, documents: inaccessible, paiements: inaccessible } : initial);
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
    setLectures({ contrat: chargement, presences: chargement, documents: regimeConnu ? chargement : nonConcerne, paiements: chargement });
    async function lire<T>(operation: PromiseLike<{ data: T[] | null; error: unknown }>): Promise<LectureSuivi<T>> {
      try {
        const { data, error } = await avecDelai(operation, 10_000);
        return !error && Array.isArray(data) ? { etat: 'disponible', lignes: data } : indisponible;
      } catch { return indisponible; }
    }
    async function lireFinances(): Promise<Pick<LecturesSuivi, 'documents' | 'paiements'>> {
      if (estEtab) {
        try {
          const { data, error } = await avecDelai(supabase.rpc('fn_mes_permissions_etab', {
            p_etablissement_id: mission.etablissement_id,
          }).abortSignal(controller.signal), 10_000);
          const acces = data as { success?: boolean; etablissement_id?: string; permissions?: { lecture_paiement?: boolean; paiement?: boolean } } | null;
          if (error || !acces?.success || acces.etablissement_id !== mission.etablissement_id) {
            return { documents: indisponible, paiements: indisponible };
          }
          if (!acces.permissions?.lecture_paiement && !acces.permissions?.paiement) {
            return { documents: { etat: 'restreint' }, paiements: { etat: 'restreint' } };
          }
        } catch { return { documents: indisponible, paiements: indisponible }; }
      }
      if (!actif || controller.signal.aborted) return { documents: indisponible, paiements: indisponible };
      setFinanceAutorisee(true);
      const [documents, paiements] = await Promise.all([
        regimeConnu ? mission.type_contrat_applique === 'LIBERAL'
          ? lire(supabase.from('factures_honoraires').select('statut,type_document').eq('mission_id', mission.id).abortSignal(controller.signal))
          : lire(supabase.from('bulletins_paie').select('statut,pdf_s3_key').eq('mission_id', mission.id).abortSignal(controller.signal))
          : Promise.resolve(nonConcerne),
        lire(supabase.from('paiements_soignant').select('statut,confirme_par_soignant,conteste')
          .eq('mission_id', mission.id).abortSignal(controller.signal)),
      ]);
      return { documents, paiements };
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

  const etapes = construireSuiviMission(mission, lectures, { candidatureEnvoyee, litigeActif });
  const charge = Object.values(lectures).some(l => l.etat === 'chargement');
  const enErreur = Object.values(lectures).some(l => l.etat === 'indisponible');
  const contratId = lectures.contrat.etat === 'disponible' ? lectures.contrat.lignes[0]?.id : null;
  const base = estEtab ? '/etablissement' : '/soignant';
  const finances = estEtab ? '/etablissement/facturation' : '/soignant/mes-gains';
  const liens: Partial<Record<(typeof etapes)[number]['id'], { vers: string; texte: string }>> = peutLireMission ? {
    ...(contratId ? { contrat: { vers: `/contrat/${contratId}`, texte: 'Consulter le contrat' } } : {}),
    heures: { vers: `${base}/presences/mission/${mission.id}`, texte: 'Voir les présences' },
    ...(financeAutorisee ? {
      document: { vers: mission.type_contrat_applique === 'SALARIE'
        ? estEtab ? '/etablissement/export-paie' : '/soignant/mes-gains?tab=bulletins'
        : estEtab ? finances : '/soignant/mes-gains?tab=factures', texte: 'Consulter les documents' },
      reglement: { vers: finances, texte: 'Consulter les finances' },
    } : {}),
  } : {};

  return <section aria-labelledby={titreId} className="card-base mb-4">
    <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
      <h2 id={titreId} className="font-semibold text-foreground">Suivi de la mission</h2>
      {peutLireMission && <button type="button" className="inline-flex min-h-11 items-center gap-2 text-sm text-primary px-2 disabled:opacity-60"
        disabled={charge} onClick={() => setRevision(r => r + 1)}>
        <RefreshCw aria-hidden="true" className={`h-4 w-4 ${charge ? 'animate-spin' : ''}`} />Actualiser le suivi
      </button>}
    </div>
    {litigeActif && <p className="mb-3 text-sm text-warning" role="status">Un litige est en cours sur cette mission.</p>}
    {enErreur && <p role="alert" className="mb-3 text-sm text-destructive">Une partie du suivi n’a pas pu être chargée. Les étapes concernées restent à vérifier.</p>}
    <ol className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {etapes.map(etape => {
        const Icone = etape.etat === 'confirme' ? CheckCircle2 : etape.etat === 'a_verifier' ? TriangleAlert : etape.etat === 'en_cours' ? Clock3 : Circle;
        const couleur = etape.etat === 'confirme' ? 'text-success' : etape.etat === 'a_verifier' ? 'text-warning' : 'text-muted-foreground';
        const lien = liens[etape.id];
        return <li key={etape.id} data-testid={`suivi-${etape.id}`} className="min-w-0 rounded-xl border border-border p-3">
          <div className="flex items-center gap-2"><Icone aria-hidden="true" className={`h-4 w-4 shrink-0 ${couleur}`} /><h3 className="text-sm font-semibold">{etape.titre}</h3></div>
          <p className="mt-2 text-sm font-medium" data-etat={etape.etat}>{etape.statut}</p>
          <p className="mt-1 text-xs text-muted-foreground">{etape.detail}</p>
          {lien && <Link className="mt-2 inline-flex min-h-11 items-center gap-1 text-sm text-primary hover:underline" to={lien.vers}>{lien.texte}<ArrowRight aria-hidden="true" className="h-3 w-3 shrink-0" /></Link>}
        </li>;
      })}
    </ol>
  </section>;
}
