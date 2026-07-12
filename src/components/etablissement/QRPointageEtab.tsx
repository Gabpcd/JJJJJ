import { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Loader2, Maximize2, Printer, RefreshCw, Copy, Check, KeyRound, X } from 'lucide-react';
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
  const [secoursCode, setSecoursCode] = useState<string | null>(null);
  const [secoursExpire, setSecoursExpire] = useState<string | null>(null);
  const [generatingSecours, setGeneratingSecours] = useState(false);

  async function genererCodeSecours() {
    setGeneratingSecours(true);
    const { data, error } = await supabase.rpc('fn_generer_code_secours_mission' as any, {
      p_mission_id: missionId,
      p_type: 'UNIVERSEL',
    });
    setGeneratingSecours(false);
    const res = data as { success?: boolean; code?: string; expire_le?: string; error_code?: string } | null;
    if (error || !res?.success || !res?.code) {
      afficherNotification({ type: 'erreur', message: res?.error_code || error?.message || 'Erreur génération du code de secours' });
      return;
    }
    setSecoursCode(res.code);
    setSecoursExpire(res.expire_le || null);
  }

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
    printWindow.opener = null;
    const qrSvg = document.getElementById(`qr-pointage-${missionId}`)?.cloneNode(true);
    if (!qrSvg) {
      printWindow.close();
      afficherNotification({ type: 'erreur', message: 'Le QR code n’est pas prêt à être imprimé.' });
      return;
    }

    const doc = printWindow.document;
    doc.title = `QR Pointage Jolene — ${missionIntitule || 'Mission'}`;
    const style = doc.createElement('style');
    style.textContent = `
      @page { size: A4; margin: 20mm; }
      body { font-family: Arial, sans-serif; text-align: center; color: #222; }
      h1 { color: #d6336c; font-size: 32px; margin-bottom: 8px; }
      .etab { font-size: 20px; color: #444; margin-bottom: 4px; }
      .mission { font-size: 16px; color: #666; margin-bottom: 24px; }
      .qr-box { margin: 32px auto; }
      .qr-box svg { width: 360px; height: 360px; }
      .instructions { font-size: 18px; margin-top: 24px; line-height: 1.6; }
      .footer { margin-top: 40px; font-size: 12px; color: #666; }
    `;
    doc.head.appendChild(style);

    const ajouterTexte = (tag: 'h1' | 'p', texte: string, classe?: string) => {
      const element = doc.createElement(tag);
      element.textContent = texte;
      if (classe) element.className = classe;
      doc.body.appendChild(element);
      return element;
    };
    ajouterTexte('h1', 'Jolene');
    ajouterTexte('p', etablissementNom || 'Établissement', 'etab');
    ajouterTexte('p', missionIntitule || 'Mission', 'mission');
    const qrBox = doc.createElement('div');
    qrBox.className = 'qr-box';
    qrBox.appendChild(qrSvg);
    doc.body.appendChild(qrBox);
    ajouterTexte('p', 'Soignant : scannez ce code avec l’app Jolene pour valider votre arrivée et votre départ.', 'instructions');
    ajouterTexte(
      'p',
      `QR généré le ${format(new Date(qr.genere_le), "d MMM yyyy 'à' HH:mm", { locale: fr })} — expire le ${format(new Date(qr.expire_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}`,
      'footer',
    );
    printWindow.setTimeout(() => printWindow.print(), 100);
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
          <QRCodeSVG id={`qr-pointage-${missionId}`} value={qr.token} size={240} level="M" includeMargin aria-label="QR code de pointage de la mission" role="img" />
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
            {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />} {copied ? 'Copié !' : 'Copier le code QR'}
          </button>
          <button
            onClick={() => setShowConfirmRegen(true)}
            disabled={generating}
            className="btn-secondary text-xs inline-flex items-center gap-1 text-destructive disabled:opacity-50"
          >
            <RefreshCw className="h-3 w-3" /> Régénérer
          </button>
        </div>

        {/* Code de secours : fallback si le scan QR / GPS échoue côté soignant.
            Généré à la demande par l'établissement, affiché EN CLAIR une seule fois,
            communiqué oralement au soignant qui le saisit dans l'app. */}
        <div className="border-t border-border pt-3 space-y-2">
          <div className="flex items-center justify-between gap-2">
            <div>
              <p className="text-sm font-semibold text-foreground flex items-center gap-1.5">
                <KeyRound className="h-4 w-4 text-muted-foreground" /> Code de secours
              </p>
              <p className="text-[11px] text-muted-foreground">
                Si le scan du QR ou le GPS échoue, générez un code à communiquer au soignant.
              </p>
            </div>
            <button
              onClick={genererCodeSecours}
              disabled={generatingSecours}
              className="btn-secondary text-xs inline-flex items-center gap-1 shrink-0 disabled:opacity-50"
            >
              {generatingSecours ? <Loader2 className="h-3 w-3 animate-spin" /> : <KeyRound className="h-3 w-3" />}
              {secoursCode ? 'Nouveau code' : 'Générer'}
            </button>
          </div>

          {secoursCode && (
            <div className="rounded-lg border border-primary/30 bg-primary/5 p-3 text-center">
              <p className="text-3xl font-mono font-bold tracking-[0.3em] text-foreground">{secoursCode}</p>
              <p className="text-[11px] text-muted-foreground mt-1">
                Communiquez ce code au soignant — il ne sera <strong>plus jamais réaffiché</strong>.
                {secoursExpire && <> Expire le {format(new Date(secoursExpire), "d MMM 'à' HH:mm", { locale: fr })}.</>}
              </p>
            </div>
          )}
        </div>
      </div>

      {fullscreen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="QR code de pointage en plein écran"
          className="fixed inset-0 z-50 bg-white dark:bg-black flex flex-col items-center justify-center p-8"
        >
          <button type="button" onClick={() => setFullscreen(false)} className="absolute right-4 top-4 btn-secondary" aria-label="Fermer le plein écran">
            <X className="h-5 w-5" />
          </button>
          <p className="text-2xl font-bold text-foreground mb-2">🏥 Jolene</p>
          <p className="text-lg text-foreground mb-1">{etablissementNom}</p>
          <p className="text-sm text-muted-foreground mb-8">{missionIntitule}</p>
          <div className="bg-white p-8 rounded-2xl">
            <QRCodeSVG value={qr.token} size={420} level="M" includeMargin />
          </div>
          <p className="text-xl text-foreground mt-8 text-center">📲 Soignant : scannez avec l'app Jolene</p>
          <p className="text-xs text-muted-foreground mt-12">Utilisez le bouton Fermer pour revenir à la mission.</p>
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
