import { ShieldCheck, ShieldAlert } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';

interface BadgeRPPSProps {
  rppsVerifie: boolean | null;
  rpps: string | null;
  profession?: string;
}

// Professions sans numéro d'identification professionnelle (AS, AES).
// Vérification par diplôme + CNI uniquement.
const PROFESSIONS_SANS_RPPS = ['AS', 'AES'];

export function BadgeRPPS({ rppsVerifie, rpps, profession }: BadgeRPPSProps) {
  if (profession && PROFESSIONS_SANS_RPPS.includes(profession)) return null;
  if (!rpps && !rppsVerifie) return null;

  if (rppsVerifie) {
    return (
      <BadgeY2K variant="success" size="sm" icone={<ShieldCheck className="h-3 w-3" />}>
        RPPS Vérifié
      </BadgeY2K>
    );
  }

  return (
    <BadgeY2K variant="warning" size="sm" icone={<ShieldAlert className="h-3 w-3" />}>
      RPPS Non vérifié
    </BadgeY2K>
  );
}
