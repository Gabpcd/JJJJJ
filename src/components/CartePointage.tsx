import React from 'react';
import { format, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Clock } from 'lucide-react';
import { BoutonPointage } from './BoutonPointage';
import { SaisieCodePointage } from './SaisieCodePointage';
import { ResultatPointage } from './ResultatPointage';
import { BadgeCertification } from './BadgeCertification';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

interface CartePointageProps {
  mission: any;
  presence: any | null;
  onPointerArrivee: () => Promise<void>;
  onPointerDepart: () => Promise<void>;
  onRecharger?: () => void;
}

export function CartePointage({ mission, presence, onPointerArrivee, onPointerDepart, onRecharger }: CartePointageProps) {
  const maintenant = new Date();
  const debut = new Date(mission.debut_le);
  const fin = new Date(mission.fin_le);
  const minutesAvantDebut = differenceInMinutes(debut, maintenant);

  const aPointeArrivee = !!presence?.pointage_arrivee_le;
  const aPointeDepart = !!presence?.pointage_depart_le;

  // Determine state
  let etat: 'futur' | 'trop_tot' | 'pret' | 'en_mission' | 'termine';
  if (aPointeArrivee && aPointeDepart) {
    etat = 'termine';
  } else if (aPointeArrivee) {
    etat = 'en_mission';
  } else if (minutesAvantDebut <= 30) {
    etat = 'pret';
  } else if (minutesAvantDebut <= 60) {
    etat = 'trop_tot';
  } else {
    etat = 'futur';
  }

  const etabNom = mission.etablissements?.nom || 'Établissement';

  const borderClass = etat === 'termine'
    ? (presence?.valide_par_etablissement ? 'border-success/30 bg-success/5' : 'border-border')
    : etat === 'en_mission'
      ? 'border-primary/30 bg-primary/5'
      : etat === 'pret'
        ? 'border-primary/40 bg-primary/5'
        : 'border-border bg-muted/30';

  return (
    <div className={`rounded-2xl border p-4 space-y-3 ${borderClass}`}>
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h3 className="font-semibold text-foreground">{mission.intitule} — {etabNom}</h3>
          <p className="text-sm text-muted-foreground">
            📅 Aujourd'hui · {format(debut, "HH:mm", { locale: fr })} → {format(fin, "HH:mm", { locale: fr })} ({mission.duree_heures}h)
          </p>
        </div>
        {etat === 'termine' && presence && (
          <BadgeCertification
            perimetreOk={presence.perimetre_gps_valide === true}
            pasAlerteTeleportation={presence.alerte_teleportation !== true}
            valideParEtablissement={presence.valide_par_etablissement === true}
          />
        )}
      </div>

      {/* État 1: Futur */}
      {etat === 'futur' && (
        <div className="text-center py-4">
          <Clock className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">
            ⏳ Mission dans {minutesAvantDebut > 60 ? `${Math.floor(minutesAvantDebut / 60)}h${String(minutesAvantDebut % 60).padStart(2, '0')}` : `${minutesAvantDebut} min`}
          </p>
          <p className="text-xs text-muted-foreground/60 mt-1">Le bouton de pointage apparaîtra 30 min avant le début.</p>
        </div>
      )}

      {/* État 1b: Too early — visible but disabled */}
      {etat === 'trop_tot' && (
        <div className="text-center py-4">
          <Clock className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">
            Pointage disponible à {format(new Date(debut.getTime() - 30 * 60000), "HH:mm", { locale: fr })}
          </p>
          <p className="text-xs text-muted-foreground/60 mt-1">Encore {minutesAvantDebut - 30} min d'attente.</p>
        </div>
      )}

      {/* État 2: Prêt */}
      {etat === 'pret' && (
        <div className="space-y-2">
          <BoutonPointage type="arrivee" onPointage={onPointerArrivee} />
          <SaisieCodePointage
            type="arrivee"
            onValider={async (code) => {
              const { data, error } = await supabase.rpc('fn_pointer_arrivee_code' as any, {
                p_mission_id: mission.id,
                p_code: code,
              });
              if (error) return { success: false, message: extraireMessageErreur(error) };
              if (data?.success === false) return { success: false, message: data.error };
              onRecharger?.();
              return { success: true, message: 'Arrivée pointée par code ✅' };
            }}
          />
        </div>
      )}

      {/* État 3: En mission */}
      {etat === 'en_mission' && presence && (
        <div className="space-y-3">
          <ResultatPointage
            type="arrivee"
            heure={presence.pointage_arrivee_le}
            distanceM={presence.distance_etablissement_m}
            perimetreOk={presence.perimetre_gps_valide}
            precisionM={presence.arrivee_precision_gps_m}
            alerteTeleportation={presence.alerte_teleportation}
          />
          {presence.methode_pointage_arrivee === 'CODE' && (
            <p className="text-xs text-primary font-medium text-center">🔑 Pointé par code</p>
          )}
          <BoutonPointage type="depart" onPointage={onPointerDepart} />
          <SaisieCodePointage
            type="depart"
            onValider={async (code) => {
              const { data, error } = await supabase.rpc('fn_pointer_depart_code' as any, {
                p_presence_id: presence.id,
                p_code: code,
              });
              if (error) return { success: false, message: extraireMessageErreur(error) };
              if (data?.success === false) return { success: false, message: data.error };
              onRecharger?.();
              return { success: true, message: 'Départ pointé par code ✅' };
            }}
          />
        </div>
      )}

      {/* État 4: Terminé */}
      {etat === 'termine' && presence && (
        <div className="space-y-3">
          <ResultatPointage
            type="arrivee"
            heure={presence.pointage_arrivee_le}
            distanceM={presence.distance_etablissement_m}
            perimetreOk={presence.perimetre_gps_valide}
            precisionM={presence.arrivee_precision_gps_m}
            alerteTeleportation={presence.alerte_teleportation}
          />
          <ResultatPointage
            type="depart"
            heure={presence.pointage_depart_le}
            distanceM={null}
            perimetreOk={null}
            precisionM={presence.depart_precision_gps_m || null}
          />
          {/* Durée réelle */}
          {(() => {
            const arrivee = new Date(presence.pointage_arrivee_le);
            const depart = new Date(presence.pointage_depart_le);
            const dureeReelleMin = differenceInMinutes(depart, arrivee);
            const dureeReelleH = Math.floor(dureeReelleMin / 60);
            const dureeReelleM = dureeReelleMin % 60;
            const dureePrevueMin = (mission.duree_heures || 0) * 60;
            const ecartMin = dureeReelleMin - dureePrevueMin;

            return (
              <div className="text-sm text-muted-foreground border-t border-border pt-2">
                <p>Durée réelle : <span className="font-medium text-foreground">{dureeReelleH}h{String(dureeReelleM).padStart(2, '0')}</span></p>
                <p className="text-xs">
                  Prévu : {mission.duree_heures}h | Écart :{' '}
                  <span className={ecartMin >= 0 ? 'text-muted-foreground' : 'text-destructive'}>
                    {ecartMin >= 0 ? '+' : ''}{ecartMin} min
                  </span>
                </p>
              </div>
            );
          })()}
          {/* Validation status */}
          <div className="text-xs">
            {presence.valide_par_etablissement ? (
              <p className="text-success font-medium">
                ✅ Validé par l'établissement{presence.valide_le ? ` le ${format(new Date(presence.valide_le), "dd/MM à HH:mm", { locale: fr })}` : ''}
              </p>
            ) : (
              <p className="text-muted-foreground italic">En attente de validation par l'établissement...</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
