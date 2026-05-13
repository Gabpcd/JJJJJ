import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, MapPin, Smartphone, Clock, ChevronRight, ShieldAlert } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface KPI {
  teleportations_24h: number;
  teleportations_7j: number;
  teleportations_30j: number;
  mock_gps_24h: number;
  mock_gps_7j: number;
  mock_gps_30j: number;
  coherence_24h: number;
  coherence_7j: number;
  coherence_30j: number;
  qr_gps_eloigne_24h: number;
  qr_gps_eloigne_7j: number;
  qr_gps_eloigne_30j: number;
  total_ouvertes: number;
}

type Periode = '24h' | '7j' | '30j';

/**
 * Bandeau alertes anti-triche Sprint 4.5 affiché sur AdminDashboard.
 *
 * Sprint 6 PR 8 — Fix P1-10 audit Sprint 5 (étend Sprint 5.7 PR 10).
 *
 * Toggle période 24h / 7j / 30j pour vue rapide ou plus longue.
 * Couleur destructive + badge ATTENTION si total_ouvertes > 5.
 * Click ouvre /admin/alertes-pointage filtré sur statut=OUVERTE.
 */
export function BandeauAlertesAntiTricheAdmin() {
  const navigate = useNavigate();
  const [kpi, setKpi] = useState<KPI | null>(null);
  const [loading, setLoading] = useState(true);
  const [periode, setPeriode] = useState<Periode>('7j');

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

  // Sélection des valeurs selon période
  const teleportations = kpi[`teleportations_${periode}` as keyof KPI] as number;
  const mockGps = kpi[`mock_gps_${periode}` as keyof KPI] as number;
  const coherence = kpi[`coherence_${periode}` as keyof KPI] as number;
  const qrGpsEloigne = kpi[`qr_gps_eloigne_${periode}` as keyof KPI] as number;
  const total = teleportations + mockGps + coherence + qrGpsEloigne;

  if (total === 0 && kpi.total_ouvertes === 0) return null;

  const isCritical = kpi.total_ouvertes > 5;
  const periodeLabel = periode === '24h' ? '24 dernières heures' : periode === '7j' ? '7 derniers jours' : '30 derniers jours';

  return (
    <div
      className={`w-full rounded-2xl border-2 p-4 transition-colors mb-4 ${
        isCritical ? 'border-destructive/40 bg-destructive/5' : 'border-warning/40 bg-warning/5'
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
          <div className="flex items-center gap-2 flex-wrap mb-1">
            <p className="text-sm font-semibold text-foreground">
              Alertes anti-triche pointage ({periodeLabel})
            </p>
            {isCritical && (
              <span className="text-[11px] px-2 py-0.5 rounded-full bg-destructive text-destructive-foreground font-medium">
                ATTENTION
              </span>
            )}
          </div>

          {/* Toggle période */}
          <div role="tablist" aria-label="Période" className="inline-flex gap-1 mb-2">
            {(['24h', '7j', '30j'] as Periode[]).map((p) => (
              <button
                key={p}
                type="button"
                role="tab"
                aria-selected={periode === p}
                onClick={(e) => { e.stopPropagation(); setPeriode(p); }}
                className={`text-[11px] px-2 py-0.5 rounded-full border ${
                  periode === p
                    ? 'border-primary bg-primary text-primary-foreground'
                    : 'border-border bg-background hover:border-primary/40'
                }`}
              >
                {p}
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={() => navigate('/admin/alertes-pointage?statut=OUVERTE')}
            className="block w-full text-left hover:opacity-90"
          >
            <p className="text-xs text-muted-foreground mt-0.5">
              {kpi.total_ouvertes} alerte{kpi.total_ouvertes > 1 ? 's' : ''} ouverte{kpi.total_ouvertes > 1 ? 's' : ''} à traiter →
            </p>
            <div className="flex flex-wrap gap-3 mt-2 text-xs">
              {teleportations > 0 && (
                <span className="inline-flex items-center gap-1 text-destructive">
                  <MapPin className="h-3 w-3" /> {teleportations} téléportation{teleportations > 1 ? 's' : ''}
                </span>
              )}
              {mockGps > 0 && (
                <span className="inline-flex items-center gap-1 text-warning">
                  <Smartphone className="h-3 w-3" /> {mockGps} mock GPS
                </span>
              )}
              {coherence > 0 && (
                <span className="inline-flex items-center gap-1 text-warning">
                  <Clock className="h-3 w-3" /> {coherence} cohérence
                </span>
              )}
              {qrGpsEloigne > 0 && (
                <span className="inline-flex items-center gap-1 text-info">
                  <MapPin className="h-3 w-3" /> {qrGpsEloigne} QR &gt; 1km
                </span>
              )}
              {total === 0 && (
                <span className="text-muted-foreground italic">
                  Aucun signal sur {periodeLabel}.
                </span>
              )}
            </div>
          </button>
        </div>
        <ChevronRight className="h-5 w-5 text-muted-foreground shrink-0 self-center" />
      </div>
    </div>
  );
}
