import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { format, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { MapPin, Radio, AlertTriangle, Phone, Mail, CheckCircle, XCircle, Scale, Eye } from 'lucide-react';
import { BadgeCertification } from './BadgeCertification';
import { PanneauContestation } from './PanneauContestation';
import { FilDiscussionLitige } from './FilDiscussionLitige';
import { BadgesAntiTrichePresence } from './presence/BadgesAntiTrichePresence';
import { EtoilesNotation, DetailCriteres } from './NotationRapide';

interface CarteValidationProps {
  presence: any;
  litigeExistant?: any;
  /** F4 (Lot 7b) : la validation embarque la note 1-tap (obligatoire) +
   *  critères détaillés optionnels (null = note répliquée sur les 4). */
  onValider: (id: string, note: number, criteres: [number, number, number, number] | null) => Promise<void>;
  onContester: (id: string, motif: string) => Promise<void>;
  onOuvrirLitige?: (presenceId: string, missionId: string, soignantId: string, motif: string) => Promise<void>;
  onUpdate?: () => void;
}

export function CarteValidation({ presence, litigeExistant, onValider, onContester, onOuvrirLitige, onUpdate }: CarteValidationProps) {
  const navigate = useNavigate();
  const [motifLitige, setMotifLitige] = useState('');
  const [showContester, setShowContester] = useState(false);
  const [showContact, setShowContact] = useState(false);
  const [showLitige, setShowLitige] = useState(false);
  const [motifLitigeFormel, setMotifLitigeFormel] = useState('');
  // F4 : note 1-tap obligatoire au moment de valider (0 = pas encore choisie).
  const [note, setNote] = useState(0);
  const [detailNote, setDetailNote] = useState(false);
  const [criteres, setCriteres] = useState<[number, number, number, number] | null>(null);
  const [validating, setValidating] = useState(false);

  const mission = presence.missions;
  const soignant = presence.soignants;
  if (!mission || !soignant) return null;

  const debutPrevu = new Date(mission.debut_le);
  const finPrevue = new Date(mission.fin_le);
  const arriveeReelle = presence.pointage_arrivee_le ? new Date(presence.pointage_arrivee_le) : null;
  const departReel = presence.pointage_depart_le ? new Date(presence.pointage_depart_le) : null;

  const dureeReelleMin = arriveeReelle && departReel ? differenceInMinutes(departReel, arriveeReelle) : null;
  const dureePrevueMin = (mission.duree_heures || 0) * 60;
  const ecartMin = dureeReelleMin !== null ? dureeReelleMin - dureePrevueMin : null;

  const aAlertes = presence.alerte_teleportation || !presence.perimetre_gps_valide;

  const borderClass = presence.alerte_teleportation
    ? 'border-l-4 border-destructive bg-destructive/5'
    : !presence.perimetre_gps_valide
      ? 'border-l-4 border-warning bg-warning/5'
      : presence.valide_par_etablissement
        ? 'border-success/30'
        : 'border-border';

  return (
    <div className={`rounded-2xl border p-4 space-y-3 ${borderClass}`}>
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h3 className="font-semibold text-foreground text-sm">{soignant.prenom} {soignant.nom} · {soignant.profession}</h3>
          <p className="text-xs text-muted-foreground">{mission.intitule}{mission.service ? ` · ${mission.service}` : ''}</p>
        </div>
        {presence.valide_par_etablissement ? (
          <div className="flex items-center gap-2">
            <button
              onClick={() => navigate(`/etablissement/presences/mission/${presence.mission_id}`)}
              className="flex items-center gap-1 text-xs text-primary hover:underline"
            >
              <Eye className="h-3.5 w-3.5" /> Détail
            </button>
            <BadgeCertification
              perimetreOk={presence.perimetre_gps_valide === true}
              pasAlerteTeleportation={!presence.alerte_teleportation}
              valideParEtablissement={true}
            />
          </div>
        ) : (
          <button
            onClick={() => navigate(`/etablissement/presences/mission/${presence.mission_id}`)}
            className="flex items-center gap-1 text-xs text-primary hover:underline"
          >
            <Eye className="h-3.5 w-3.5" /> Détail
          </button>
        )}
      </div>

      {/* Horaires */}
      <div className="grid grid-cols-2 gap-2 text-xs">
        <div>
          <p className="text-muted-foreground">Prévu</p>
          <p className="font-medium text-foreground">
            {format(debutPrevu, "HH:mm")} → {format(finPrevue, "HH:mm")} ({mission.duree_heures}h)
          </p>
        </div>
        {arriveeReelle && departReel && dureeReelleMin !== null && (
          <div>
            <p className="text-muted-foreground">Réel</p>
            <p className="font-medium text-foreground">
              {format(arriveeReelle, "HH:mm")} → {format(departReel, "HH:mm")} ({Math.floor(dureeReelleMin / 60)}h{String(dureeReelleMin % 60).padStart(2, '0')})
            </p>
          </div>
        )}
      </div>

      {ecartMin !== null && (
        <p className={`text-xs ${Math.abs(ecartMin) <= 15 ? 'text-muted-foreground' : ecartMin > 15 ? 'text-warning' : 'text-destructive'}`}>
          Écart : {ecartMin >= 0 ? '+' : ''}{ecartMin} min
        </p>
      )}

      {/* GPS info */}
      <div className="flex flex-wrap gap-3 text-xs">
        {presence.distance_etablissement_m !== null && (
          <span className={`flex items-center gap-1 ${presence.perimetre_gps_valide ? 'text-success' : 'text-warning'}`}>
            <MapPin className="h-3.5 w-3.5" />
            Arrivée : {Math.round(presence.distance_etablissement_m)}m · {presence.perimetre_gps_valide ? '✅ OK' : '⚠️ Hors périmètre'}
          </span>
        )}
        {presence.arrivee_precision_gps_m && (
          <span className="flex items-center gap-1 text-muted-foreground">
            <Radio className="h-3.5 w-3.5" /> {Math.round(presence.arrivee_precision_gps_m)}m
          </span>
        )}
      </div>

      {/* Alertes anti-triche Sprint 4.5 (Sprint 6 PR 7 — Fix P1-7) */}
      <BadgesAntiTrichePresence
        arrivee_mock_detected={presence.arrivee_mock_detected}
        depart_mock_detected={presence.depart_mock_detected}
        alerte_teleportation={presence.alerte_teleportation}
        perimetre_gps_valide={presence.perimetre_gps_valide}
        coherence_incidents={presence.coherence_incidents}
      />

      {/* Détail alertes legacy (préserve compat) */}
      {aAlertes && (
        <div className="space-y-1">
          {!presence.perimetre_gps_valide && (
            <p className="text-xs text-warning flex items-center gap-1">
              <AlertTriangle className="h-3.5 w-3.5" /> Hors périmètre à l'arrivée ({Math.round(presence.distance_etablissement_m || 0)}m)
            </p>
          )}
          {presence.alerte_teleportation && (
            <p className="text-xs text-destructive flex items-center gap-1">
              <AlertTriangle className="h-3.5 w-3.5" /> Téléportation détectée
            </p>
          )}
        </div>
      )}

      {/* Litige */}
      {presence.motif_litige && (
        <div className="bg-warning/10 border border-warning/20 rounded-xl p-2 text-xs text-warning">
          ⚠️ Litige : {presence.motif_litige}
        </div>
      )}

      {/* Actions — F4 : valider = valider ET noter, un seul geste. La note 1-tap
          est obligatoire (cold start du système de notation, la donnée coule dès
          le jour 1) ; le détail 4 critères reste optionnel. */}
      {!presence.valide_par_etablissement && departReel && (
        <div className="space-y-2 pt-1">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs text-muted-foreground">Note {soignant.prenom} :</span>
            <EtoilesNotation
              label={`Note pour ${soignant.prenom} ${soignant.nom}`}
              valeur={note}
              onChange={(n) => { setNote(n); if (!detailNote) setCriteres(null); }}
            />
            <button
              type="button"
              className="text-[11px] text-primary hover:underline"
              onClick={() => {
                setDetailNote(v => !v);
                if (!detailNote) setCriteres([note || 3, note || 3, note || 3, note || 3]);
                else setCriteres(null);
              }}
            >
              {detailNote ? 'Masquer le détail' : 'Détailler'}
            </button>
          </div>
          {detailNote && criteres && (
            <DetailCriteres sens="ETAB_VERS_SOIGNANT" criteres={criteres} onChange={setCriteres} />
          )}
        <div className="flex flex-wrap gap-2">
          <button
            onClick={async () => {
              if (note === 0 || validating) return;
              setValidating(true);
              try { await onValider(presence.id, note, criteres); } finally { setValidating(false); }
            }}
            disabled={note === 0 || validating}
            title={note === 0 ? 'Choisissez une note pour valider' : undefined}
            className="flex items-center gap-1.5 bg-success text-success-foreground text-xs font-semibold px-3 py-2 rounded-xl hover:bg-success/90 transition-colors disabled:opacity-50 disabled:pointer-events-none"
          >
            <CheckCircle className="h-3.5 w-3.5" /> {note === 0 ? 'Noter pour valider' : 'Valider et noter'}
          </button>
          <button
            onClick={() => setShowContester(!showContester)}
            className="flex items-center gap-1.5 bg-destructive/10 text-destructive text-xs font-semibold px-3 py-2 rounded-xl hover:bg-destructive/20 transition-colors"
          >
            <XCircle className="h-3.5 w-3.5" /> Contester
          </button>
          <button
            onClick={() => setShowContact(!showContact)}
            className="flex items-center gap-1.5 bg-muted text-muted-foreground text-xs font-semibold px-3 py-2 rounded-xl hover:bg-muted/80 transition-colors"
          >
            <Phone className="h-3.5 w-3.5" /> Contacter
          </button>
        </div>
        </div>
      )}

      {/* Contester form */}
      {showContester && (
        <div className="space-y-2 border-t border-border pt-2">
          <textarea
            value={motifLitige}
            onChange={e => setMotifLitige(e.target.value)}
            placeholder="Motif de la contestation..."
            className="input-base w-full text-sm"
            rows={2}
          />
          <button
            onClick={() => { onContester(presence.id, motifLitige); setShowContester(false); setMotifLitige(''); }}
            disabled={!motifLitige.trim()}
            className="btn-primary text-xs disabled:opacity-50 disabled:pointer-events-none"
          >
            Envoyer la contestation
          </button>
        </div>
      )}

      {/* Contact options */}
      {showContact && (
        <div className="flex gap-2 border-t border-border pt-2">
          {soignant.telephone && (
            <a href={`tel:${soignant.telephone}`} className="flex items-center gap-1 text-xs text-primary hover:underline">
              <Phone className="h-3.5 w-3.5" /> Appeler
            </a>
          )}
          {soignant.email && (
            <a href={`mailto:${soignant.email}`} className="flex items-center gap-1 text-xs text-primary hover:underline">
              <Mail className="h-3.5 w-3.5" /> Email
            </a>
          )}
        </div>
      )}

      {/* Litige section */}
      {litigeExistant ? (
        <div className="border-t border-border pt-2">
          <FilDiscussionLitige litige={litigeExistant} onUpdate={onUpdate || (() => {})} />
        </div>
      ) : (
        <>
          {onOuvrirLitige && presence.pointage_depart_le && (
            <div className="border-t border-border pt-2">
              {showLitige ? (
                <div className="space-y-2">
                  <textarea
                    value={motifLitigeFormel}
                    onChange={e => setMotifLitigeFormel(e.target.value)}
                    placeholder="Décrivez le motif du litige..."
                    className="input-base w-full text-sm"
                    rows={3}
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={() => {
                        onOuvrirLitige(presence.id, presence.mission_id, presence.soignant_id, motifLitigeFormel);
                        setShowLitige(false);
                        setMotifLitigeFormel('');
                      }}
                      disabled={!motifLitigeFormel.trim()}
                      className="flex items-center gap-1.5 bg-warning/10 text-warning text-xs font-semibold px-3 py-2 rounded-xl hover:bg-warning/20 transition-colors disabled:opacity-50"
                    >
                      <Scale className="h-3.5 w-3.5" /> Confirmer le litige
                    </button>
                    <button
                      onClick={() => setShowLitige(false)}
                      className="text-xs text-muted-foreground hover:text-foreground px-3 py-2"
                    >
                      Annuler
                    </button>
                  </div>
                </div>
              ) : (
                <button
                  onClick={() => setShowLitige(true)}
                  className="flex items-center gap-1.5 text-xs text-warning hover:text-warning/80 font-medium transition-colors"
                >
                  <Scale className="h-3.5 w-3.5" /> Ouvrir un litige
                </button>
              )}
            </div>
          )}

          {presence.valide_par_etablissement && (
            <PanneauContestation
              presenceId={presence.id}
              missionId={presence.mission_id}
              etablissementId={mission.etablissement_id}
              soignantId={presence.soignant_id}
              presenceValideeLe={presence.valide_le}
              role="ETABLISSEMENT"
            />
          )}
        </>
      )}
    </div>
  );
}
