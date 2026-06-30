import { JaugeProgression } from '@/components/JaugeProgression';
import { useParamBool } from '@/hooks/useParamBool';

interface ProgressionJalons3200hProps {
  heures: number;
  suivi?: {
    jalon_800h_atteint: boolean | null;
    jalon_1600h_atteint: boolean | null;
    jalon_2400h_atteint: boolean | null;
    jalon_3200h_atteint: boolean | null;
  } | null;
  missions?: any[];
  compact?: boolean;
}

const JALONS = [
  { seuil: 800, icone: '📚', titre: 'Formations en ligne offertes', desc: 'Catalogue de 50+ formations continues pour soignants.' },
  { seuil: 1600, icone: '🛡️', titre: 'Réduction assurance RCP', desc: '-15% sur votre assurance Responsabilité Civile Pro.' },
  { seuil: 2400, icone: '🏗️', titre: 'Accompagnement installation', desc: 'Un conseiller dédié vous guide dans vos démarches.' },
  { seuil: 3200, icone: '🎉', titre: 'Kit complet libéral', desc: 'Business plan + aide juridique + 3 mois d\'assurance.' },
];

export function ProgressionJalons3200h({ heures, suivi, missions, compact }: ProgressionJalons3200hProps) {
  const progression = Math.min(100, (heures / 3200) * 100);
  // B6 — les avantages par palier (formations, -15 % RCP, kit libéral…) ne sont pas
  // encore branchés : on gate la PROMESSE derrière un flag (comme l'affacturage).
  // OFF par défaut → on garde les paliers/heures mais sans promettre un service absent.
  const recompensesActives = useParamBool('recompenses_3200h_actives', false);

  // Estimation de rythme
  let estimation: string | null = null;
  if (missions && missions.length > 0 && heures < 3200) {
    const premiere = missions[missions.length - 1];
    const joursDepuisDebut = (Date.now() - new Date(premiere.debut_le).getTime()) / 86400000;
    if (joursDepuisDebut > 7) {
      const heuresParSemaine = (heures / joursDepuisDebut) * 7;
      const semainesRestantes = (3200 - heures) / heuresParSemaine;
      const dateEstimee = new Date(Date.now() + semainesRestantes * 7 * 86400000);
      estimation = `À votre rythme actuel (~${heuresParSemaine.toFixed(0)}h/semaine), vous atteindrez les 3 200h vers ${dateEstimee.toLocaleDateString('fr-FR')}.`;
    }
  }

  if (compact) {
    return (
      <div>
        <JaugeProgression valeur={heures} max={3200} marqueurs={[800, 1600, 2400, 3200]} couleurBarre="bg-gradient-to-r from-rose to-primary" couleurFond="bg-rose-light" />
        <div className="flex justify-between text-[10px] text-muted-foreground mt-1"><span>0h</span><span>800h</span><span>1600h</span><span>2400h</span><span>3200h</span></div>
        <p className="text-sm font-semibold text-foreground mt-2"><span className="text-rose">{heures}h</span> / 3 200h</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Jauge principale */}
      <div className="card-base bg-gradient-to-r from-rose-light to-rose/5 border-rose/20">
        <h2 className="text-lg font-bold text-foreground mb-1">🎯 Mon parcours vers le libéral</h2>
        <p className="text-xs text-muted-foreground mb-4">Objectif : 3 200 heures d'exercice</p>
        <JaugeProgression valeur={heures} max={3200} marqueurs={[800, 1600, 2400, 3200]} couleurBarre="bg-gradient-to-r from-rose to-success" couleurFond="bg-rose-light" />
        <div className="flex justify-between text-[10px] text-muted-foreground mt-1.5"><span>0h</span><span>800h</span><span>1600h</span><span>2400h</span><span>3200h</span></div>
        <p className="text-xl font-bold text-foreground mt-3 text-center">
          <span className="text-rose">{Math.round(heures)}</span> / 3 200h
          <span className="text-sm text-muted-foreground ml-2">({progression.toFixed(1)}%)</span>
        </p>
      </div>

      {/* Estimation rythme */}
      {estimation && (
        <div className="bg-rose-light border border-rose/20 rounded-xl p-4">
          <p className="text-sm text-rose">🏃 {estimation}</p>
        </div>
      )}

      {/* Jalons */}
      <div className="space-y-3">
        {JALONS.map(j => {
          const atteint = heures >= j.seuil;
          const restant = Math.max(0, j.seuil - heures);
          // Sans le flag récompenses : libellé neutre (palier d'heures), pas de
          // promesse d'avantage concret qui n'existe pas encore.
          const titre = recompensesActives ? j.titre : `Palier ${j.seuil}h franchi`;
          return (
            <div key={j.seuil} className={`card-base ${atteint ? 'bg-primary/5 border-primary/20' : 'bg-muted/50 border-border opacity-75'}`}>
              <div className="flex items-start gap-3">
                <span className="text-2xl">{atteint ? (recompensesActives ? j.icone : '✅') : '🔒'}</span>
                <div className="flex-1">
                  <p className={`font-semibold text-sm ${atteint ? 'text-foreground' : 'text-muted-foreground'}`}>
                    {atteint ? '✅' : '🔒'} {j.seuil}h — {atteint ? 'Atteint !' : `Dans ${Math.round(restant)}h`}
                  </p>
                  <p className="text-sm text-muted-foreground mt-0.5">{titre}</p>
                  {recompensesActives && <p className="text-xs text-muted-foreground mt-0.5">{j.desc}</p>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
