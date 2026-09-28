import { Switch } from '@/components/ui/switch';
import { useNavigate } from 'react-router-dom';
import { ChoixModesExercice } from '@/components/ChoixModesExercice';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
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
  profession: string;
  onTypesContratChange: (valeur: string[]) => void;
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
}

export function SectionPreferences(props: Props) {
  const {
    userId, bio, onBioChange, anneesExperience, onAnneesChange,
    specialites, onSpecialitesChange,
    typesContrat, profession, onTypesContratChange,
    rayon, onRayonChange,
    tauxHoraireMinimum, onTauxChange,
    poolUrgenceActif, poolUrgenceRayon, onPoolUrgenceUpdate,
    consentementGPS, onConsentementGPSChange, gpsToggling, setGpsToggling,
  } = props;
  const { afficherNotification } = useNotification();
  const { role } = useRole();
  const navigate = useNavigate();
  const modesExercice = useTypesExerciceAutorises(profession);

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
        <ChoixModesExercice
          valeur={typesContrat}
          onChange={onTypesContratChange}
          {...modesExercice}
        />
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
            className="w-full min-h-11 accent-primary"
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
          className="w-full min-h-11 accent-primary"
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
        <h2 className="text-base font-semibold text-foreground">Notifications</h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Choisis au même endroit les alertes email, push, SMS et in-app, globalement ou par événement.
        </p>
        <button
          type="button"
          onClick={() => navigate('/soignant/parametres/notifications')}
          className="btn-secondary mt-4 min-h-11 w-full"
        >
          Gérer mes préférences de notifications
        </button>
      </div>
    </div>
  );
}
