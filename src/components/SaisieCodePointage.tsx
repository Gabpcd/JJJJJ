import React, { useState, useRef, useCallback } from 'react';
import { Keyboard, Loader2, CheckCircle, XCircle } from 'lucide-react';

interface SaisieCodePointageProps {
  type: 'arrivee' | 'depart';
  onValider: (code: string) => Promise<{ success: boolean; message?: string }>;
}

export function SaisieCodePointage({ type, onValider }: SaisieCodePointageProps) {
  const [ouvert, setOuvert] = useState(false);
  const [digits, setDigits] = useState<string[]>(['', '', '', '', '', '']);
  const [loading, setLoading] = useState(false);
  const [resultat, setResultat] = useState<{ success: boolean; message?: string } | null>(null);
  const inputRefs = useRef<(HTMLInputElement | null)[]>([]);

  const submitCode = useCallback(async (code: string) => {
    setLoading(true);
    setResultat(null);
    try {
      const result = await onValider(code);
      setResultat(result);
      if (!result.success) {
        // Reset after error
        setTimeout(() => {
          setDigits(['', '', '', '', '', '']);
          inputRefs.current[0]?.focus();
        }, 2000);
      }
    } catch {
      setResultat({ success: false, message: 'Erreur réseau' });
    }
    setLoading(false);
  }, [onValider]);

  const handleChange = useCallback((index: number, value: string) => {
    if (!/^\d?$/.test(value)) return;
    const newDigits = [...digits];
    newDigits[index] = value;
    setDigits(newDigits);
    setResultat(null);

    // Auto-focus next
    if (value && index < 5) {
      inputRefs.current[index + 1]?.focus();
    }

    // Auto-submit when all 6 filled
    if (value && index === 5 && newDigits.every(d => d !== '')) {
      void submitCode(newDigits.join(''));
    }
  }, [digits, submitCode]);

  const handleKeyDown = useCallback((index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !digits[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
    }
  }, [digits]);

  const handlePaste = useCallback((e: React.ClipboardEvent) => {
    e.preventDefault();
    const pasted = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
    if (pasted.length === 6) {
      const newDigits = pasted.split('');
      setDigits(newDigits);
      inputRefs.current[5]?.focus();
      void submitCode(pasted);
    }
  }, [submitCode]);

  if (!ouvert) {
    return (
      <button
        onClick={() => {
          setOuvert(true);
          setTimeout(() => inputRefs.current[0]?.focus(), 100);
        }}
        className="w-full py-2.5 rounded-xl text-sm font-medium border border-border text-muted-foreground hover:bg-muted/50 transition-colors flex items-center justify-center gap-2"
      >
        <Keyboard className="h-4 w-4" />
        Pointer avec un code
      </button>
    );
  }

  return (
    <div className="border border-border rounded-xl p-4 space-y-3 bg-card">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-foreground">
          {type === 'arrivee' ? '🔑 Code d\'arrivée' : '🔑 Code de départ'}
        </p>
        <button onClick={() => { setOuvert(false); setDigits(['', '', '', '', '', '']); setResultat(null); }} className="text-xs text-muted-foreground hover:text-foreground">
          Fermer
        </button>
      </div>

      <p className="text-xs text-muted-foreground">
        Entrez le code de pointage à 6 chiffres communiqué par l'établissement
      </p>

      <div className="flex justify-center gap-2" onPaste={handlePaste}>
        {digits.map((digit, i) => (
          <input
            key={i}
            ref={(el) => { inputRefs.current[i] = el; }}
            type="text"
            inputMode="numeric"
            maxLength={1}
            value={digit}
            onChange={(e) => handleChange(i, e.target.value)}
            onKeyDown={(e) => handleKeyDown(i, e)}
            disabled={loading}
            className="w-12 h-12 text-center text-xl font-mono font-bold rounded-lg border-2 border-border bg-background text-foreground focus:border-primary focus:ring-2 focus:ring-primary/20 outline-none transition-all disabled:opacity-50"
          />
        ))}
      </div>

      {loading && (
        <div className="flex items-center justify-center gap-2 text-sm text-primary">
          <Loader2 className="h-4 w-4 animate-spin" /> Vérification...
        </div>
      )}

      {resultat && (
        <div className={`flex items-center justify-center gap-2 text-sm font-medium ${resultat.success ? 'text-success' : 'text-destructive'}`}>
          {resultat.success ? <CheckCircle className="h-4 w-4" /> : <XCircle className="h-4 w-4" />}
          {resultat.message || (resultat.success ? 'Pointage validé !' : 'Code incorrect')}
        </div>
      )}
    </div>
  );
}
