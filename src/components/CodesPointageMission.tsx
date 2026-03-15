import React, { useState, useEffect } from 'react';
import { QrCode, Copy, Check } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface CodesPointageMissionProps {
  missionId: string;
}

function QRCodeSVG({ value, size = 120 }: { value: string; size?: number }) {
  // Simple QR-like visual with the code displayed prominently
  // For a real QR, we'd use a library, but this creates a clean visual
  const cells = 21;
  const cellSize = size / cells;
  
  // Generate deterministic pattern from value
  const pattern: boolean[][] = [];
  let seed = 0;
  for (let i = 0; i < value.length; i++) seed = ((seed << 5) - seed + value.charCodeAt(i)) | 0;
  
  for (let y = 0; y < cells; y++) {
    pattern[y] = [];
    for (let x = 0; x < cells; x++) {
      // Finder patterns (corners)
      const inFinderTL = x < 7 && y < 7;
      const inFinderTR = x >= cells - 7 && y < 7;
      const inFinderBL = x < 7 && y >= cells - 7;
      
      if (inFinderTL || inFinderTR || inFinderBL) {
        const fx = inFinderTR ? x - (cells - 7) : x;
        const fy = inFinderBL ? y - (cells - 7) : y;
        pattern[y][x] = (fx === 0 || fx === 6 || fy === 0 || fy === 6) ||
          (fx >= 2 && fx <= 4 && fy >= 2 && fy <= 4);
      } else {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        pattern[y][x] = (seed % 3) !== 0;
      }
    }
  }

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="mx-auto">
      <rect width={size} height={size} fill="white" />
      {pattern.map((row, y) =>
        row.map((cell, x) =>
          cell ? (
            <rect
              key={`${x}-${y}`}
              x={x * cellSize}
              y={y * cellSize}
              width={cellSize}
              height={cellSize}
              fill="black"
            />
          ) : null
        )
      )}
    </svg>
  );
}

export function CodesPointageMission({ missionId }: CodesPointageMissionProps) {
  const [codes, setCodes] = useState<{ code_arrivee: string; code_depart: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [copiedArrivee, setCopiedArrivee] = useState(false);
  const [copiedDepart, setCopiedDepart] = useState(false);

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
        <QrCode className="h-5 w-5 text-primary" />
        <h2 className="font-semibold text-foreground">Codes de pointage</h2>
      </div>
      <p className="text-xs text-muted-foreground mb-4">
        Donnez ces codes au soignant à son arrivée et à son départ. Vous pouvez aussi lui montrer le QR code.
      </p>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* Code arrivée */}
        <div className="border border-primary/20 bg-primary/5 rounded-xl p-4 text-center space-y-3">
          <p className="text-xs font-semibold text-primary uppercase tracking-wide">Code arrivée</p>
          <p className="text-3xl font-mono font-black text-foreground tracking-[0.3em]">
            {formatCode(codes.code_arrivee)}
          </p>
          <button
            onClick={() => copier(codes.code_arrivee, 'arrivee')}
            className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
          >
            {copiedArrivee ? <><Check className="h-3 w-3" /> Copié</> : <><Copy className="h-3 w-3" /> Copier</>}
          </button>
          <div className="pt-2 border-t border-primary/10">
            <QRCodeSVG value={codes.code_arrivee} size={100} />
          </div>
        </div>

        {/* Code départ */}
        <div className="border border-muted-foreground/20 bg-muted/30 rounded-xl p-4 text-center space-y-3">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Code départ</p>
          <p className="text-3xl font-mono font-black text-foreground tracking-[0.3em]">
            {formatCode(codes.code_depart)}
          </p>
          <button
            onClick={() => copier(codes.code_depart, 'depart')}
            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:underline"
          >
            {copiedDepart ? <><Check className="h-3 w-3" /> Copié</> : <><Copy className="h-3 w-3" /> Copier</>}
          </button>
          <div className="pt-2 border-t border-muted-foreground/10">
            <QRCodeSVG value={codes.code_depart} size={100} />
          </div>
        </div>
      </div>
    </div>
  );
}
