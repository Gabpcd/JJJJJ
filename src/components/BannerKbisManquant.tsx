import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileUp, ChevronRight, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

/**
 * Bannière "KBIS manquant" pour l'étab — Sprint 6 PR 11 (P1-14).
 *
 * Vérifie si l'étab a uploadé son KBIS dans documents_etablissement.
 * Sinon, affiche une bannière proactive avec CTA vers la page documents.
 *
 * Dismissible via localStorage (24h) pour ne pas spammer l'étab.
 */
export function BannerKbisManquant() {
  const navigate = useNavigate();
  const { etablissementId } = useEtablissementScope();
  const [loading, setLoading] = useState(true);
  const [hasKbis, setHasKbis] = useState<boolean | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    if (!etablissementId) { setLoading(false); return; }

    const dismissKey = `kbis_dismissed_${etablissementId}`;
    const dismissAt = localStorage.getItem(dismissKey);
    if (dismissAt && Date.now() - Number(dismissAt) < 24 * 3600 * 1000) {
      setDismissed(true);
      setLoading(false);
      return;
    }

    async function check() {
      const { data } = await (supabase as any)
        .from('documents_etablissement')
        .select('id')
        .eq('etablissement_id', etablissementId)
        .eq('type_document', 'KBIS')
        .limit(1);
      if (cancelled) return;
      setHasKbis(Array.isArray(data) && data.length > 0);
      setLoading(false);
    }
    check();
    return () => { cancelled = true; };
  }, [etablissementId]);

  if (loading || dismissed || hasKbis !== false) return null;

  function dismiss() {
    if (etablissementId) {
      localStorage.setItem(`kbis_dismissed_${etablissementId}`, Date.now().toString());
    }
    setDismissed(true);
  }

  return (
    <div className="w-full rounded-2xl border-2 border-warning/40 bg-warning/5 p-4 mb-4 flex items-start gap-3">
      <FileUp className="h-6 w-6 text-warning shrink-0" />
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-foreground">KBIS manquant</p>
        <p className="text-xs text-muted-foreground mt-0.5">
          Ajoutez votre extrait KBIS (moins de 3 mois) pour valider votre profil et débloquer toutes les fonctionnalités.
        </p>
        <button
          type="button"
          onClick={() => navigate('/etablissement/parametres?tab=profil')}
          className="mt-2 text-xs font-medium text-warning hover:underline inline-flex items-center gap-1"
        >
          Ajouter mon KBIS <ChevronRight className="h-3 w-3" />
        </button>
      </div>
      <button
        type="button"
        onClick={dismiss}
        className="text-muted-foreground hover:text-foreground"
        aria-label="Masquer 24h"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}
