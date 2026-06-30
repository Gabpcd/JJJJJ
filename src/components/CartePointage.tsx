import React, { useState, useEffect, useRef } from 'react';
import { format, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Clock, Pause, Play, QrCode, KeyRound, WifiOff } from 'lucide-react';
import { BoutonPointage } from './BoutonPointage';
import { ScannerQRPointageSoignant } from './soignant/ScannerQRPointageSoignant';
import { SaisieCodeSecours } from './soignant/SaisieCodeSecours';

import { ResultatPointage } from './ResultatPointage';
import { BadgeCertification } from './BadgeCertification';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { toast } from 'sonner';
import { ajouterAQueueQr, initSyncQrOfflineQueue, tailleQueueQr } from '@/lib/qr-offline-queue';

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

  // Sprint 4.5 PR 12 : modal Scan QR / Code secours + indicateur offline
  const [modalActif, setModalActif] = useState<'qr' | 'code' | null>(null);
  const [tailleQueue, setTailleQueue] = useState<number>(() => tailleQueueQr());

  useEffect(() => {
    initSyncQrOfflineQueue(() => setTailleQueue(tailleQueueQr())).catch(() => {});
    const handler = () => setTailleQueue(tailleQueueQr());
    window.addEventListener('storage', handler);
    return () => window.removeEventListener('storage', handler);
  }, []);

  function fermerModalEtRecharger() {
    setModalActif(null);
    onRecharger?.();
  }

  function fallbackVersCode() {
    setModalActif('code');
  }

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

      {/* État 2: Prêt — Sprint 4.5 PR 12 : QR (recommandé) + GPS + Code secours */}
      {etat === 'pret' && (
        <div className="space-y-3">
          <BoutonScannerQrPrincipal onClick={() => setModalActif('qr')} />
          <div className="grid grid-cols-2 gap-2">
            <BoutonPointage type="arrivee" onPointage={onPointerArrivee} />
            <button
              onClick={() => setModalActif('code')}
              className="rounded-2xl border-2 border-border bg-background py-4 text-sm font-bold text-foreground hover:bg-muted active:scale-95 transition-all flex flex-col items-center justify-center gap-1 min-h-[60px]"
            >
              <KeyRound className="h-5 w-5 text-primary" />
              Code secours
            </button>
          </div>
          {tailleQueue > 0 && <IndicateurFileOffline taille={tailleQueue} />}
        </div>
      )}

      {/* État 3: En mission */}
      {etat === 'en_mission' && presence && (
        <EnMissionBlock
          mission={mission}
          presence={presence}
          onPointerDepart={onPointerDepart}
          onRecharger={onRecharger}
          onScanQr={() => setModalActif('qr')}
          onCodeSecours={() => setModalActif('code')}
          tailleQueue={tailleQueue}
        />
      )}

      {/* Modals scan QR / code secours */}
      {modalActif === 'qr' && (
        <ScannerQRPointageSoignant
          missionId={mission.id}
          onValide={fermerModalEtRecharger}
          onAnnuler={() => setModalActif(null)}
          onFallbackCode={fallbackVersCode}
        />
      )}
      {modalActif === 'code' && (
        <SaisieCodeSecours
          missionId={mission.id}
          onValide={fermerModalEtRecharger}
          onAnnuler={() => setModalActif(null)}
        />
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

/** Bouton principal scan QR (Sprint 4.5 PR 12) */
function BoutonScannerQrPrincipal({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full py-6 rounded-2xl text-lg font-bold shadow-lg transition-all active:scale-95 bg-primary text-primary-foreground hover:bg-primary/90 flex items-center justify-center gap-3 min-h-[68px]"
    >
      <QrCode className="h-6 w-6" />
      <span>SCANNER LE QR (recommandé)</span>
    </button>
  );
}

/** Indicateur file offline (Sprint 4.5 PR 12) */
function IndicateurFileOffline({ taille }: { taille: number }) {
  return (
    <div className="flex items-center gap-2 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
      <WifiOff className="h-4 w-4 shrink-0" />
      <span>
        {taille} pointage{taille > 1 ? 's' : ''} en attente de synchronisation. Reconnecte-toi à Internet.
      </span>
    </div>
  );
}

/** Sub-component for en_mission state with pause support */
function EnMissionBlock({ mission, presence, onPointerDepart, onRecharger, onScanQr, onCodeSecours, tailleQueue }: {
  mission: any; presence: any; onPointerDepart: () => Promise<void>; onRecharger?: () => void;
  onScanQr: () => void; onCodeSecours: () => void; tailleQueue: number;
}) {
  const [enPause, setEnPause] = useState(!!presence.pause_debut_le && !presence.pause_fin_le);
  const [pauseLoading, setPauseLoading] = useState(false);
  const [chronoPause, setChronoPause] = useState(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Chrono for ongoing pause
  useEffect(() => {
    if (enPause && presence.pause_debut_le) {
      const debut = new Date(presence.pause_debut_le).getTime();
      const tick = () => setChronoPause(Math.floor((Date.now() - debut) / 1000));
      tick();
      timerRef.current = setInterval(tick, 1000);
      return () => { if (timerRef.current) clearInterval(timerRef.current); };
    } else {
      setChronoPause(0);
    }
  }, [enPause, presence.pause_debut_le]);

  const formatChrono = (s: number) => {
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  };

  const handlePause = async () => {
    setPauseLoading(true);
    try {
      if (!enPause) {
        const { error } = await supabase.rpc('fn_pointer_debut_pause' as any, { p_presence_id: presence.id });
        if (error) { toast.error(extraireMessageErreur(error)); return; }
        setEnPause(true);
        toast.success('Pause démarrée');
      } else {
        const { error } = await supabase.rpc('fn_pointer_fin_pause' as any, { p_presence_id: presence.id });
        if (error) { toast.error(extraireMessageErreur(error)); return; }
        setEnPause(false);
        toast.success('Pause terminée');
      }
      onRecharger?.();
    } finally {
      setPauseLoading(false);
    }
  };

  return (
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

      {/* Bouton pause déjeuner */}
      <button
        onClick={handlePause}
        disabled={pauseLoading}
        className={`w-full py-3 rounded-xl text-sm font-semibold transition-all flex items-center justify-center gap-2 ${
          enPause
            ? 'bg-primary/10 border border-primary/30 text-primary hover:bg-primary/20'
            : 'bg-muted border border-border text-muted-foreground hover:bg-muted/80'
        } disabled:opacity-60`}
      >
        {enPause ? (
          <><Play className="h-4 w-4" /> ▶️ Fin de pause · {formatChrono(chronoPause)}</>
        ) : (
          <><Pause className="h-4 w-4" /> ⏸ Pause déjeuner</>
        )}
      </button>

      {!enPause && (
        <>
          <BoutonScannerQrPrincipal onClick={onScanQr} />
          <div className="grid grid-cols-2 gap-2">
            <BoutonPointage type="depart" onPointage={onPointerDepart} />
            <button
              onClick={onCodeSecours}
              className="rounded-2xl border-2 border-border bg-background py-4 text-sm font-bold text-foreground hover:bg-muted active:scale-95 transition-all flex flex-col items-center justify-center gap-1 min-h-[60px]"
            >
              <KeyRound className="h-5 w-5 text-primary" />
              Code secours
            </button>
          </div>
          {tailleQueue > 0 && <IndicateurFileOffline taille={tailleQueue} />}
        </>
      )}
      {enPause && (
        <p className="text-xs text-muted-foreground text-center italic">
          Le bouton de départ est masqué pendant la pause.
        </p>
      )}
    </div>
  );
}
