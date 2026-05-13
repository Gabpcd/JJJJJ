import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileSignature, CheckCircle2, AlertCircle, ChevronRight } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

/**
 * Bannière statut mandat de facturation soignant.
 *
 * Sprint 6 PR 10 — Fix P1-13 audit Sprint 5.
 *
 * Affichage compact du statut du mandat de facturation (Voie A factor) :
 * - NON_SIGNÉ → bannière warning avec CTA "Signer maintenant"
 * - SIGNÉ → bannière success avec date signature + version
 * - VERSION OBSOLÈTE → bannière warning "Re-signer"
 *
 * Click → /soignant/mandat-facturation (page existante).
 */
export function BannerMandatFacturation() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [signe, setSigne] = useState<boolean>(false);
  const [dateSignature, setDateSignature] = useState<string | null>(null);
  const [version, setVersion] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const { data: { user } } = await supabase.auth.getUser();
      if (cancelled || !user) { setLoading(false); return; }
      const { data } = await supabase
        .from('soignants')
        .select('mandat_facturation_signe, mandat_facturation_signe_le, mandat_facturation_version')
        .eq('id', user.id)
        .maybeSingle();
      if (cancelled) return;
      const row = data as any;
      setSigne(!!row?.mandat_facturation_signe);
      setDateSignature(row?.mandat_facturation_signe_le || null);
      setVersion(row?.mandat_facturation_version || null);
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, []);

  if (loading) return null;

  if (!signe) {
    return (
      <button
        type="button"
        onClick={() => navigate('/soignant/mandat-facturation')}
        className="w-full rounded-2xl border-2 border-warning/40 bg-warning/5 p-4 text-left hover:bg-warning/10 transition-colors"
      >
        <div className="flex items-start gap-3">
          <FileSignature className="h-6 w-6 text-warning shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">Mandat de facturation à signer</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Nécessaire pour activer le factor (avances rapides sur factures honoraires).
            </p>
          </div>
          <ChevronRight className="h-5 w-5 text-muted-foreground shrink-0 self-center" />
        </div>
      </button>
    );
  }

  return (
    <button
      type="button"
      onClick={() => navigate('/soignant/mandat-facturation')}
      className="w-full rounded-2xl border-2 border-success/30 bg-success/5 p-4 text-left hover:bg-success/10 transition-colors"
    >
      <div className="flex items-start gap-3">
        <CheckCircle2 className="h-6 w-6 text-success shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground inline-flex items-center gap-2">
            Mandat de facturation signé ✓
            {version && (
              <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono">
                v{version}
              </span>
            )}
          </p>
          {dateSignature && (
            <p className="text-xs text-muted-foreground mt-0.5">
              Signé le {format(new Date(dateSignature), 'd MMMM yyyy', { locale: fr })}.
              Cliquez pour télécharger le PDF ou résilier.
            </p>
          )}
        </div>
        <ChevronRight className="h-5 w-5 text-muted-foreground shrink-0 self-center" />
      </div>
    </button>
  );
}
