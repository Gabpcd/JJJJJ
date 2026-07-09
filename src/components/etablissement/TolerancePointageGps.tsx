import { useEffect, useState } from 'react';
import { Loader2, MapPin, Info } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

const MIN = 30;
const MAX = 1000;
const DEFAULT_VALEUR = 100;
const STEP = 10;

/**
 * Section paramètres "Pointage GPS" — slider tolerance_pointage_m (Sprint 5.5 PR 8).
 *
 * Fix P0-4 audit Sprint 5 : la colonne `etablissements.tolerance_pointage_m`
 * existe (CHECK [30, 1000], DEFAULT 100) mais n'avait aucune UI étab pour la
 * régler. Le ScannerQRPointageSoignant et fn_pointer_arrivee utilisent cette
 * valeur pour valider le périmètre GPS.
 *
 * Persiste via fn_modifier_mon_etablissement.
 */
export function TolerancePointageGps() {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [valeur, setValeur] = useState<number>(DEFAULT_VALEUR);
  const [valeurInitiale, setValeurInitiale] = useState<number>(DEFAULT_VALEUR);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const { data } = await supabase.rpc('fn_mon_etablissement_complet' as any);
      if (cancelled) return;
      const v = Number((data as any)?.tolerance_pointage_m ?? DEFAULT_VALEUR);
      const clamped = Math.min(MAX, Math.max(MIN, v));
      setValeur(clamped);
      setValeurInitiale(clamped);
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, []);

  async function sauvegarder() {
    if (valeur < MIN || valeur > MAX) {
      afficherNotification({ type: 'erreur', message: `Tolérance doit être entre ${MIN} et ${MAX} mètres.` });
      return;
    }
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('fn_modifier_tolerance_pointage_etab' as any, {
        p_tolerance_pointage_m: valeur,
      });
      if (error) {
        afficherNotification({ type: 'erreur', message: error.message });
        return;
      }
      const result = data as any;
      if (!result?.success) {
        const message = result?.error || codeErreurFr(result?.error_code) || 'Erreur lors de l\'enregistrement.';
        afficherNotification({ type: 'erreur', message });
        return;
      }
      afficherNotification({ type: 'succes', message: `Tolérance pointage GPS : ${valeur} m enregistrée.` });
      setValeurInitiale(valeur);
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau.' });
    } finally {
      setSaving(false);
    }
  }

  const dirty = valeur !== valeurInitiale;
  const conseil = valeur <= 100
    ? '✅ Zone urbaine — précision GPS standard'
    : valeur <= 300
      ? '⚠️ Zone semi-urbaine ou rurale — tolérance modérée'
      : '🏞️ Grand campus ou zone très étendue — tolérance large';

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <section className="card-base space-y-4">
      <div className="flex items-center gap-2">
        <MapPin className="h-5 w-5 text-primary" />
        <h2 className="text-lg font-bold text-foreground">Tolérance pointage GPS</h2>
      </div>

      <div className="rounded-lg bg-muted/40 p-3 text-xs flex gap-2">
        <Info className="h-4 w-4 shrink-0 text-primary mt-0.5" />
        <div className="space-y-1 text-muted-foreground">
          <p>
            Distance maximale autorisée entre le soignant et l'établissement pour qu'un pointage GPS soit validé.
          </p>
          <p>
            Si vos soignants utilisent le QR code (recommandé), cette valeur sert uniquement à déclencher une alerte si l'écart constaté est anormal.
          </p>
          <p>
            <strong>100 m</strong> recommandé en zone urbaine, <strong>200 m</strong> en zone rurale, <strong>500 m+</strong> pour grands campus.
          </p>
        </div>
      </div>

      {/* Lot 11 : presets 1-tap (Urbain/Rural/Campus) + saisie libre conservée */}
      <div className="flex gap-2" role="group" aria-label="Presets de tolérance">
        {([['Urbain', 100], ['Rural', 200], ['Campus', 500]] as const).map(([nom, m]) => (
          <button
            key={nom}
            type="button"
            onClick={() => setValeur(m)}
            disabled={saving}
            className={`flex-1 rounded-xl border px-3 py-2 text-xs font-medium transition-colors ${
              valeur === m ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:border-primary/40'
            }`}
          >
            {nom}
            <span className="block text-[10px] font-normal">{m} m</span>
          </button>
        ))}
      </div>

      <div className="space-y-3">
        <div className="flex items-baseline justify-between">
          <label htmlFor="tolerance-slider" className="text-sm font-medium text-foreground">
            Tolérance actuelle
          </label>
          <span className="text-2xl font-bold text-primary tabular-nums">
            {valeur} <span className="text-base text-muted-foreground">m</span>
          </span>
        </div>

        <input
          id="tolerance-slider"
          type="range"
          min={MIN}
          max={MAX}
          step={STEP}
          value={valeur}
          onChange={(e) => setValeur(Number(e.target.value))}
          disabled={saving}
          className="w-full accent-primary"
        />

        <div className="flex justify-between text-[11px] text-muted-foreground">
          <span>{MIN} m (zone très précise)</span>
          <span>{MAX} m (max autorisé)</span>
        </div>

        <p className="text-xs text-foreground">{conseil}</p>

        {/* Saisie manuelle alternative au slider */}
        <div className="flex items-center gap-2">
          <label htmlFor="tolerance-input" className="text-xs text-muted-foreground">
            Saisie précise :
          </label>
          <input
            id="tolerance-input"
            type="number"
            min={MIN}
            max={MAX}
            step={STEP}
            value={valeur}
            onChange={(e) => setValeur(Number(e.target.value))}
            disabled={saving}
            className="input-base w-24 text-sm"
          />
          <span className="text-xs text-muted-foreground">mètres</span>
        </div>
      </div>

      <div className="flex gap-2 pt-2">
        <button
          onClick={() => setValeur(valeurInitiale)}
          disabled={!dirty || saving}
          className="btn-secondary text-sm disabled:opacity-50"
        >
          Réinitialiser
        </button>
        <button
          onClick={sauvegarder}
          disabled={!dirty || saving}
          className="btn-primary text-sm disabled:opacity-50 inline-flex items-center justify-center gap-2"
        >
          {saving && <Loader2 className="h-4 w-4 animate-spin" />}
          Enregistrer
        </button>
      </div>
    </section>
  );
}

function codeErreurFr(code?: string): string | null {
  if (!code) return null;
  switch (code) {
    case 'NON_AUTHENTIFIE': return 'Session expirée.';
    case 'NON_AUTORISE': return 'Action non autorisée.';
    case 'VALEUR_REQUISE': return 'Valeur requise.';
    case 'HORS_RANGE': return 'La tolérance doit être entre 30 et 1000 mètres.';
    default: return null;
  }
}
