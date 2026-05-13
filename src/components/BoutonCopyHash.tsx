import { useState } from 'react';
import { Copy, CheckCircle2 } from 'lucide-react';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  hash: string;
  /** Label optionnel (default: "Copier le hash complet") */
  label?: string;
  /** Style: 'button' (default) ou 'icon' (icône seule) */
  variant?: 'button' | 'icon';
}

/**
 * Bouton copier hash dans le presse-papier.
 *
 * Sprint 7 PR 4 — Cosmétique P2 §7.
 *
 * Affichage compact, toast confirmation, fallback gracieux si Clipboard
 * API absente (anciens navigateurs).
 */
export function BoutonCopyHash({ hash, label = 'Copier le hash complet', variant = 'button' }: Props) {
  const { afficherNotification } = useNotification();
  const [copied, setCopied] = useState(false);

  async function copier() {
    try {
      await navigator.clipboard.writeText(hash);
      afficherNotification({ type: 'succes', message: 'Hash copié dans le presse-papier ✓' });
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      afficherNotification({ type: 'erreur', message: 'Impossible de copier — sélectionnez et copiez manuellement.' });
    }
  }

  if (variant === 'icon') {
    return (
      <button
        type="button"
        onClick={copier}
        className="text-muted-foreground hover:text-primary"
        aria-label={label}
      >
        {copied ? <CheckCircle2 className="h-3.5 w-3.5 text-success" /> : <Copy className="h-3.5 w-3.5" />}
      </button>
    );
  }

  return (
    <button
      type="button"
      onClick={copier}
      className="btn-secondary text-xs inline-flex items-center gap-1"
    >
      {copied ? <CheckCircle2 className="h-3.5 w-3.5 text-success" /> : <Copy className="h-3.5 w-3.5" />}
      {copied ? 'Copié ✓' : label}
    </button>
  );
}
