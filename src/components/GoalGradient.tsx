import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';

interface Jalon {
  seuil: number;
  label: string;
  avantage: string;
}

const JALONS: Jalon[] = [
  { seuil: 800, label: '800h', avantage: 'Formations en ligne offertes' },
  { seuil: 1600, label: '1 600h', avantage: 'Réduction assurance RCP' },
  { seuil: 2400, label: '2 400h', avantage: 'Accompagnement installation' },
  { seuil: 3200, label: '3 200h', avantage: 'Kit complet installation libérale' },
];

interface CelebrationJalonProps {
  jalon: Jalon;
  onTermine: () => void;
}

function CelebrationJalon({ jalon, onTermine }: CelebrationJalonProps) {
  const navigate = useNavigate();

  useEffect(() => {
    const timer = setTimeout(() => {
      onTermine();
      navigate('/soignant/parcours-3200h');
    }, 4000);
    return () => clearTimeout(timer);
  }, [onTermine, navigate]);

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-card/95">
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        {Array.from({ length: 24 }).map((_, i) => (
          <div
            key={i}
            className="confetti-piece"
            style={{
              left: `${Math.random() * 100}%`,
              animationDelay: `${Math.random() * 1.5}s`,
              animationDuration: `${2 + Math.random() * 2}s`,
              backgroundColor: ['hsl(var(--primary))', 'hsl(var(--success))', 'hsl(var(--warning))', '#8b5cf6'][i % 4],
            }}
          />
        ))}
      </div>
      <div className="text-center z-10 animate-bounce-in">
        <div className="text-6xl mb-4">🎉</div>
        <h2 className="text-2xl font-bold text-foreground mb-3">Félicitations !</h2>
        <p className="text-lg text-foreground mb-2">Vous avez atteint <span className="font-bold text-primary">{jalon.label}</span> !</p>
        <p className="text-muted-foreground mb-4">🎁 {jalon.avantage}</p>
        <button onClick={() => { onTermine(); navigate('/soignant/parcours-3200h'); }} className="text-sm text-primary font-semibold hover:underline">
          Découvrir mon avantage →
        </button>
      </div>
    </div>
  );
}

interface BandeauGoalGradientProps {
  heures: number;
}

export function BandeauGoalGradient({ heures }: BandeauGoalGradientProps) {
  const navigate = useNavigate();
  const prochainJalon = JALONS.find(j => heures < j.seuil);
  const heuresRestantes = prochainJalon ? prochainJalon.seuil - heures : 0;
  const estProche = heuresRestantes > 0 && heuresRestantes <= 50;

  if (!estProche || !prochainJalon) return null;

  return (
    <div className="bg-gradient-to-r from-amber-50 to-orange-50 border-2 border-amber-300 rounded-2xl p-5 mb-6 animate-pulse-once">
      <p className="text-base font-bold text-foreground mb-1">🔥 Plus que {Math.round(heuresRestantes)}h avant le jalon {prochainJalon.label} !</p>
      <p className="text-sm text-muted-foreground mb-2">🎁 Avantage à débloquer : {prochainJalon.avantage}</p>
      <p className="text-sm text-muted-foreground mb-3">Encore ~{Math.ceil(heuresRestantes / 12)} mission{Math.ceil(heuresRestantes / 12) > 1 ? 's' : ''} de 12h pour y arriver !</p>
      <button onClick={() => navigate('/soignant/missions')} className="text-sm text-primary font-semibold hover:underline">
        Voir les missions disponibles →
      </button>
    </div>
  );
}

interface GoalGradientMissionProps {
  heures: number;
  dureeHeuresMission: number;
}

export function GoalGradientMission({ heures, dureeHeuresMission }: GoalGradientMissionProps) {
  const prochainJalon = JALONS.find(j => heures < j.seuil);
  const heuresRestantes = prochainJalon ? prochainJalon.seuil - heures : 0;
  const estProche = heuresRestantes > 0 && heuresRestantes <= 50;

  if (!estProche || !prochainJalon) return null;

  return (
    <div className="text-sm text-amber-700 bg-amber-50 rounded-lg p-2 mb-3">
      🔥 Accepter cette mission vous rapproche de {prochainJalon.label} ! Plus que {Math.round(heuresRestantes - dureeHeuresMission)}h après cette mission.
    </div>
  );
}

interface CelebrationJalonManagerProps {
  heures: number;
}

export function CelebrationJalonManager({ heures }: CelebrationJalonManagerProps) {
  const [jalonCelebration, setJalonCelebration] = useState<Jalon | null>(null);

  useEffect(() => {
    const dernierJalonVu = parseInt(localStorage.getItem('dernier_jalon_vu') || '0');
    const jalonsAtteints = JALONS.filter(j => heures >= j.seuil && j.seuil > dernierJalonVu);
    if (jalonsAtteints.length > 0) {
      const dernierAtteint = jalonsAtteints[jalonsAtteints.length - 1];
      localStorage.setItem('dernier_jalon_vu', String(dernierAtteint.seuil));
      setJalonCelebration(dernierAtteint);
    }
  }, [heures]);

  if (!jalonCelebration) return null;
  return <CelebrationJalon jalon={jalonCelebration} onTermine={() => setJalonCelebration(null)} />;
}
