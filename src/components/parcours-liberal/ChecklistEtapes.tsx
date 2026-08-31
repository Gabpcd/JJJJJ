import { useState } from 'react';
import { ExternalLink, CheckCircle2, Info } from 'lucide-react';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Checkbox } from '@/components/ui/checkbox';

export interface Etape {
  cle: string;
  label: string;
  description?: string;
  lienExterne?: string;
  lienLabel?: string;
  informatif?: boolean;
  /** Documents à préparer — surcharge le défaut DOCS_PAR_ETAPE. */
  documents?: string[];
}

/* Documents à préparer par étape (toutes catégories de professions) — évite au
   soignant de les chercher dans 4 interfaces administratives différentes. */
/* Documents que Jolene détient déjà (Mes documents, vérifiés IA) ou génère
   automatiquement — le soignant clique au lieu de chercher. */
const DOCS_FOURNIS_PAR_JOLENE: Record<string, { route: string; action: string }> = {
  "Pièce d'identité": { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  "Diplôme d'État (original ou copie certifiée)": { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  "Diplôme d'État IPA": { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  'Copie du diplôme': { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  'Diplôme + qualification': { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  'Diplôme': { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  'RIB': { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  'RIB professionnel': { route: '/soignant/mes-documents', action: 'déjà dans Mes documents' },
  'N° RPPS + carte CPS': { route: '/soignant/profil', action: 'RPPS vérifié sur ton profil'},
  'N° RPPS': { route: '/soignant/profil', action: 'RPPS vérifié sur ton profil'},
  "Justificatifs des heures (attestations employeurs — tes attestations Jolene comptent)": { route: '/soignant/attestation-heures', action: 'Jolene génère ton attestation d\'heures' },
};

const DOCS_PAR_ETAPE: Record<string, string[]> = {
  inscription_ordre: ["Pièce d'identité", "Diplôme d'État (original ou copie certifiée)", 'Attestation sur l\'honneur de non-condamnation', 'Justificatif de domicile < 3 mois'],
  inscription_ordre_ipa: ["Pièce d'identité", 'Diplôme d\'État IPA', 'Justificatif de domicile < 3 mois'],
  inscription_ordre_medecins: ["Pièce d'identité", 'Diplôme + qualification', 'CV', 'Casier judiciaire B2 (demandé par l\'Ordre)'],
  inscription_ordre_sages_femmes: ["Pièce d'identité", 'Diplôme d\'État', 'Justificatif de domicile'],
  inscription_onpp: ["Pièce d'identité", 'Diplôme d\'État', 'Justificatif de domicile'],
  inscription_cpam: ['N° RPPS + carte CPS', 'RIB professionnel', 'Attestation d\'inscription à l\'Ordre', 'Justificatifs des heures (attestations employeurs — tes attestations Jolene comptent)'],
  inscription_cpam_ipa: ['N° RPPS + carte CPS', 'RIB professionnel', 'Diplôme IPA'],
  inscription_ars: ["Pièce d'identité", 'Diplôme', 'N° RPPS'],
  inscription_ars_ortho: ["Pièce d'identité", 'Diplôme', 'N° RPPS'],
  immatriculation_urssaf: ["Pièce d'identité", 'Justificatif du local pro (ou domicile)', 'N° RPPS', 'Date de début d\'activité choisie'],
  affiliation_carpimko: ['N° SIRET (obtenu via INPI)', 'Attestation URSSAF', 'Copie du diplôme', 'RIB'],
  affiliation_carmf: ['N° SIRET', 'Attestation URSSAF', 'Copie du diplôme', 'RIB'],
  affiliation_carcdsf: ['N° SIRET', 'Attestation URSSAF', 'Copie du diplôme', 'RIB'],
  affiliation_cipav: ['N° SIRET', 'Attestation URSSAF', 'RIB'],
  souscription_rcp: ['N° RPPS', 'Attestation de conventionnement CPAM', 'Descriptif de ton activité'],
  local_professionnel: ['Bail professionnel ou attestation de domiciliation', 'Registre public d\'accessibilité (PMR)'],
  local_fixe_obligatoire: ['Bail professionnel', 'Registre public d\'accessibilité (PMR)'],
  prevoyance_complementaire: ['RIB', 'Relevé CARPIMKO/caisse de retraite'],
};

interface Props {
  etapes: Etape[];
  etapesValidees: Record<string, unknown>;
  onToggle: (cle: string, valeur: boolean) => Promise<void>;
  disabled?: boolean;
}

export function ChecklistEtapes({ etapes, etapesValidees, onToggle, disabled }: Props) {
  const [optimistic, setOptimistic] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState<Record<string, boolean>>({});

  const isChecked = (cle: string) => {
    if (cle in optimistic) return optimistic[cle];
    return Boolean(etapesValidees[cle]);
  };

  const getDateValidation = (cle: string): string | null => {
    const d = etapesValidees[`${cle}_date`];
    return typeof d === 'string' && d !== 'null' ? d : null;
  };

  const handleToggle = async (cle: string, val: boolean) => {
    setOptimistic(prev => ({ ...prev, [cle]: val }));
    setSaving(prev => ({ ...prev, [cle]: true }));
    try {
      await onToggle(cle, val);
      setOptimistic(prev => {
        const { [cle]: _removed, ...rest } = prev;
        return rest;
      });
    } catch {
      setOptimistic(prev => ({ ...prev, [cle]: !val }));
      toast.error('Impossible de mettre à jour cette étape.');
      setTimeout(() => {
        setOptimistic(prev => {
          const { [cle]: _removed, ...rest } = prev;
          return rest;
        });
      }, 2000);
    } finally {
      setSaving(prev => ({ ...prev, [cle]: false }));
    }
  };

  // Ordre logique : la première étape non cochée est mise en avant comme « à faire ».
  const prochaineCle = etapes.find(e => !e.informatif && !isChecked(e.cle))?.cle;

  return (
    <div className="space-y-2">
      {etapes.map((etape, index) => {
        const checked = isChecked(etape.cle);
        const dateVal = checked ? getDateValidation(etape.cle) : null;
        const estProchaine = etape.cle === prochaineCle;
        const docs = etape.documents ?? DOCS_PAR_ETAPE[etape.cle];

        return (
          <div
            key={etape.cle}
            className={`rounded-xl border p-3 transition-colors duration-200 ${checked ? 'border-success/30 bg-success/5' : estProchaine ? 'border-primary/50 bg-primary/5 ring-1 ring-primary/20' : 'border-border bg-card hover:bg-muted/30'}`}
          >
            <div className="flex items-start gap-3">
              {etape.informatif ? (
                <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
              ) : (
                <label
                  htmlFor={`etape-${etape.cle}`}
                  aria-label={`${checked ? 'Décocher' : 'Cocher'} l’étape ${etape.label}`}
                  className="flex min-h-11 min-w-11 shrink-0 cursor-pointer items-start justify-center pt-1"
                >
                  <Checkbox
                    id={`etape-${etape.cle}`}
                    checked={checked}
                    disabled={disabled || saving[etape.cle]}
                    onCheckedChange={(c) => handleToggle(etape.cle, Boolean(c))}
                    className="mt-0.5 shrink-0"
                  />
                </label>
              )}
              <div className="flex-1 min-w-0">
                <label
                  htmlFor={`etape-${etape.cle}`}
                  className={`flex min-h-11 items-center py-1 text-sm font-semibold ${etape.informatif ? '' : 'cursor-pointer'} ${checked ? 'text-success' : 'text-foreground'}`}
                >
                  <span className="text-muted-foreground font-normal">{index + 1}.</span> {etape.label}
                  {estProchaine && <span className="ml-2 text-[10px] font-bold text-primary uppercase">→ Prochaine étape</span>}
                </label>
                {etape.description && (
                  <p className="text-xs text-muted-foreground mt-1">{etape.description}</p>
                )}
                {checked && dateVal && (
                  <p className="text-[11px] text-success mt-1 flex items-center gap-1">
                    <CheckCircle2 className="h-3 w-3" />
                    Validé le {format(new Date(dateVal), 'd MMM yyyy', { locale: fr })}
                  </p>
                )}
                {docs && docs.length > 0 && !checked && (
                  <div className="mt-2">
                    <p className="text-[11px] font-medium text-foreground mb-1">📂 Documents à préparer :</p>
                    <div className="flex flex-wrap gap-1">
                      {docs.map(d => {
                        const fourni = DOCS_FOURNIS_PAR_JOLENE[d];
                        return fourni ? (
                          <a key={d} href={fourni.route}
                            title={fourni.action}
                            className="text-[10px] px-1.5 py-0.5 rounded-full bg-success/10 text-success hover:bg-success/20 transition-colors">
                            ✓ {d} <span className="opacity-70">({fourni.action})</span>
                          </a>
                        ) : (
                          <span key={d} className="text-[10px] px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground">{d}</span>
                        );
                      })}
                    </div>
                  </div>
                )}
                {etape.lienExterne && (
                  <a
                    href={etape.lienExterne}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-2"
                  >
                    {etape.lienLabel || 'Ouvrir le site'}
                    <ExternalLink className="h-3 w-3" />
                  </a>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
