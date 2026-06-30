import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Star, X, ArrowRight } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Props {
  role: 'SOIGNANT' | 'ETAB';
  /** Lien quand on clique "Voir" — par défaut /soignant/missions ou /etablissement/missions */
  liensMissionsRoute?: string;
}

const SEUIL_AFFICHAGE = 3;
const STORAGE_KEY_PREFIX = 'jolene.banner_notation_dismiss_';
const REAPPARITION_JOURS = 7;

export function BannerEncourageNotation({ role, liensMissionsRoute }: Props) {
  const navigate = useNavigate();
  const [count, setCount] = useState<number | null>(null);
  const [hidden, setHidden] = useState(false);

  const storageKey = STORAGE_KEY_PREFIX + role;

  useEffect(() => {
    // Check si dismissed récemment
    try {
      const dismissedAt = localStorage.getItem(storageKey);
      if (dismissedAt) {
        const since = (Date.now() - parseInt(dismissedAt, 10)) / (1000 * 60 * 60 * 24);
        if (since < REAPPARITION_JOURS) {
          setHidden(true);
          return;
        }
      }
    } catch { /* noop */ }

    let alive = true;
    (async () => {
      const { data } = await supabase.rpc('fn_compter_missions_sans_notation' as any, { p_role: role });
      if (!alive) return;
      const payload = data as any;
      if (payload?.count != null) setCount(Number(payload.count));
    })();
    return () => { alive = false; };
  }, [role, storageKey]);

  const dismiss = () => {
    try { localStorage.setItem(storageKey, String(Date.now())); } catch { /* noop */ }
    setHidden(true);
  };

  if (hidden || count == null || count < SEUIL_AFFICHAGE) return null;

  const route = liensMissionsRoute ?? (role === 'SOIGNANT' ? '/soignant/missions?onglet=mes_missions' : '/etablissement/missions');

  return (
    <div className="card-base border-l-4 border-l-amber-400 bg-amber-50/40 dark:bg-amber-950/10 mb-4">
      <div className="flex items-start gap-3">
        <Star className="h-5 w-5 text-amber-500 shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground">
            {count} mission{count > 1 ? 's' : ''} terminée{count > 1 ? 's' : ''} sans notation
          </p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {role === 'SOIGNANT'
              ? 'Tes notations aident les autres soignants à choisir leurs missions et améliorent ton propre score (composante "Notation par soignant").'
              : 'Vos notations enrichissent les profils soignants et alimentent leur score de fiabilité.'}
          </p>
          <button
            type="button"
            onClick={() => navigate(route)}
            className="btn-primary text-xs inline-flex items-center gap-1.5 mt-3"
          >
            Voir mes missions <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
        <button onClick={dismiss} aria-label="Masquer" className="p-1 hover:bg-muted/50 rounded-lg">
          <X className="h-4 w-4 text-muted-foreground" />
        </button>
      </div>
    </div>
  );
}
