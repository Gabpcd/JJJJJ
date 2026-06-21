import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';

/** Formations reconnues par la table d'équivalence + l'IA (verify-document). */
export const FORMATIONS_ETUDIANT = [
  { valeur: 'IFSI', label: 'Soins infirmiers (IFSI / ESI)' },
  { valeur: 'IFAS', label: 'Aide-soignant (IFAS)' },
  { valeur: 'MEDECINE_DFGSM', label: 'Médecine — 1er cycle (DFGSM)' },
  { valeur: 'MEDECINE_DFASM', label: 'Médecine — 2e cycle (DFASM / externat)' },
  { valeur: 'PHARMACIE', label: 'Pharmacie' },
] as const;

// La plus qualifiante des professions autorisées (ex : DFASM2 → {AS, IDE} → IDE).
const PRIORITE = ['MEDECIN', 'SAGE_FEMME', 'PHARMACIEN', 'IADE', 'IBODE', 'IDE', 'DENTISTE', 'KINE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE'];

interface Props {
  estEtudiant: boolean;
  formation: string;
  annee: string;
  professionDeclaree: string;
  onToggle: (v: boolean) => void;
  onChangeFormation: (v: string) => void;
  onChangeAnnee: (v: string) => void;
  onSuggererProfession: (prof: string) => void;
}

/**
 * Déclaration « étudiant en santé » à l'inscription. Calcule (via la table
 * d'équivalence, RPC publique) la profession « faisant fonction » autorisée par
 * le niveau déclaré, et propose de basculer si la profession choisie est trop
 * haute. Le niveau est CONFIRMÉ après inscription via l'attestation de scolarité
 * (vérif IA) — ici c'est déclaratif (la création de compte précède l'upload).
 */
export function DeclarationEtudiant({
  estEtudiant, formation, annee, professionDeclaree,
  onToggle, onChangeFormation, onChangeAnnee, onSuggererProfession,
}: Props) {
  const [professionsAutorisees, setProfessionsAutorisees] = useState<string[] | null>(null);

  useEffect(() => {
    const an = parseInt(annee, 10);
    if (!estEtudiant || !formation || !Number.isFinite(an) || an < 1) {
      setProfessionsAutorisees(null);
      return;
    }
    let annule = false;
    (supabase.rpc as any)('fn_professions_autorisees_scolarite', { p_formation: formation, p_annee_validee: an })
      .then(({ data }: { data: any }) => {
        if (annule) return;
        const liste: string[] = Array.isArray(data)
          ? data.map((r: any) => (typeof r === 'string' ? r : (r?.fn_professions_autorisees_scolarite ?? Object.values(r ?? {})[0]))).filter(Boolean)
          : [];
        setProfessionsAutorisees(liste);
      }, () => { if (!annule) setProfessionsAutorisees([]); });
    return () => { annule = true; };
  }, [estEtudiant, formation, annee]);

  const meilleure = professionsAutorisees?.length
    ? (PRIORITE.find((p) => professionsAutorisees.includes(p)) ?? professionsAutorisees[0])
    : null;
  const incoherent = !!professionDeclaree && !!professionsAutorisees && professionsAutorisees.length > 0 && !professionsAutorisees.includes(professionDeclaree);
  const niveauRenseigne = !!formation && !!annee;

  return (
    <div className="rounded-xl border border-input p-3 space-y-2">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-medium text-foreground">🎓 Je suis étudiant(e) en santé</p>
          <p className="text-[11px] text-muted-foreground">Exercice « faisant fonction » selon votre niveau (arrêté du 03/02/2022).</p>
        </div>
        <button type="button" onClick={() => onToggle(!estEtudiant)}
          aria-pressed={estEtudiant} aria-label="Je suis étudiant en santé"
          className={`relative w-12 h-6 rounded-full transition-colors shrink-0 ${estEtudiant ? 'bg-primary' : 'bg-muted'}`}>
          <span className={`absolute top-0.5 w-5 h-5 rounded-full bg-card shadow transition-transform ${estEtudiant ? 'translate-x-6' : 'translate-x-0.5'}`} />
        </button>
      </div>

      {estEtudiant && (
        <>
          <div className="grid grid-cols-2 gap-2">
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Formation</span>
              <select value={formation} onChange={(e) => onChangeFormation(e.target.value)} className="input-base text-sm">
                <option value="">— Choisir —</option>
                {FORMATIONS_ETUDIANT.map((f) => <option key={f.valeur} value={f.valeur}>{f.label}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Année validée</span>
              <input value={annee} onChange={(e) => onChangeAnnee(e.target.value.replace(/\D/g, '').slice(0, 1))}
                inputMode="numeric" placeholder="ex : 1" className="input-base text-sm" />
            </label>
          </div>

          {meilleure && !incoherent && (
            <p className="text-[11px] text-emerald-700 dark:text-emerald-400">
              ✅ Ce niveau permet d'exercer comme <strong>{getLabelProfession(meilleure)}</strong> (à confirmer par votre attestation après inscription).
            </p>
          )}

          {incoherent && meilleure && (
            <div className="rounded-lg bg-amber-50 border border-amber-200 dark:bg-amber-950/20 dark:border-amber-800 p-2 text-xs text-amber-800 dark:text-amber-300">
              <p>⚠️ Avec ce niveau, vous ne pouvez pas encore exercer comme {getLabelProfession(professionDeclaree)}, mais vous pouvez exercer comme <strong>{getLabelProfession(meilleure)}</strong>.</p>
              <button type="button" onClick={() => onSuggererProfession(meilleure)} className="mt-1 font-semibold text-primary underline">
                M'inscrire comme {getLabelProfession(meilleure)}
              </button>
            </div>
          )}

          {niveauRenseigne && professionsAutorisees && professionsAutorisees.length === 0 && (
            <p className="text-[11px] text-amber-700 dark:text-amber-400">
              ⚠️ Ce niveau ne permet pas encore d'exercer « faisant fonction » selon nos règles. Vous pourrez préciser via votre attestation de scolarité.
            </p>
          )}

          <p className="text-[11px] text-muted-foreground">
            Après inscription, téléversez votre attestation de scolarité : l'IA confirmera votre niveau.
          </p>
        </>
      )}
    </div>
  );
}
