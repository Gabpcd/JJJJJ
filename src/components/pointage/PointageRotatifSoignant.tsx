import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { QrCode, Loader2, Clock, CheckCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { SheetNotationRapide } from '@/components/NotationRapide';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { extraireMessageErreur } from '@/lib/erreurs';
import { obtenirPosition } from '@/lib/platform';
import { genererIdTerminal } from '@/lib/terminal';
import { scannerQr } from '@/lib/camera';
import { toast } from 'sonner';
import { cleJourParis, formatParis, memeJourParis } from '@/lib/date-heure-paris';

/**
 * Pointage rotatif (PR 2/3) — côté SOIGNANT.
 *
 * Le soignant saisit le code à 6 chiffres affiché par l'établissement (ou scanne
 * le QR), à chaque ouverture/fermeture de segment. fn_scanner_code_pointage
 * alterne OUVERTURE/FERMETURE, gère les pauses (N segments/jour) et crée les
 * créneaux EFFECTIF qui alimentent la paie. GPS joint en métadonnée (anti-triche).
 */
interface Segment { id: string; debut: string; fin: string | null }
interface Etat {
  statut: string;
  prochain_type_scan: 'OUVERTURE' | 'FERMETURE';
  segment_ouvert: boolean;
  segments: Segment[];
  error?: string;
}

const CLE_PROMPT_NOTE = (missionId: string) => `jolene_note_checkout_${missionId}`;

export function PointageRotatifSoignant({
  missionId,
  consentementGPS,
}: {
  missionId: string;
  consentementGPS: boolean | null;
}) {
  const queryClient = useQueryClient();
  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [scanning, setScanning] = useState(false);
  // F4 (Lot 7b) : notation au check-out — proposée UNE fois, au dernier départ
  // (fin prévue atteinte). Skippable : le bandeau évaluations rattrape.
  const [notationOpen, setNotationOpen] = useState(false);

  const { data, refetch, isLoading, isError, error: queryError } = useQuery({
    queryKey: ['etat-pointage-soignant', missionId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_etat_pointage_mission' as any, { p_mission_id: missionId });
      if (error) throw error;
      return data as Etat;
    },
    refetchInterval: 15000,
  });

  if (isLoading) {
    return (
      <div className="card-base flex items-center gap-2 text-sm text-muted-foreground" role="status">
        <Loader2 className="h-4 w-4 animate-spin" /> Chargement du pointage…
      </div>
    );
  }
  if (isError || !data || data.error) {
    return (
      <div className="card-base border-destructive/30" role="alert">
        <p className="text-sm font-semibold text-destructive">Pointage momentanément indisponible</p>
        <p className="text-xs text-muted-foreground mt-1">
          {data?.error || (queryError ? extraireMessageErreur(queryError) : 'Impossible de charger son état.')}
        </p>
        <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => refetch()}>
          Réessayer
        </BoutonY2K>
      </div>
    );
  }
  if (!['ASSIGNEE', 'EN_COURS'].includes(data.statut)) {
    return (
      <div className="card-base text-sm text-muted-foreground" role="status">
        Le pointage n'est pas disponible pour le statut actuel de cette mission.
      </div>
    );
  }

  const ouvert = data.segment_ouvert;
  const aDejaPointeAujourdHui = data.segments.some((segment) => (
    memeJourParis(segment.debut, new Date())
  ));
  const actionLabel = ouvert
    ? 'Pointer mon départ / pause'
    : (aDejaPointeAujourdHui ? 'Pointer mon arrivée / ma reprise' : "Pointer mon arrivée");
  const segmentEnCours = data.segments.find((s) => s.fin === null);
  const segmentsSurPlusieursJours = new Set(
    data.segments.map((segment) => cleJourParis(segment.debut)),
  ).size > 1;

  const envoyer = async (codeSaisi: string) => {
    const c = codeSaisi.trim();
    if (c.length !== 6 || submitting) return;
    setSubmitting(true);
    // Le GPS est strictement opt-in. Un refus n'empêche jamais le pointage :
    // l'établissement peut alors le valider manuellement.
    let meta: Record<string, unknown> = { id_terminal: genererIdTerminal() };
    if (consentementGPS === true) {
      try {
        const pos = await obtenirPosition();
        meta = { ...meta, latitude: pos.lat, longitude: pos.lng, precision_gps_m: pos.precisionM };
      } catch { /* GPS indisponible — le scan reste valable, validation étab possible */ }
    }

    const { data: res, error } = await supabase.rpc('fn_scanner_code_pointage' as any, { p_code: c, p_metadata: meta });
    setSubmitting(false);
    if (error) {
      toast.error(extraireMessageErreur(error));
      return;
    }
    const type = (res as any)?.type_scan_effectue;
    if ('vibrate' in navigator) navigator.vibrate(type === 'OUVERTURE' ? 200 : [200, 100, 200]);
    toast.success(type === 'OUVERTURE' ? '✅ Pointage enregistré — segment ouvert' : '✅ Pointage enregistré — segment fermé');
    setCode('');
    await Promise.all([
      refetch(),
      queryClient.invalidateQueries({ queryKey: ['presences-soignant'] }),
      queryClient.invalidateQueries({ queryKey: ['dashboard-soignant'] }),
    ]);

    // F4 : au check-out FINAL (fermeture alors que la fin prévue est atteinte),
    // proposer la note 1-tap — une seule fois par mission.
    if (type === 'FERMETURE' && !localStorage.getItem(CLE_PROMPT_NOTE(missionId))) {
      try {
        const { data: m } = await supabase.from('missions').select('fin_le').eq('id', missionId).maybeSingle();
        if (m?.fin_le && Date.now() >= new Date(m.fin_le).getTime() - 30 * 60_000) {
          localStorage.setItem(CLE_PROMPT_NOTE(missionId), '1');
          setNotationOpen(true);
        }
      } catch { /* le prompt de note ne doit jamais gêner le pointage */ }
    }
  };

  const scanner = async () => {
    setScanning(true);
    try {
      const r = await scannerQr();
      if (r?.text) {
        const digits = r.text.replace(/\D/g, '').slice(0, 6);
        if (digits.length === 6) { await envoyer(digits); return; }
        toast.error('QR non reconnu. Saisissez le code à 6 chiffres.');
      }
    } catch {
      toast.error('Scan impossible. Saisissez le code manuellement.');
    } finally {
      setScanning(false);
    }
  };

  return (
    <div className="card-base space-y-3">
      <div className="flex items-center gap-2">
        <h3 className="font-semibold text-foreground text-sm">Pointage</h3>
        {ouvert && segmentEnCours && (
          <span className="ml-auto inline-flex items-center gap-1 text-xs text-success font-semibold">
            <Clock className="h-3.5 w-3.5" /> En service depuis {formatParis(segmentEnCours.debut, "HH'h'mm")}
          </span>
        )}
      </div>

      <p className="text-xs text-muted-foreground">
        {ouvert
          ? 'Saisissez le code affiché par l\'établissement pour pointer votre départ ou une pause.'
          : 'Saisissez le code affiché par l\'établissement pour pointer.'}
      </p>

      <div className="flex gap-2">
        <input
          inputMode="numeric"
          pattern="[0-9]*"
          maxLength={6}
          aria-label="Code de pointage à 6 chiffres"
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          placeholder="123 456"
          className="input-base flex-1 text-center text-xl font-mono tracking-[0.3em]"
        />
        <BoutonY2K size="sm" variant="secondary" onClick={scanner} disabled={scanning || submitting} iconeGauche={scanning ? <Loader2 className="h-4 w-4 animate-spin" /> : <QrCode className="h-4 w-4" />}>
          QR
        </BoutonY2K>
      </div>

      <BoutonY2K
        variant="primary"
        className="w-full"
        loading={submitting}
        disabled={code.length !== 6 || submitting}
        onClick={() => envoyer(code)}
        iconeGauche={<CheckCircle className="h-4 w-4" />}
      >
        {actionLabel}
      </BoutonY2K>

      {data.segments.length > 0 && (
        <div className="space-y-1 pt-1">
          {data.segments.map((s, i) => (
            <div key={s.id} className="flex items-center justify-between text-xs text-muted-foreground">
              <span>Segment {i + 1}</span>
              <span>
                {formatParis(
                  s.debut,
                  segmentsSurPlusieursJours ? "d MMM · HH'h'mm" : "HH'h'mm",
                )}
                {s.fin ? ` → ${formatParis(s.fin, "HH'h'mm")}` : ' → en cours'}
              </span>
            </div>
          ))}
        </div>
      )}

      <SheetNotationRapide
        open={notationOpen}
        onOpenChange={setNotationOpen}
        missionId={missionId}
        sens="SOIGNANT_VERS_ETAB"
        titre="Mission terminée 🎉 Comment ça s'est passé ?"
        description="Un tap suffit — ta note aide les autres soignants à choisir leurs missions."
      />
    </div>
  );
}
