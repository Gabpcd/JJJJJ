import React, { useEffect, useRef, useId } from 'react';
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
  const dialogRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const titleId = useId();
  const descId = useId();

  // Focus trap + escape key + focus restoration
  useEffect(() => {
    if (!ouvert) return;
    previousFocusRef.current = document.activeElement as HTMLElement | null;

    // Focus initial : 1er élément focusable de la modale
    const focusables = dialogRef.current?.querySelectorAll<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );
    focusables?.[0]?.focus();

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onFermer();
        return;
      }
      if (e.key === 'Tab' && focusables && focusables.length > 0) {
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      // Restaurer focus sur élément précédent à la fermeture
      previousFocusRef.current?.focus();
    };
  }, [ouvert, onFermer]);

  if (!ouvert) return null;

  return (
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={descId}
    >
      <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onFermer} aria-hidden="true" />
      <div
        ref={dialogRef}
        className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-[calc(100%-2rem)]"
      >
        <button
          onClick={onFermer}
          className="absolute top-4 right-4 text-muted-foreground hover:text-foreground"
          aria-label="Fermer la fenêtre"
          type="button"
        >
          <X className="h-5 w-5" aria-hidden="true" />
        </button>
        <h3 id={titleId} className="text-lg font-bold text-foreground mb-2">{titre}</h3>
        <p id={descId} className="text-sm text-muted-foreground mb-6">{message}</p>
        <div className="flex gap-3 justify-end">
          <button onClick={onFermer} className="btn-secondary text-sm px-4 py-2" type="button">
            {labelAnnuler}
          </button>
          <button
            onClick={() => { onConfirmer(); onFermer(); }}
            className={variante === 'danger' ? 'btn-danger text-sm px-4 py-2' : 'btn-primary text-sm px-4 py-2'}
            type="button"
          >
            {labelConfirmer}
          </button>
        </div>
      </div>
    </div>
  );
}
