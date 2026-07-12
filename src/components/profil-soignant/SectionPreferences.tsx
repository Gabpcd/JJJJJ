import { Switch } from '@/components/ui/switch';
import { CONTRATS } from '@/lib/constantes';
import { PoolUrgenceToggle } from '@/components/PoolUrgenceToggle';
import { SectionBio } from '@/components/SectionBio';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { useRole } from '@/hooks/useRole';
import { extraireMessageErreur } from '@/lib/erreurs';

interface Props {
  userId: string;
  bio: string;
  onBioChange: (val: string) => void;
  anneesExperience: number;
  onAnneesChange: (val: number) => void;
  specialites: string[];
  onSpecialitesChange: (vals: string[]) => void;
  typesContrat: string[];
  onToggleContrat: (valeur: string) => void;
  rayon: number;
  onRayonChange: (val: number) => void;
  tauxHoraireMinimum: number | null;
  onTauxChange: (val: number | null) => void;
  poolUrgenceActif: boolean;
  poolUrgenceRayon: number;
  onPoolUrgenceUpdate: (actif: boolean, rayon: number) => void;
  consentementGPS: boolean;
  onConsentementGPSChange: (val: boolean) => void;
  gpsToggling: boolean;
  setGpsToggling: (val: boolean) => void;
  consentementSMS: boolean;
  onConsentementSMSChange: (val: boolean) => void;
  smsToggling: boolean;
  setSmsToggling: (val: boolean) => void;
}

export function SectionPreferences(props: Props) {
  const {
    userId, bio, onBioChange, anneesExperience, onAnneesChange,
    specialites, onSpecialitesChange,
    typesContrat, onToggleContrat,
    rayon, onRayonChange,
    tauxHoraireMinimum, onTauxChange,
    poolUrgenceActif, poolUrgenceRayon, onPoolUrgenceUpdate,
    consentementGPS, onConsentementGPSChange, gpsToggling, setGpsToggling,
    consentementSMS, onConsentementSMSChange, smsToggling, setSmsToggling,
  } = props;
  const { afficherNotification } = useNotification();
  const { role } = useRole();

  return (
    <div className="space-y-4">
      <SectionBio
        bio={bio}
        onBioChange={onBioChange}
        anneesExperience={anneesExperience}
        onAnneesChange={onAnneesChange}
        specialites={specialites}
        onSpecialitesChange={onSpecialitesChange}
      />

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-2">Types de contrat acceptés</h2>
        <p className="text-xs text-muted-foreground mb-3">Coche tous les types de contrat que tu acceptes.</p>
        <div className="space-y-2">
          {CONTRATS.map((c) => (
            <label key={c.valeur} className="flex items-center gap-3 cursor-pointer group">
              <input
                type="checkbox"
                checked={typesContrat.includes(c.valeur)}
                onChange={() => onToggleContrat(c.valeur)}
                className="h-4 w-4 rounded border-border text-primary focus:ring-primary accent-primary"
              />
              <span className="text-sm text-foreground group-hover:text-primary transition-colors">{c.label}</span>
            </label>
          ))}
        </div>
        {typesContrat.length === 0 && (
          <p className="text-xs text-destructive mt-1">Sélectionne au moins un type de contrat</p>
        )}
      </div>

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-2">💰 Taux horaire minimum accepté</h2>
        <p className="text-xs text-muted-foreground mb-3">Les missions en dessous de ce taux seront grisées dans tes résultats.</p>
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm text-foreground font-medium">
              {tauxHoraireMinimum ? `${tauxHoraireMinimum} €/h` : 'Non défini'}
            </span>
            {tauxHoraireMinimum && (
              <button type="button" onClick={() => onTauxChange(null)} className="text-xs text-destructive hover:underline">
                Supprimer
              </button>
            )}
          </div>
          <input
            type="range"
            aria-label="Taux horaire minimum accepté"
            aria-valuetext={tauxHoraireMinimum ? `${tauxHoraireMinimum} euros par heure` : 'Non défini'}
            min={10}
            max={100}
            step={1}
            value={tauxHoraireMinimum ?? 10}
            onChange={(e) => onTauxChange(Number(e.target.value))}
            className="w-full accent-primary"
          />
          <div className="flex justify-between text-[10px] text-muted-foreground">
            <span>10 €/h</span><span>100 €/h</span>
          </div>
        </div>
      </div>

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-2">📍 Rayon de déplacement</h2>
        <p className="text-xs text-muted-foreground mb-3">Distance maximale jusqu'aux missions proposées.</p>
        <label className="text-sm font-medium text-foreground mb-1.5 block">
          Rayon : <span className="text-primary font-bold">{rayon} km</span>
        </label>
        <input
          type="range"
          aria-label="Rayon de déplacement"
          aria-valuetext={`${rayon} kilomètres`}
          min={5}
          max={100}
          value={rayon}
          onChange={(e) => onRayonChange(Number(e.target.value))}
          className="w-full accent-primary"
        />
        <div className="flex justify-between text-[10px] text-muted-foreground"><span>5 km</span><span>100 km</span></div>
      </div>

      <PoolUrgenceToggle
        actif={poolUrgenceActif}
        rayonKm={poolUrgenceRayon}
        onUpdate={(a, r) => onPoolUrgenceUpdate(a, r)}
        onError={(msg) => afficherNotification({ type: 'erreur', message: msg })}
        onSuccess={(msg) => afficherNotification({ type: 'succes', message: msg })}
      />

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4">Consentement GPS</h2>
        <div className="flex items-center justify-between">
          <div className="flex-1">
            <p className="text-sm text-foreground font-medium">Autoriser la géolocalisation lors des pointages</p>
            <p className="text-xs text-muted-foreground mt-1">
              {consentementGPS
                ? 'Ta position sera capturée uniquement au moment de l\'arrivée et du départ.'
                : 'Sans GPS, tes pointages seront validés manuellement par l\'établissement — rien à faire de ton côté.'}
            </p>
          </div>
          <Switch
            aria-label="Autoriser la géolocalisation lors des pointages"
            checked={consentementGPS}
            disabled={gpsToggling}
            onCheckedChange={async (checked) => {
              setGpsToggling(true);
              const { data, error } = await supabase.rpc('fn_consentir_gps' as any, { p_accepte: checked });
              if (error) {
                afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
              } else if (data && (data as any).error) {
                afficherNotification({ type: 'erreur', message: (data as any).error });
              } else {
                onConsentementGPSChange(checked);
                await supabase.rpc('fn_ecrire_audit_safe', {
                  p_acteur_id: userId, p_type_acteur: role || 'SOIGNANT',
                  p_action: checked ? 'GPS_CONSENTEMENT_ACTIVE' : 'GPS_CONSENTEMENT_RETIRE',
                  p_type_ressource: 'soignant', p_id_ressource: userId,
                  p_cle_s3: null, p_details: { consentement_gps: checked },
                  p_ip: null, p_navigateur: navigator.userAgent,
                });
                afficherNotification({
                  type: checked ? 'succes' : 'info',
                  message: checked ? 'Consentement GPS activé.' : 'Consentement GPS retiré — tes pointages seront validés manuellement par l\'établissement.',
                });
              }
              setGpsToggling(false);
            }}
          />
        </div>
      </div>

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4">Notifications SMS</h2>
        <div className="flex items-center justify-between">
          <div className="flex-1">
            <p className="text-sm text-foreground font-medium">Recevoir les alertes par SMS</p>
            <p className="text-xs text-muted-foreground mt-1">
              {consentementSMS
                ? 'Tu recevras un SMS pour les missions urgentes et les annulations tardives.'
                : 'Active pour recevoir les notifications critiques par SMS (missions urgentes, annulations).'}
            </p>
          </div>
          <Switch
            aria-label="Recevoir les alertes par SMS"
            checked={consentementSMS}
            disabled={smsToggling}
            onCheckedChange={async (checked) => {
              setSmsToggling(true);
              const { error } = await supabase
                .from('soignants')
                .update({ sms_actif: checked, sms_consent_le: checked ? new Date().toISOString() : null })
                .eq('id', userId);
              if (error) {
                afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
              } else {
                onConsentementSMSChange(checked);
                await supabase.rpc('fn_ecrire_audit_safe', {
                  p_acteur_id: userId, p_type_acteur: role || 'SOIGNANT',
                  p_action: checked ? 'SMS_CONSENTEMENT_ACTIVE' : 'SMS_CONSENTEMENT_RETIRE',
                  p_type_ressource: 'soignant', p_id_ressource: userId,
                  p_cle_s3: null, p_details: { sms_actif: checked },
                  p_ip: null, p_navigateur: navigator.userAgent,
                });
                afficherNotification({
                  type: checked ? 'succes' : 'avertissement',
                  message: checked ? 'Notifications SMS activées.' : 'Notifications SMS désactivées.',
                });
              }
              setSmsToggling(false);
            }}
          />
        </div>
      </div>

      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4">Notifications push</h2>
        <div className="flex items-center justify-between">
          <div className="flex-1">
            <p className="text-sm text-foreground font-medium">Recevoir les notifications push</p>
            <p className="text-xs text-muted-foreground mt-1">
              Missions urgentes, nouvelles candidatures, rappels de pointage.
            </p>
          </div>
          <Switch
            aria-label="Recevoir les notifications push"
            checked={typeof Notification !== 'undefined' && Notification.permission === 'granted'}
            onCheckedChange={async (checked) => {
              if (checked) {
                const perm = await Notification.requestPermission();
                if (perm === 'granted') {
                  afficherNotification({ type: 'succes', message: 'Notifications push activées.' });
                } else {
                  afficherNotification({ type: 'avertissement', message: 'Notifications refusées par le navigateur. Vérifie les paramètres.' });
                }
              } else {
                await supabase.from('tokens_push').delete().eq('utilisateur_id', userId);
                afficherNotification({ type: 'avertissement', message: 'Notifications push désactivées. Tes tokens ont été supprimés.' });
              }
            }}
          />
        </div>
      </div>
    </div>
  );
}
