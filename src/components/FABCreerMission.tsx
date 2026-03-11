import { Plus } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export function FABCreerMission() {
  const navigate = useNavigate();
  return (
    <button
      onClick={() => navigate('/etablissement/missions/creer')}
      className="md:hidden fixed bottom-20 right-4 z-40 bg-primary text-primary-foreground rounded-full w-14 h-14 shadow-xl flex items-center justify-center hover:scale-110 active:scale-95 transition-transform"
      aria-label="Créer une mission"
    >
      <Plus className="h-8 w-8" />
    </button>
  );
}
