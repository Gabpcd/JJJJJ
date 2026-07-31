import { useEffect, useState } from 'react';
import { AlertTriangle, CalendarClock } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PointageRotatifSoignant } from '@/components/pointage/PointageRotatifSoignant';
import { Button } from '@/components/ui/button';
import {
  ajouterRepliMissionPonctuelle,
  evaluerDisponibilitePointage,
  FENETRE_OUVERTURE_POINTAGE_MINUTES,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { formatParis, memeJourParis } from '@/lib/date-heure-paris';

interface MissionPointage {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  etablissements?: { nom?: string | null } | null;
  creneaux?: CreneauPointage[];
}

interface ContratPointage {
  id: string;
  statut: string;
}

export function BlocPointageMission({
  mission,
  contrat,
  consentementGPS,
}: {
  mission: MissionPointage;
  contrat?: ContratPointage;
  consentementGPS: boolean | null;
}) {
  const navigate = useNavigate();
  const [maintenant, setMaintenant] = useState(() => new Date());
  useEffect(() => {
    const intervalle = window.setInterval(() => setMaintenant(new Date()), 30_000);
    return () => window.clearInterval(intervalle);
  }, []);
  const creneauxPointage = ajouterRepliMissionPonctuelle(mission.creneaux ?? [], mission);
  const disponibilite = evaluerDisponibilitePointage({
    creneaux: creneauxPointage,
    contratStatut: contrat?.statut,
    maintenant,
  });

  const prochain = disponibilite.prochainCreneau;
  const prochainDebut = prochain ? new Date(prochain.debut) : null;

  return (
    <div className="space-y-2">
      <button
        type="button"
        onClick={() => navigate(`/soignant/missions/${mission.id}`)}
        className="card-base w-full text-left hover:border-primary/30 transition-colors"
        aria-label={`Voir la mission ${mission.intitule}`}
      >
        <h3 className="font-semibold text-sm text-foreground truncate" title={mission.intitule}>
          {mission.intitule}
        </h3>
        <p className="text-xs text-muted-foreground mt-0.5">
          🏥 {mission.etablissements?.nom || 'Établissement'}
        </p>
      </button>

      {disponibilite.peutPointer ? (
        <PointageRotatifSoignant missionId={mission.id} consentementGPS={consentementGPS} />
      ) : (
        <div className="card-base border-dashed" role="status">
          <div className="flex gap-3">
            {disponibilite.motif === 'CONTRAT'
              ? <AlertTriangle className="h-5 w-5 shrink-0 text-warning" />
              : <CalendarClock className="h-5 w-5 shrink-0 text-primary" />}
            <div className="min-w-0">
              {disponibilite.motif === 'CONTRAT' ? (
                <>
                  <p className="font-semibold text-sm text-foreground">Contrat non signé</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    Le contrat doit être signé par les deux parties avant le premier pointage.
                  </p>
                  {prochainDebut && !memeJourParis(prochainDebut, maintenant) && (
                    <p className="text-xs text-muted-foreground mt-1">
                      Aucun créneau à pointer aujourd’hui. Prochain créneau le{' '}
                      {formatParis(prochainDebut, "EEEE d MMMM 'à' HH'h'mm")}.
                    </p>
                  )}
                  {contrat && (
                    <Button
                      type="button"
                      size="sm"
                      className="mt-3"
                      onClick={() => navigate(`/contrat/${contrat.id}`)}
                    >
                      Voir le contrat
                    </Button>
                  )}
                </>
              ) : disponibilite.motif === 'AUCUN_CRENEAU' ? (
                <>
                  <p className="font-semibold text-sm text-foreground">Aucun créneau planifié</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    Aucun horaire de présence n'est enregistré pour cette mission. Contacte l'établissement avant de te déplacer.
                  </p>
                </>
              ) : (
                <>
                  <p className="font-semibold text-sm text-foreground">
                    {prochainDebut && memeJourParis(prochainDebut, maintenant)
                      ? 'Pointage pas encore ouvert'
                      : 'Aucun créneau à pointer aujourd’hui'}
                  </p>
                  <p className="text-xs text-muted-foreground mt-1">
                    {prochainDebut && memeJourParis(prochainDebut, maintenant)
                      ? `Le pointage ouvrira ${FENETRE_OUVERTURE_POINTAGE_MINUTES} minutes avant le créneau de ${formatParis(prochainDebut, "HH'h'mm")}.`
                      : prochainDebut
                        ? `Prochain créneau le ${formatParis(prochainDebut, "EEEE d MMMM 'à' HH'h'mm")}.`
                        : 'Tous les créneaux planifiés sont terminés.'}
                  </p>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
