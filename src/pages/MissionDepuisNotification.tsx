import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { ChargementPage } from '@/components/ChargementPage';
import { ListeCandidatures } from '@/components/ListeCandidatures';
import { OUVERTURE_NOTIFICATION } from '@/lib/navigationNotification';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { CreneauPointage } from '@/lib/disponibilite-pointage';
import DetailMission from '@/pages/DetailMission';
import type { Tables } from '@/integrations/supabase/types';

const statutCandidature: Record<string, string> = { EN_ATTENTE: 'En attente', EN_ATTENTE_VALIDATION_ETAB: 'En attente de validation', ACCEPTEE: 'Acceptée', REFUSEE: 'Refusée', ANNULEE: 'Annulée' };

type CandidatureHabilitee = Pick<Tables<'candidatures'>, 'id' | 'soignant_id' | 'statut' | 'message' | 'cree_le'> & {
  soignant: Pick<Tables<'soignants'>,
    'id' | 'prenom' | 'nom' | 'profession' | 'specialite_medicale' | 'type_exercice'
    | 'est_etudiant' | 'etudiant_details' | 'tous_documents_valides' | 'score_fiabilite'
    | 'total_missions_terminees' | 'note_moyenne' | 'nb_evaluations'> & { nom_anonymise: true };
};

type Lecture = {
  mission: {
    id: string; intitule: string; etablissement_id: string; etablissement_nom: string;
    statut: string; mode_attribution: string; nb_creneaux: number;
    profession_requise: string; specialite_medicale_requise: string | null;
  };
  candidatures: CandidatureHabilitee[];
  creneaux: CreneauPointage[];
};

export default function MissionDepuisNotification() {
  const { id } = useParams<{ id: string }>();
  const { role } = useRole();
  const { user } = useAuth();
  const [lecture, setLecture] = useState<Lecture | null>(null);
  const [detailHabituel, setDetailHabituel] = useState(false);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const contexte = `${user?.id ?? ''}:${id ?? ''}`;
  const contexteActuel = useRef(contexte);
  contexteActuel.current = contexte;
  const [message, setMessage] = useState<{ contexte: string; texte: string } | null>(null);
  const [revision, setRevision] = useState(0);
  const recharger = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => { setMessage(null); }, [contexte]);
  const afficherMessage = useCallback((texte: string) => {
    if (contexteActuel.current === contexte) setMessage({ contexte, texte });
  }, [contexte]);
  const apresAcceptation = useCallback(() => {
    if (contexteActuel.current === contexte) recharger();
  }, [contexte, recharger]);
  const lire = useCallback(async (): Promise<Lecture> => {
    if (!id) throw new Error('Mission indisponible ou accès refusé');
    const { data, error } = await supabase.rpc('fn_lire_candidatures_mission_habilitee', { p_mission_id: id });
    if (error) throw error;
    const resultat = data as Partial<Lecture> | null;
    if (!resultat || resultat.mission?.id !== id || !Array.isArray(resultat.candidatures) || !Array.isArray(resultat.creneaux)) {
      throw new Error('Le détail de cette mission est momentanément indisponible.');
    }
    return resultat as Lecture;
  }, [id, user?.id]);
  const lireCandidatures = useCallback(async () => (await lire()).candidatures, [lire]);
  const lirePlanning = useCallback(async () => (await lire()).creneaux, [lire]);

  useEffect(() => {
    let ignore = false;
    setLoading(true); setErreur(null); setLecture(null); setDetailHabituel(false);
    void (async () => {
      // Conserver le détail complet existant pour les comptes établissement
      // dont la RLS autorise déjà cette mission, y compris la lecture seule.
      if (role === 'ADMIN_ETABLISSEMENT') {
        const { data, error } = await supabase.from('missions').select('id').eq('id', id!).maybeSingle();
        if (error) throw error;
        if (data) { if (!ignore) setDetailHabituel(true); return; }
      }
      const data = await lire();
      if (!ignore) setLecture(data);
    })().catch(error => { if (!ignore) setErreur(extraireMessageErreur(error)); })
      .finally(() => { if (!ignore) setLoading(false); });
    return () => { ignore = true; };
  }, [id, role, lire, revision]);

  useEffect(() => {
    const ouvrir = (event: Event) => {
      if (!detailHabituel && (event as CustomEvent<{ path?: string }>).detail?.path === `/etablissement/missions/${id}`) recharger();
    };
    window.addEventListener(OUVERTURE_NOTIFICATION, ouvrir);
    return () => window.removeEventListener(OUVERTURE_NOTIFICATION, ouvrir);
  }, [id, detailHabituel, recharger]);

  if (loading) return <ChargementPage />;
  if (detailHabituel) return <DetailMission />;
  const retour = role === 'ADMIN_GROUPE' ? '/groupe/tableau-de-bord'
    : role === 'SOIGNANT' ? '/soignant/tableau-de-bord'
    : role === 'ADMIN_PLATEFORME' ? '/admin' : '/etablissement/tableau-de-bord';
  return (
    <main className="mx-auto min-h-[100dvh] max-w-4xl space-y-4 px-4 pt-[calc(env(safe-area-inset-top)+1.5rem)] pb-[calc(env(safe-area-inset-bottom)+1.5rem)]">
      <Link to={retour} className="text-primary underline">Retour à mon espace</Link>
      {erreur ? <div role="alert" className="card-base">
        <h1 className="font-semibold">Impossible de charger la mission</h1>
        <p>{erreur}</p><button type="button" className="btn-primary mt-4" onClick={recharger}>Réessayer</button>
      </div> : lecture && <>
        <header><p className="text-sm text-muted-foreground">{lecture.mission.etablissement_nom}</p>
          <h1 className="text-xl font-semibold">{lecture.mission.intitule}</h1>
          <h2 className="mt-2 font-semibold">Candidatures</h2></header>
        {message?.contexte === contexte && <p role="status">{message.texte}</p>}
        {lecture.mission.statut === 'OUVERTE' && lecture.mission.mode_attribution === 'CANDIDATURE'
          ? <ListeCandidatures missionId={lecture.mission.id} missionIntitule={lecture.mission.intitule}
            missionCreneaux={lecture.creneaux} missionNbCreneaux={lecture.mission.nb_creneaux}
            missionProfession={lecture.mission.profession_requise}
            missionSpecialiteMedicale={lecture.mission.specialite_medicale_requise}
            chargerCandidaturesHabilitees={lireCandidatures} chargerPlanningHabilite={lirePlanning}
            afficherDetailScore={false} onAccepted={apresAcceptation} onError={afficherMessage} onSuccess={afficherMessage} />
          : <div className="card-base"><p>Cette mission n’accepte plus de nouvelles candidatures.</p>
            <ul>{lecture.candidatures.map(candidature => <li key={candidature.id}>
              {candidature.soignant?.prenom} {candidature.soignant?.nom} — {statutCandidature[candidature.statut] ?? 'Mise à jour'}
            </li>)}</ul></div>}
      </>}
    </main>
  );
}
