import React, { useState, useEffect } from 'react';
import { Hash, Copy, Check, QrCode } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface CodesPointageMissionProps {
  missionId: string;
}

export function CodesPointageMission({ missionId }: CodesPointageMissionProps) {
  const [codes, setCodes] = useState<{ code_arrivee: string; code_depart: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [copiedArrivee, setCopiedArrivee] = useState(false);
  const [copiedDepart, setCopiedDepart] = useState(false);
  const [showQR, setShowQR] = useState<'arrivee' | 'depart' | null>(null);

  useEffect(() => {
    const load = async () => {
      const { data, error } = await supabase.rpc('fn_codes_pointage_mission' as any, { p_mission_id: missionId });
      if (!error && data) {
        setCodes(data as any);
      }
      setLoading(false);
    };
    load();
  }, [missionId]);

  const copier = async (code: string, type: 'arrivee' | 'depart') => {
    await navigator.clipboard.writeText(code);
    if (type === 'arrivee') {
      setCopiedArrivee(true);
      setTimeout(() => setCopiedArrivee(false), 2000);
    } else {
      setCopiedDepart(true);
      setTimeout(() => setCopiedDepart(false), 2000);
    }
    toast.success('Code copié !');
  };

  if (loading) return null;
  if (!codes) return null;

  const formatCode = (code: string) => `${code.slice(0, 3)} ${code.slice(3)}`;

  return (
    <div className="card-base">
      <div className="flex items-center gap-2 mb-4">
        <Hash className="h-5 w-5 text-primary" />
        <h2 className="font-semibold text-foreground">Codes de pointage</h2>
      </div>
      <p className="text-xs text-muted-foreground mb-4">
        Communiquez ces codes au soignant ou montrez-lui le QR code à scanner depuis l'application.
      </p>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* Code arrivée */}
        <div className="border border-primary/20 bg-primary/5 rounded-xl p-4 text-center space-y-3">
          <p className="text-xs font-semibold text-primary uppercase tracking-wide">Code d'arrivée</p>
          <p className="text-3xl font-mono font-black text-foreground tracking-[0.3em]">
            {formatCode(codes.code_arrivee)}
          </p>
          <div className="flex items-center justify-center gap-3">
            <button
              onClick={() => copier(codes.code_arrivee, 'arrivee')}
              className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
            >
              {copiedArrivee ? <><Check className="h-3 w-3" /> Copié</> : <><Copy className="h-3 w-3" /> Copier</>}
            </button>
            <button
              onClick={() => setShowQR(showQR === 'arrivee' ? null : 'arrivee')}
              className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
            >
              <QrCode className="h-3 w-3" /> {showQR === 'arrivee' ? 'Masquer QR' : 'QR Code'}
            </button>
          </div>
          {showQR === 'arrivee' && (
            <div className="flex justify-center pt-2">
              <div className="bg-white p-3 rounded-xl inline-block">
                <QRCodeSVG value={codes.code_arrivee} size={160} level="M" />
              </div>
            </div>
          )}
        </div>

        {/* Code départ */}
        <div className="border border-muted-foreground/20 bg-muted/30 rounded-xl p-4 text-center space-y-3">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Code de départ</p>
          <p className="text-3xl font-mono font-black text-foreground tracking-[0.3em]">
            {formatCode(codes.code_depart)}
          </p>
          <div className="flex items-center justify-center gap-3">
            <button
              onClick={() => copier(codes.code_depart, 'depart')}
              className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:underline"
            >
              {copiedDepart ? <><Check className="h-3 w-3" /> Copié</> : <><Copy className="h-3 w-3" /> Copier</>}
            </button>
            <button
              onClick={() => setShowQR(showQR === 'depart' ? null : 'depart')}
              className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:underline"
            >
              <QrCode className="h-3 w-3" /> {showQR === 'depart' ? 'Masquer QR' : 'QR Code'}
            </button>
          </div>
          {showQR === 'depart' && (
            <div className="flex justify-center pt-2">
              <div className="bg-white p-3 rounded-xl inline-block">
                <QRCodeSVG value={codes.code_depart} size={160} level="M" />
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
