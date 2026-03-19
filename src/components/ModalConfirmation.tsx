import React from 'react';
import { X } from 'lucide-react';

interface ModalConfirmationProps {
  ouvert: boolean;
  onFermer: () => void;
  onConfirmer: () => void;
  titre: string;
  message: string;
  labelConfirmer?: string;
  labelAnnuler?: string;
  variante?: 'primaire' | 'danger';
}

export function ModalConfirmation({
  ouvert,
  onFermer,
  onConfirmer,
  titre,
  message,
  labelConfirmer = 'Confirmer',
  labelAnnuler = 'Annuler',
  variante = 'primaire',
}: ModalConfirmationProps) {
  if (!ouvert) return null;

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center">
      <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onFermer} />
      <div className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-[calc(100%-2rem)]">
        <button onClick={onFermer} className="absolute top-4 right-4 text-muted-foreground hover:text-foreground">
          <X className="h-5 w-5" />
        </button>
        <h3 className="text-lg font-bold text-foreground mb-2">{titre}</h3>
        <p className="text-sm text-muted-foreground mb-6">{message}</p>
        <div className="flex gap-3 justify-end">
          <button onClick={onFermer} className="btn-secondary text-sm px-4 py-2">
            {labelAnnuler}
          </button>
          <button
            onClick={() => { onConfirmer(); onFermer(); }}
            className={variante === 'danger' ? 'btn-danger text-sm px-4 py-2' : 'btn-primary text-sm px-4 py-2'}
          >
            {labelConfirmer}
          </button>
        </div>
      </div>
    </div>
  );
}
