import { useState, useRef, useEffect } from 'react';
import { X, Loader2, CheckCircle, AlertCircle, KeyRound } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { getCurrentPosition } from '@/lib/geoloc';
import { genererIdTerminal } from '@/lib/terminal';

interface Props {
  missionId: string;
  onValide?: (params: { methode_detectee: string; horodatage: string }) => void;
  onAnnuler?: () => void;
}

const MESSAGES_ERREUR: Record<string, string> = {
  NON_AUTHENTIFIE: 'Session expirée. Reconnectez-vous.',
  NON_AUTORISE: 'Vous n\'êtes pas assigné à cette mission.',
  CODE_FORMAT_INVALIDE: 'Le code doit être 6 chiffres.',
  CODE_INVALIDE: 'Code incorrect, déjà utilisé ou expiré. Demandez un nouveau code à l\'établissement.',
  DEJA_POINTE: 'Vous avez déjà pointé votre arrivée.',
  DEPART_SANS_ARRIVEE: 'Vous devez d\'abord pointer votre arrivée.',
  DEPART_DEJA_POINTE: 'Vous avez déjà pointé votre départ.',
  DEPART_TROP_RAPIDE: 'Vous ne pouvez pointer votre départ moins de 30 minutes après l\'arrivée.',
};

/**
 * Saisie code secours pointage (Sprint 4.5 PR 9).
 *
 * 6 cases input chiffres avec auto-focus enchaîné. Backspace recule.
 * Appelle fn_valider_code_secours avec coords GPS si dispo.
 */
export function SaisieCodeSecours({ missionId, onValide, onAnnuler }: Props) {
  const { afficherNotification } = useNotification();
  const [digits, setDigits] = useState<string[]>(['', '', '', '', '', '']);
  const [loading, setLoading] = useState(false);
  const [resultat, setResultat] = useState<{ success: boolean; methode?: string; horodatage?: string; message?: string } | null>(null);
  const inputRefs = useRef<Array<HTMLInputElement | null>>([]);

  useEffect(() => {
    inputRefs.current[0]?.focus();
  }, []);

  const code = digits.join('');
  const codeComplet = code.length === 6 && /^[0-9]{6}$/.test(code);

  function handleChange(index: number, value: string) {
    const cleanedValue = value.replace(/\D/g, '').slice(-1);
    const newDigits = [...digits];
    newDigits[index] = cleanedValue;
    setDigits(newDigits);
    if (cleanedValue && index < 5) {
      inputRefs.current[index + 1]?.focus();
    }
  }

  function handleKeyDown(index: number, e: React.KeyboardEvent) {
    if (e.key === 'Backspace' && !digits[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
    }
  }

  function handlePaste(e: React.ClipboardEvent) {
    e.preventDefault();
    const pasted = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
    if (pasted.length === 6) {
      setDigits(pasted.split(''));
      inputRefs.current[5]?.focus();
    }
  }

  async function valider() {
    if (!codeComplet) return;
    setLoading(true);
    let lat: number | undefined, lng: number | undefined, precision: number | undefined;
    try {
      const pos = await Promise.race([
        getCurrentPosition({ enableHighAccuracy: true, timeout: 5000 }),
        new Promise<null>((resolve) => setTimeout(() => resolve(null), 5000)),
      ]);
      if (pos) {
        lat = pos.coords.latitude;
        lng = pos.coords.longitude;
        precision = pos.coords.accuracy;
      }
    } catch { /* GPS optionnel */ }

    try {
      const { data, error } = await supabase.rpc('fn_valider_code_secours' as any, {
        p_mission_id: missionId,
        p_code: code,
        p_lat: lat ?? null,
        p_lng: lng ?? null,
        p_precision: precision ?? null,
        p_terminal_id: genererIdTerminal(),
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        const msg = MESSAGES_ERREUR[result?.error_code] || result?.error || 'Erreur';
        setResultat({ success: false, message: msg });
        return;
      }
      setResultat({
        success: true,
        methode: result.methode_detectee,
        horodatage: result.horodatage,
        message: result.methode_detectee === 'ARRIVEE' ? 'Arrivée validée' : 'Départ validé',
      });
      afficherNotification({ type: 'succes', message: result.methode_detectee === 'ARRIVEE' ? 'Arrivée pointée ✅' : 'Départ pointé ✅' });
      setTimeout(() => {
        onValide?.({ methode_detectee: result.methode_detectee, horodatage: result.horodatage });
      }, 2000);
    } catch (err: any) {
      setResultat({ success: false, message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
    }
  }

  if (resultat?.success) {
    return (
      <div className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-4">
        <div className="bg-emerald-50 dark:bg-emerald-950/60 border-2 border-emerald-500 rounded-2xl p-8 text-center max-w-md w-full animate-in zoom-in duration-300">
          <CheckCircle className="h-20 w-20 text-emerald-600 mx-auto mb-4" />
          <p className="text-2xl font-bold text-emerald-900 dark:text-emerald-100">{resultat.message}</p>
          {resultat.horodatage && (
            <p className="text-sm text-emerald-700 dark:text-emerald-300 mt-2 font-mono">
              {new Date(resultat.horodatage).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
            </p>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/90 flex flex-col items-center justify-center p-4">
      <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4 relative">
        <button onClick={onAnnuler} className="absolute top-3 right-3 text-muted-foreground p-2 rounded-full hover:bg-muted">
          <X className="h-5 w-5" />
        </button>

        <div className="text-center">
          <KeyRound className="h-12 w-12 text-primary mx-auto mb-3" />
          <h2 className="text-lg font-bold text-foreground">Code de secours</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Saisissez le code à 6 chiffres communiqué par l'établissement
          </p>
        </div>

        <div className="flex justify-center gap-2" onPaste={handlePaste}>
          {digits.map((d, i) => (
            <input
              key={i}
              ref={(el) => { inputRefs.current[i] = el; }}
              type="text"
              inputMode="numeric"
              maxLength={1}
              value={d}
              onChange={(e) => handleChange(i, e.target.value)}
              onKeyDown={(e) => handleKeyDown(i, e)}
              className="w-12 h-14 text-center text-2xl font-mono font-bold rounded-lg border-2 border-border bg-background focus:border-primary focus:outline-none"
              disabled={loading}
            />
          ))}
        </div>

        {resultat && !resultat.success && (
          <div className="flex items-start gap-2 rounded-lg bg-destructive/10 border border-destructive/30 p-3 text-xs text-destructive">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{resultat.message}</span>
          </div>
        )}

        <button
          onClick={valider}
          disabled={!codeComplet || loading}
          className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
        >
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          Valider le code
        </button>

        <p className="text-[10px] text-muted-foreground text-center">
          Si vous n'avez pas reçu de code, demandez-le à l'établissement.
        </p>
      </div>
    </div>
  );
}
