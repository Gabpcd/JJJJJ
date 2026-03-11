import React from 'react';
import { ShieldCheck } from 'lucide-react';

interface BadgeCertificationProps {
  perimetreOk: boolean;
  pasAlerteTeleportation: boolean;
  valideParEtablissement: boolean;
}

export function BadgeCertification({ perimetreOk, pasAlerteTeleportation, valideParEtablissement }: BadgeCertificationProps) {
  const certifie = perimetreOk && pasAlerteTeleportation && valideParEtablissement;
  if (!certifie) return null;

  return (
    <span className="inline-flex items-center gap-1 bg-success/10 text-success px-3 py-1 rounded-full text-xs font-semibold">
      <ShieldCheck className="h-3.5 w-3.5" /> Présence certifiée
    </span>
  );
}
