import { useState, useEffect } from 'react';
import { Loader2, MapPin, ShieldCheck } from 'lucide-react';
import { aConsenti, setConsentement } from '@/lib/background-geoloc';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  onClose?: () => void;
}

/**
 * Page consentement RGPD ping GPS background (Sprint 4.5 PR 10).
 *
 * Affiche les finalités, durée de conservation, droit de retrait,
 * et collecte un consentement explicite (case à cocher requise).
 */
export function ConsentementPingGps({ onClose }: Props) {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [actuel, setActuel] = useState(false);
  const [coche, setCoche] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    aConsenti().then((v) => {
      setActuel(v);
      setCoche(v);
      setLoading(false);
    });
  }, []);

  async function enregistrer() {
    if (coche === actuel) {
      onClose?.();
      return;
    }
    setSaving(true);
    const res = await setConsentement(coche);
    setSaving(false);
    if (!res.success) {
      afficherNotification({ type: 'erreur', message: res.error || 'Erreur enregistrement' });
      return;
    }
    setActuel(coche);
    afficherNotification({
      type: 'succes',
      message: coche ? 'Consentement enregistré' : 'Consentement retiré',
    });
    onClose?.();
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-4 p-6">
      <div className="flex items-center gap-3">
        <MapPin className="h-8 w-8 text-primary" />
        <div>
          <h2 className="text-lg font-bold text-foreground">Suivi GPS pendant mission</h2>
          <p className="text-xs text-muted-foreground">Option facultative — vous pouvez la retirer à tout moment.</p>
        </div>
      </div>

      <div className="space-y-3 text-sm text-foreground">
        <p>
          Pour renforcer la fiabilité du pointage et faciliter la gestion des litiges horaires,
          Jolene peut enregistrer votre position GPS toutes les minutes pendant la durée de votre mission.
        </p>

        <div className="rounded-lg bg-muted/50 border border-border p-3 space-y-2 text-xs">
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 shrink-0 text-primary mt-0.5" />
            <span><strong>Finalité :</strong> preuve d'arrivée et de présence en cas de litige.</span>
          </div>
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 shrink-0 text-primary mt-0.5" />
            <span><strong>Données :</strong> latitude, longitude, précision, vitesse, horodatage.</span>
          </div>
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 shrink-0 text-primary mt-0.5" />
            <span><strong>Durée :</strong> 30 jours puis suppression automatique.</span>
          </div>
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 shrink-0 text-primary mt-0.5" />
            <span><strong>Périmètre :</strong> uniquement pendant la fenêtre de mission active. Désactivé en dehors.</span>
          </div>
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 shrink-0 text-primary mt-0.5" />
            <span><strong>Accès :</strong> vous-même, l'établissement employeur, et l'administration Jolene en cas de litige.</span>
          </div>
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 shrink-0 text-primary mt-0.5" />
            <span><strong>Retrait :</strong> à tout moment via ce même écran. Aucune conséquence sur vos missions.</span>
          </div>
        </div>
      </div>

      <label className="flex items-start gap-3 rounded-lg border border-border bg-background p-3 cursor-pointer hover:border-primary">
        <input
          type="checkbox"
          checked={coche}
          onChange={(e) => setCoche(e.target.checked)}
          className="mt-1 h-4 w-4 rounded border-border"
          disabled={saving}
        />
        <span className="text-sm text-foreground">
          J'autorise Jolene à enregistrer ma position GPS pendant mes missions actives, pour 30 jours.
        </span>
      </label>

      <div className="flex gap-2 pt-2">
        {onClose && (
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            className="flex-1 rounded-lg border border-border bg-background py-2 text-sm font-medium text-foreground hover:bg-muted disabled:opacity-50"
          >
            Annuler
          </button>
        )}
        <button
          type="button"
          onClick={enregistrer}
          disabled={saving}
          className="btn-primary flex-1 inline-flex items-center justify-center gap-2 disabled:opacity-50"
        >
          {saving && <Loader2 className="h-4 w-4 animate-spin" />}
          Enregistrer
        </button>
      </div>
    </div>
  );
}
