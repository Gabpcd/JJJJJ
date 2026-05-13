import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, MapPin, Smartphone, Clock, ChevronRight, ShieldAlert } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface KPI {
  teleportations_7j: number;
  mock_gps_7j: number;
  coherence_7j: number;
  qr_gps_eloigne_7j: number;
  total_ouvertes: number;
}

/**
 * Bandeau alertes anti-triche Sprint 4.5 affiché sur AdminDashboard.
 *
 * Fix P0-11 audit Sprint 5 (Sprint 5.7 PR 10).
 *
 * Affiche un récap visuel des 4 types d'alertes anti-triche détectées
 * sur les 7 derniers jours. Couleur rouge si total ouvertes > 5.
 *
 * Lien direct vers /admin/alertes-pointage pour traitement détaillé.
 */
export function BandeauAlertesAntiTricheAdmin() {
  const navigate = useNavigate();
  const [kpi, setKpi] = useState<KPI | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    supabase.rpc('fn_admin_resume_alertes_pointage' as any).then(({ data }) => {
      if (cancelled) return;
      const result = data as any;
      if (result?.success) {
        setKpi(result.kpis as KPI);
      }
      setLoading(false);
    });
    return () => { cancelled = true; };
  }, []);

  if (loading || !kpi) return null;

  const total = kpi.teleportations_7j + kpi.mock_gps_7j + kpi.coherence_7j + kpi.qr_gps_eloigne_7j;
  if (total === 0) return null;

  const isCritical = kpi.total_ouvertes > 5;

  return (
    <button
      onClick={() => navigate('/admin/alertes-pointage')}
      className={`w-full rounded-2xl border-2 p-4 text-left transition-colors mb-4 hover:opacity-90 ${
        isCritical
          ? 'border-destructive/40 bg-destructive/5'
          : 'border-warning/40 bg-warning/5'
      }`}
    >
      <div className="flex items-start gap-3">
        <div className="shrink-0">
          {isCritical ? (
            <ShieldAlert className="h-6 w-6 text-destructive" />
          ) : (
            <AlertTriangle className="h-6 w-6 text-warning" />
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="text-sm font-semibold text-foreground">
              Alertes anti-triche pointage (7 derniers jours)
            </p>
            {isCritical && (
              <span className="text-[11px] px-2 py-0.5 rounded-full bg-destructive text-destructive-foreground font-medium">
                ATTENTION
              </span>
            )}
          </div>
          <p className="text-xs text-muted-foreground mt-0.5">
            {kpi.total_ouvertes} alerte{kpi.total_ouvertes > 1 ? 's' : ''} ouverte{kpi.total_ouvertes > 1 ? 's' : ''} à traiter.
          </p>
          <div className="flex flex-wrap gap-3 mt-2 text-xs">
            {kpi.teleportations_7j > 0 && (
              <span className="inline-flex items-center gap-1 text-destructive">
                <MapPin className="h-3 w-3" /> {kpi.teleportations_7j} téléportation{kpi.teleportations_7j > 1 ? 's' : ''}
              </span>
            )}
            {kpi.mock_gps_7j > 0 && (
              <span className="inline-flex items-center gap-1 text-warning">
                <Smartphone className="h-3 w-3" /> {kpi.mock_gps_7j} mock GPS
              </span>
            )}
            {kpi.coherence_7j > 0 && (
              <span className="inline-flex items-center gap-1 text-warning">
                <Clock className="h-3 w-3" /> {kpi.coherence_7j} cohérence
              </span>
            )}
            {kpi.qr_gps_eloigne_7j > 0 && (
              <span className="inline-flex items-center gap-1 text-info">
                <MapPin className="h-3 w-3" /> {kpi.qr_gps_eloigne_7j} QR &gt; 1km
              </span>
            )}
          </div>
        </div>
        <ChevronRight className="h-5 w-5 text-muted-foreground shrink-0 self-center" />
      </div>
    </button>
  );
}
