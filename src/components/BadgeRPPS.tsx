import { ShieldCheck, ShieldAlert } from 'lucide-react';

interface BadgeRPPSProps {
  rppsVerifie: boolean | null;
  rpps: string | null;
  profession?: string;
}

// Professions sans RPPS (ADELI uniquement)
const PROFESSIONS_SANS_RPPS = ['AS', 'AES'];

export function BadgeRPPS({ rppsVerifie, rpps, profession }: BadgeRPPSProps) {
  // Pas de badge RPPS pour les professions qui n'en ont pas
  if (profession && PROFESSIONS_SANS_RPPS.includes(profession)) return null;
  if (!rpps && !rppsVerifie) return null;

  if (rppsVerifie) {
    return (
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-700">
        <ShieldCheck className="h-3.5 w-3.5" />
        RPPS Vérifié
      </span>
    );
  }

  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-700">
      <ShieldAlert className="h-3.5 w-3.5" />
      RPPS Non vérifié
    </span>
  );
}
