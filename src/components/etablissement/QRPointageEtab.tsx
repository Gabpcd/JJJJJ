import { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Loader2, Maximize2, Printer, RefreshCw, Copy, Check } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ModalConfirmation } from '@/components/ModalConfirmation';

interface Props {
  missionId: string;
  missionIntitule?: string;
  etablissementNom?: string;
}

interface QRRow {
  id: string;
  token: string;
  type: 'ARRIVEE' | 'DEPART' | 'UNIVERSEL';
  expire_le: string;
  nb_scans: number;
  dernier_scan_le: string | null;
  actif: boolean;
  genere_le: string;
}

/**
 * Composant QRPointageEtab (Sprint 4.5 PR 5).
 *
 * Affiche le QR code unique de la mission, scanné par le soignant pour
 * valider sa présence. Type UNIVERSEL par défaut (gère arrivée + départ).
 *
 * Actions :
 *  - Affichage QR taille 300×300 avec instructions
 *  - Bouton "Plein écran" pour affichage à l'accueil
 *  - Bouton "Imprimer poster A4"
 *  - Bouton "Régénérer le QR" (invalide précédent)
 */
export function QRPointageEtab({ missionId, missionIntitule, etablissementNom }: Props) {
  const { afficherNotification } = useNotification();
  const [qr, setQr] = useState<QRRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [showConfirmRegen, setShowConfirmRegen] = useState(false);
  const [copied, setCopied] = useState(false);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase
      .from('qr_codes_mission' as any)
      .select('*')
      .eq('mission_id', missionId)
      .eq('actif', true)
      .eq('type', 'UNIVERSEL')
      .order('genere_le', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
    } else {
      setQr((data as unknown as QRRow) || null);
    }
    setLoading(false);
  }

  async function genererOuRegenerer() {
    setGenerating(true);
    const { data, error } = await supabase.rpc('fn_generer_qr_mission' as any, {
      p_mission_id: missionId,
      p_type: 'UNIVERSEL',
    });
    setGenerating(false);
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || error?.message || 'Erreur génération QR' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'QR code régénéré ✅' });
    setShowConfirmRegen(false);
    charger();
  }

  useEffect(() => { charger(); }, [missionId]);

  function imprimer() {
    if (!qr) return;
    const printWindow = window.open('', '_blank');
    if (!printWindow) {
      afficherNotification({ type: 'erreur', message: 'Bloqué par votre navigateur. Autorisez les popups.' });
      return;
    }
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>QR Pointage Jolene — ${missionIntitule || ''}</title>
<style>
  @page { size: A4; margin: 20mm; }
  body { font-family: Arial, sans-serif; text-align: center; }
  h1 { color: #d6336c; font-size: 32px; margin-bottom: 8px; }
  .etab { font-size: 20px; color: #444; margin-bottom: 4px; }
  .mission { font-size: 16px; color: #666; margin-bottom: 24px; }
  .qr-box { margin: 32px auto; }
  .instructions { font-size: 18px; color: #222; margin-top: 24px; line-height: 1.6; }
  .footer { margin-top: 40px; font-size: 12px; color: #888; }
</style></head><body>
<h1>🏥 Jolene</h1>
<p class="etab">${etablissementNom || 'Établissement'}</p>
<p class="mission">${missionIntitule || ''}</p>
<div class="qr-box" id="qr"></div>
<p class="instructions">📲 <strong>Soignant : scannez ce code avec l'app Jolene</strong><br/>
pour valider votre arrivée et votre départ.</p>
<p class="footer">QR généré le ${format(new Date(qr.genere_le), "d MMM yyyy 'à' HH:mm", { locale: fr })} —
expire le ${format(new Date(qr.expire_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}</p>
<script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.3/build/qrcode.min.js"></script>
<script>
  const div = document.getElementById('qr');
  const c = document.createElement('canvas');
  div.appendChild(c);
  QRCode.toCanvas(c, ${JSON.stringify(qr.token)}, { width: 360, margin: 2 }, () => window.print());
</script>
</body></html>`;
    printWindow.document.write(html);
    printWindow.document.close();
  }

  function copierToken() {
    if (!qr) return;
    navigator.clipboard.writeText(qr.token).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  if (loading) {
    return <div className="flex justify-center p-6"><Loader2 className="h-6 w-6 animate-spin text-muted-foreground" /></div>;
  }

  if (!qr) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 dark:bg-amber-950/30 p-4 space-y-3">
        <p className="text-sm font-semibold text-amber-900 dark:text-amber-200">Aucun QR code généré pour cette mission</p>
        <p className="text-xs text-amber-800 dark:text-amber-300">
          Le QR sera généré automatiquement à la signature complète du contrat.
          Vous pouvez aussi le générer manuellement maintenant.
        </p>
        <button
          onClick={genererOuRegenerer}
          disabled={generating}
          className="btn-primary inline-flex items-center gap-2 disabled:opacity-50"
        >
          {generating ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
          Générer le QR
        </button>
      </div>
    );
  }

  return (
    <>
      <div className="rounded-xl border border-border bg-card p-4 space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold text-foreground">QR code de pointage</h3>
          <span className="text-xs px-2 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-900 text-emerald-900 dark:text-emerald-100">
            Actif
          </span>
        </div>

        <div className="flex justify-center bg-white dark:bg-card p-4 rounded-lg border border-border">
          <QRCodeSVG value={qr.token} size={240} level="M" includeMargin />
        </div>

        <p className="text-xs text-center text-muted-foreground">
          📲 Le soignant scanne ce QR avec l'app Jolene pour valider sa présence
        </p>

        <div className="grid grid-cols-2 gap-2 text-[10px] text-muted-foreground border-t border-border pt-2">
          <span>Généré : <strong>{format(new Date(qr.genere_le), "d MMM HH:mm", { locale: fr })}</strong></span>
          <span>Expire : <strong>{format(new Date(qr.expire_le), "d MMM HH:mm", { locale: fr })}</strong></span>
          <span>Scans : <strong>{qr.nb_scans}</strong></span>
          {qr.dernier_scan_le && (
            <span>Dernier scan : <strong>{format(new Date(qr.dernier_scan_le), "d MMM HH:mm", { locale: fr })}</strong></span>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          <button onClick={() => setFullscreen(true)} className="btn-secondary text-xs inline-flex items-center gap-1">
            <Maximize2 className="h-3 w-3" /> Plein écran
          </button>
          <button onClick={imprimer} className="btn-secondary text-xs inline-flex items-center gap-1">
            <Printer className="h-3 w-3" /> Imprimer A4
          </button>
          <button onClick={copierToken} className="btn-secondary text-xs inline-flex items-center gap-1">
            {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />} {copied ? 'Copié !' : 'Copier token'}
          </button>
          <button
            onClick={() => setShowConfirmRegen(true)}
            disabled={generating}
            className="btn-secondary text-xs inline-flex items-center gap-1 text-destructive disabled:opacity-50"
          >
            <RefreshCw className="h-3 w-3" /> Régénérer
          </button>
        </div>
      </div>

      {fullscreen && (
        <div className="fixed inset-0 z-50 bg-white dark:bg-black flex flex-col items-center justify-center p-8" onClick={() => setFullscreen(false)}>
          <p className="text-2xl font-bold text-foreground mb-2">🏥 Jolene</p>
          <p className="text-lg text-foreground mb-1">{etablissementNom}</p>
          <p className="text-sm text-muted-foreground mb-8">{missionIntitule}</p>
          <div className="bg-white p-8 rounded-2xl">
            <QRCodeSVG value={qr.token} size={420} level="M" includeMargin />
          </div>
          <p className="text-xl text-foreground mt-8 text-center">📲 Soignant : scannez avec l'app Jolene</p>
          <p className="text-xs text-muted-foreground mt-12">Cliquez pour fermer</p>
        </div>
      )}

      <ModalConfirmation
        ouvert={showConfirmRegen}
        onFermer={() => setShowConfirmRegen(false)}
        onConfirmer={genererOuRegenerer}
        titre="Régénérer le QR code ?"
        message="Le QR actuel sera invalidé. Toute personne ayant scanné l'ancien QR ne pourra plus l'utiliser. Cette action est irréversible."
        labelConfirmer="Régénérer"
        variante="primaire"
      />
    </>
  );
}
