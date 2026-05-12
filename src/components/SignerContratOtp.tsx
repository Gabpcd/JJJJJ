import { useState } from 'react';
import { Loader2, ShieldCheck, MessageSquare } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { mapperErreurInscription } from '@/lib/erreurs';

interface Props {
  contratId: string;
  /** Hash SHA-256 du PDF affiché à l'utilisateur (pour preuve d'intégrité). */
  hashDocument?: string | null;
  /** Image base64 de la signature manuscrite (optionnel, complément AES). */
  signatureImage?: string | null;
  /** Callback appelé après signature réussie. */
  onSigne?: (params: { role: string; contratComplet: boolean }) => void;
}

/**
 * Module signature électronique sécurisée Jolene (PR 4 Sprint 1).
 *
 * Flow :
 *   1. Utilisateur clique "Recevoir code SMS" → fn_envoyer_otp_signature
 *   2. SMS reçu avec OTP 6 chiffres (valide 10 min, max 5 tentatives)
 *   3. Saisit OTP + clic "Signer" → fn_signer_contrat_otp
 *   4. Le backend vérifie OTP + hash + insère signatures_contrats + update
 *      contrats_mission (signature_*_le, mode_signature='JOLENE_OTP').
 *
 * Sécurité : OTP SMS systématique (Option A max), hash SHA-256 du document
 * stocké pour preuve d'intégrité, IP/UA capturés côté serveur via headers.
 *
 * NOTE : ce composant ne génère PAS la valeur "Signature électronique
 * avancée eIDAS" — pour ça il faudrait un PSCo qualifié + cert. Jolene
 * fournit une signature électronique simple/avancée renforcée par OTP +
 * traçabilité, conforme art. 1366-1367 Code civil.
 */
export function SignerContratOtp({ contratId, hashDocument, signatureImage, onSigne }: Props) {
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState<'idle' | 'otp_envoye' | 'signe'>('idle');
  const [otp, setOtp] = useState('');
  const [accepte, setAccepte] = useState(false);
  const [loading, setLoading] = useState(false);
  const [telMasked, setTelMasked] = useState<string | null>(null);

  async function envoyerOtp() {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_envoyer_otp_signature' as any, { p_contrat_id: contratId });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        const mapped = mapperErreurInscription({ message: result?.error || 'Erreur envoi OTP' });
        afficherNotification({ type: 'erreur', message: mapped.message });
        return;
      }
      setTelMasked(result.telephone_masked || null);
      setEtape('otp_envoye');
      afficherNotification({ type: 'succes', message: `Code envoyé au ${result.telephone_masked}. Valide ${result.expire_dans_minutes} min.` });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur envoi OTP' });
    } finally {
      setLoading(false);
    }
  }

  async function signer() {
    if (!/^[0-9]{6}$/.test(otp)) {
      afficherNotification({ type: 'erreur', message: 'Code à 6 chiffres requis.' });
      return;
    }
    if (!accepte) {
      afficherNotification({ type: 'erreur', message: 'Vous devez accepter les termes du contrat avant de signer.' });
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_signer_contrat_otp' as any, {
        p_contrat_id: contratId,
        p_otp_code: otp,
        p_hash_document: hashDocument || null,
        p_signature_image: signatureImage || null,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur de signature' });
        return;
      }
      setEtape('signe');
      afficherNotification({ type: 'succes', message: `Contrat signé ✅${result.contrat_complet ? ' — Mission confirmée par les 2 parties.' : ''}` });
      onSigne?.({ role: result.role, contratComplet: result.contrat_complet });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur de signature' });
    } finally {
      setLoading(false);
    }
  }

  if (etape === 'signe') {
    return (
      <div className="rounded-xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50/60 dark:bg-emerald-950/30 p-4 flex items-start gap-3">
        <ShieldCheck className="h-5 w-5 text-emerald-600 dark:text-emerald-400 shrink-0 mt-0.5" />
        <div>
          <p className="font-semibold text-emerald-900 dark:text-emerald-200">Signature électronique sécurisée Jolene</p>
          <p className="text-xs text-emerald-800 dark:text-emerald-300 mt-1">
            Signé avec succès. Validation par OTP SMS, horodatage et IP capturés (art. 1366-1367 Code civil).
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-start gap-2">
        <MessageSquare className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Signature électronique sécurisée</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Pour signer, recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous.
            La signature inclut horodatage, IP et hash du document (preuve juridique art. 1366 Code civil).
          </p>
        </div>
      </div>

      <label className="flex items-start gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={accepte}
          onChange={e => setAccepte(e.target.checked)}
          className="mt-0.5 accent-primary"
        />
        <span className="text-xs text-foreground">
          J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.
        </span>
      </label>

      {etape === 'idle' && (
        <button
          type="button"
          onClick={envoyerOtp}
          disabled={!accepte || loading}
          className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
        >
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          Recevoir le code SMS pour signer
        </button>
      )}

      {etape === 'otp_envoye' && (
        <>
          <p className="text-xs text-muted-foreground">
            Code SMS envoyé au <strong>{telMasked || 'numéro masqué'}</strong>. Saisissez-le ci-dessous.
          </p>
          <input
            type="text"
            inputMode="numeric"
            pattern="[0-9]{6}"
            maxLength={6}
            value={otp}
            onChange={e => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
            placeholder="123456"
            className="input-base text-center text-lg tracking-widest font-mono"
            aria-label="Code SMS à 6 chiffres"
          />
          <div className="flex gap-2">
            <button
              type="button"
              onClick={envoyerOtp}
              disabled={loading}
              className="btn-secondary flex-1 disabled:opacity-50"
            >
              Renvoyer le code
            </button>
            <button
              type="button"
              onClick={signer}
              disabled={!accepte || otp.length !== 6 || loading}
              className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
            >
              {loading && <Loader2 className="h-4 w-4 animate-spin" />}
              Signer
            </button>
          </div>
        </>
      )}
    </div>
  );
}
