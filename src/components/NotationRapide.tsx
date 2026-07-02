/**
 * NotationRapide — notation 1-tap (F4, Lot 7b).
 *
 * Une note globale 1-5 en un tap ; les 4 critères détaillés sont OPTIONNELS
 * (panneau « Détailler »). Tant que le détail n'est pas touché, les 4 critères
 * envoyés = la note globale — la RPC fn_creer_notation_mission (moyenne des 4)
 * reproduit exactement la note choisie, et toute la machinerie de score
 * existante (propagation, audit, anti-litige) reste inchangée.
 *
 * Deux usages :
 *  - <EtoilesNotation /> : la rangée d'étoiles contrôlée, à intégrer inline
 *    (écran de validation des présences côté étab).
 *  - <SheetNotationRapide /> : sheet légère au check-out soignante
 *    (skippable — « Plus tard » : le bandeau évaluations rattrape).
 */
import { useState } from 'react';
import { Star } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  DialogResponsive, DialogResponsiveContent, DialogResponsiveHeader,
  DialogResponsiveTitle, DialogResponsiveDescription, DialogResponsiveBody,
} from '@/components/ui/DialogResponsive';

export type SensNotation = 'ETAB_VERS_SOIGNANT' | 'SOIGNANT_VERS_ETAB';

export const CRITERES_LABELS: Record<SensNotation, [string, string, string, string]> = {
  ETAB_VERS_SOIGNANT: ['Ponctualité', 'Professionnalisme', 'Qualité du soin', 'Communication'],
  SOIGNANT_VERS_ETAB: ['Accueil', 'Encadrement', 'Clarté des consignes', 'Paiement / administratif'],
};

/**
 * Crée la notation via la RPC existante. Note globale seule → les 4 critères
 * répliquent la note. Retourne true si la note est enregistrée ; les erreurs
 * « déjà notée » sont silencieuses (true), les autres remontent en toast (false).
 */
export async function envoyerNotationRapide(params: {
  missionId: string;
  sens: SensNotation;
  note: number;
  criteres?: [number, number, number, number] | null;
  commentaire?: string;
}): Promise<boolean> {
  const { missionId, sens, note, criteres, commentaire } = params;
  const [c1, c2, c3, c4] = criteres ?? [note, note, note, note];
  const { data, error } = await supabase.rpc('fn_creer_notation_mission', {
    p_mission_id: missionId,
    p_sens: sens,
    p_critere_1: c1, p_critere_2: c2, p_critere_3: c3, p_critere_4: c4,
    p_commentaire: commentaire?.trim() || null,
  });
  if (error) {
    toast.error('La note n\'a pas pu être enregistrée — tu pourras noter depuis la mission.');
    return false;
  }
  const res = data as any;
  if (res?.success) return true;
  // Déjà notée : rien à faire, pas d'erreur à montrer.
  if (typeof res?.error === 'string' && res.error.includes('déjà notée')) return true;
  if (res?.error) {
    toast.error(res.error);
    return false;
  }
  return false;
}

interface EtoilesProps {
  valeur: number;
  onChange: (n: number) => void;
  taille?: 'sm' | 'md' | 'lg';
  label?: string;
  disabled?: boolean;
}

/** Rangée d'étoiles 1-5 contrôlée, accessible (radiogroup). */
export function EtoilesNotation({ valeur, onChange, taille = 'md', label = 'Note', disabled }: EtoilesProps) {
  const px = taille === 'lg' ? 'h-8 w-8' : taille === 'sm' ? 'h-5 w-5' : 'h-6 w-6';
  return (
    <div role="radiogroup" aria-label={label} className="flex items-center gap-1">
      {[1, 2, 3, 4, 5].map(n => (
        <button
          key={n}
          type="button"
          role="radio"
          aria-checked={valeur === n}
          aria-label={`${n} étoile${n > 1 ? 's' : ''}`}
          disabled={disabled}
          onClick={() => onChange(n)}
          className="p-0.5 min-h-[32px] min-w-[32px] flex items-center justify-center disabled:opacity-50"
        >
          <Star
            className={`${px} transition-colors ${n <= valeur ? 'fill-warning text-warning' : 'text-muted-foreground/40'}`}
            aria-hidden="true"
          />
        </button>
      ))}
    </div>
  );
}

interface DetailProps {
  sens: SensNotation;
  criteres: [number, number, number, number];
  onChange: (c: [number, number, number, number]) => void;
}

/** Panneau optionnel : les 4 critères, pré-remplis par la note globale. */
export function DetailCriteres({ sens, criteres, onChange }: DetailProps) {
  return (
    <div className="space-y-2">
      {CRITERES_LABELS[sens].map((labelCritere, i) => (
        <div key={labelCritere} className="flex items-center justify-between gap-3">
          <span className="text-xs text-muted-foreground">{labelCritere}</span>
          <EtoilesNotation
            taille="sm"
            label={labelCritere}
            valeur={criteres[i]}
            onChange={(n) => {
              const next = [...criteres] as [number, number, number, number];
              next[i] = n;
              onChange(next);
            }}
          />
        </div>
      ))}
    </div>
  );
}

interface SheetProps {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  missionId: string;
  sens: SensNotation;
  titre?: string;
  description?: string;
  /** Appelé après enregistrement réussi (ou skip). */
  onDone?: (notee: boolean) => void;
}

/** Sheet de notation au check-out — 1 tap + « Plus tard » toujours possible. */
export function SheetNotationRapide({ open, onOpenChange, missionId, sens, titre, description, onDone }: SheetProps) {
  const [note, setNote] = useState(0);
  const [detailOuvert, setDetailOuvert] = useState(false);
  const [criteres, setCriteres] = useState<[number, number, number, number] | null>(null);
  const [envoi, setEnvoi] = useState(false);

  const fermer = (notee: boolean) => {
    onOpenChange(false);
    setNote(0); setDetailOuvert(false); setCriteres(null);
    onDone?.(notee);
  };

  const envoyer = async () => {
    if (note === 0 || envoi) return;
    setEnvoi(true);
    const ok = await envoyerNotationRapide({ missionId, sens, note, criteres });
    setEnvoi(false);
    if (ok) {
      toast.success('Merci pour ta note ⭐');
      fermer(true);
    }
  };

  return (
    <DialogResponsive open={open} onOpenChange={(o) => { if (!o) fermer(false); else onOpenChange(o); }}>
      <DialogResponsiveContent maxWidth="sm">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>{titre ?? 'Comment s\'est passée ta mission ?'}</DialogResponsiveTitle>
          <DialogResponsiveDescription>
            {description ?? 'Un tap suffit — ta note aide toute la communauté.'}
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody>
          <div className="space-y-4">
            <div className="flex justify-center py-2">
              <EtoilesNotation taille="lg" valeur={note} onChange={(n) => { setNote(n); if (!detailOuvert) setCriteres(null); }} />
            </div>

            <button
              type="button"
              className="text-xs text-primary hover:underline"
              onClick={() => {
                setDetailOuvert(v => !v);
                if (!detailOuvert) setCriteres([note || 3, note || 3, note || 3, note || 3]);
                else setCriteres(null);
              }}
            >
              {detailOuvert ? 'Masquer le détail' : 'Détailler ma note (optionnel)'}
            </button>

            {detailOuvert && criteres && (
              <DetailCriteres sens={sens} criteres={criteres} onChange={setCriteres} />
            )}

            <div className="flex gap-2 pt-1">
              <BoutonY2K className="flex-1" disabled={note === 0} loading={envoi} onClick={envoyer}>
                Envoyer ma note
              </BoutonY2K>
              <BoutonY2K variant="ghost" onClick={() => fermer(false)} disabled={envoi}>
                Plus tard
              </BoutonY2K>
            </div>
          </div>
        </DialogResponsiveBody>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}
