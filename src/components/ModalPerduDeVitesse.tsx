import { X } from 'lucide-react';

interface ModalPerduDeVitesseProps {
  onFermer: () => void;
  onVoirAutres: () => void;
}

export function ModalPerduDeVitesse({ onFermer, onVoirAutres }: ModalPerduDeVitesseProps) {
  return (
    <div className="fixed inset-0 z-[200] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onFermer} />
      <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-sm w-full text-center">
        <button onClick={onFermer} className="absolute top-4 right-4 text-muted-foreground hover:text-foreground">
          <X className="h-5 w-5" />
        </button>

        <div className="text-5xl mb-4">😅</div>
        <h3 className="text-lg font-bold text-foreground mb-2">
          Mince, un(e) confrère a été plus rapide !
        </h3>
        <p className="text-sm text-muted-foreground mb-6">
          Cette mission vient d'être attribuée à un autre soignant.
          Ne baissez pas les bras — de nouvelles missions arrivent en continu.
        </p>

        <div className="flex gap-3">
          <button onClick={onFermer} className="btn-secondary text-sm flex-1 py-2.5">
            Fermer
          </button>
          <button onClick={onVoirAutres} className="btn-primary text-sm flex-1 py-2.5">
            Voir d'autres missions
          </button>
        </div>
      </div>
    </div>
  );
}
