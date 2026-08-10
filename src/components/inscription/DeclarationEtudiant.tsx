import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';

/** Formations reconnues par la table d'équivalence + l'IA (verify-document). */
export const FORMATIONS_ETUDIANT = [
  { valeur: 'IFSI', label: 'Soins infirmiers (IFSI / ESI)' },
  { valeur: 'IFAS', label: 'Aide-soignant (IFAS)' },
  { valeur: 'MEDECINE_DFGSM', label: 'Médecine — 1er cycle (DFGSM)' },
  { valeur: 'MEDECINE_DFASM', label: 'Médecine — 2e cycle (DFASM / externat)' },
  { valeur: 'MAIEUTIQUE', label: 'Maïeutique (sage-femme)' },
  { valeur: 'ODONTOLOGIE', label: 'Odontologie (chirurgie dentaire)' },
  { valeur: 'KINE', label: 'Masso-kinésithérapie (IFMK)' },
  { valeur: 'ERGOTHERAPIE', label: 'Ergothérapie' },
  { valeur: 'PEDICURE_PODOLOGIE', label: 'Pédicurie-podologie' },
  { valeur: 'PSYCHOMOTRICITE', label: 'Psychomotricité' },
  { valeur: 'MANIP_RADIO', label: 'Manipulateur radio (MERM)' },
  { valeur: 'PHARMACIE', label: 'Pharmacie' },
] as const;

// La plus qualifiante des professions autorisées (ex : DFASM2 → {AS, IDE} → IDE).
const PRIORITE = ['MEDECIN', 'SAGE_FEMME', 'PHARMACIEN', 'IADE', 'IBODE', 'IDE', 'DENTISTE', 'KINE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE'];

const CONDITIONS_FORMATION: Record<string, string> = {
  IFSI: 'Pour travailler temporairement comme aide-soignant : admission en 2e année, 48 ECTS dont 15 de stages et validation des UE réglementaires concernées.',
  KINE: 'Admission en K2, 52 ECTS dont 6 de stages et validation des enseignements réglementaires. Une simple inscription en année supérieure ne suffit pas.',
  ERGOTHERAPIE: 'Admission en 2e année, 48 ECTS dont 4 de stages, UE requises, soins d’urgence niveau 2 et stage sanitaire ou médico-social de 4 semaines.',
  PEDICURE_PODOLOGIE: 'Admission en 2e année, 48 ECTS dont 9 de stages, UE requises, soins d’urgence niveau 2 et stage sanitaire ou médico-social de 4 semaines.',
  PSYCHOMOTRICITE: 'Admission en 2e année, soins d’urgence niveau 2 et stage sanitaire ou médico-social de 4 semaines (140 h) permettant les activités d’aide-soignant.',
  MANIP_RADIO: 'Admission en 2e année, 48 ECTS, UE requises et stage sanitaire ou médico-social de 4 semaines permettant les activités d’aide-soignant.',
  MEDECINE_DFGSM: 'La 2e année du premier cycle doit être validée pour travailler temporairement comme aide-soignant.',
  MEDECINE_DFASM: 'La validation du premier cycle permet la pré-éligibilité aide-soignant. Les actes infirmiers relèvent d’un autre cadre supervisé, non proposé au lancement.',
  MAIEUTIQUE: 'La 2e année du premier cycle doit être validée pour travailler temporairement comme aide-soignant.',
  ODONTOLOGIE: 'La 3e année du premier cycle doit être validée pour travailler temporairement comme aide-soignant.',
  PHARMACIE: 'Le remplacement de pharmacien relève d’un parcours distinct (niveau, stage professionnel et certificat ordinal) qui n’est pas proposé au lancement.',
};

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
 * le niveau déclaré, et propose une pré-éligibilité. L'année seule ne donne
 * jamais un droit d'exercice : une attestation détaillée est revue avant toute
 * candidature.
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
        // Pré-lancement : seules les passerelles temporaires vers AS sont
        // présentées. Les élévations IDE/pharmacien nécessitent des preuves et
        // autorisations supplémentaires non réductibles à une année validée.
        setProfessionsAutorisees(liste.filter((profession) => profession === 'AS'));
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
          <p className="text-[11px] text-muted-foreground">Pré-éligibilité à un emploi temporaire selon l'arrêté du 3 février 2022, sous contrôle des preuves.</p>
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
              <span className="text-xs font-medium text-foreground mb-1 block">Dernière année validée</span>
              <input value={annee} onChange={(e) => onChangeAnnee(e.target.value.replace(/\D/g, '').slice(0, 1))}
                inputMode="numeric" placeholder="ex : 1" className="input-base text-sm" />
              <span className="text-[10px] text-muted-foreground mt-1 block">Ex. : admis(e) en 2e année → indique 1.</span>
            </label>
          </div>

          {meilleure && !incoherent && (
            <p className="text-[11px] text-emerald-700 dark:text-emerald-400">
              Pré-éligibilité détectée pour des missions comme <strong>{getLabelProfession(meilleure)}</strong>. L'accès reste bloqué jusqu'à la revue de l'attestation détaillée.
            </p>
          )}

          {incoherent && meilleure && (
            <div className="rounded-lg bg-amber-50 border border-amber-200 dark:bg-amber-950/20 dark:border-amber-800 p-2 text-xs text-amber-800 dark:text-amber-300">
              <p>⚠️ Ce niveau ne justifie pas la profession {getLabelProfession(professionDeclaree)}. Tu peux demander une pré-éligibilité comme <strong>{getLabelProfession(meilleure)}</strong>, sous réserve des preuves réglementaires.</p>
              <button type="button" onClick={() => onSuggererProfession(meilleure)} className="mt-1 font-semibold text-primary underline">
                Choisir le profil {getLabelProfession(meilleure)}
              </button>
            </div>
          )}

          {niveauRenseigne && professionsAutorisees && professionsAutorisees.length === 0 && (
            <p className="text-[11px] text-amber-700 dark:text-amber-400">
              ⚠️ Ce niveau ne permet pas encore d'exercer « faisant fonction » selon nos règles. Tu pourras préciser via ton attestation de scolarité.
            </p>
          )}

          {formation && CONDITIONS_FORMATION[formation] && (
            <div className="rounded-lg border border-info/30 bg-info/5 p-2 text-[11px] text-foreground">
              <strong>Conditions à prouver :</strong> {CONDITIONS_FORMATION[formation]}
            </div>
          )}

          <p className="text-[11px] text-muted-foreground">
            Après inscription, téléverse une attestation détaillée. L'analyse automatique prépare le dossier, mais une revue humaine valide les conditions avant toute candidature.
          </p>
        </>
      )}
    </div>
  );
}
