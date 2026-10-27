import { PROFESSIONS, PROFESSIONS_RPPS_REQUIS, TYPES_ETABLISSEMENT } from '../../../src/lib/constantes';
import { validerSiret } from '../../../src/lib/luhn';
import type { NativeAccountType, NativeRegistrationForm } from './types';
import { NativeAccountError } from './errors';

// Same declarations as web DeclarationEtudiant; never infer a professional right from a cycle.
export const STUDENT_FORMATIONS = [
  { valeur: 'IFSI', label: 'Soins infirmiers (IFSI / ESI)' },
  { valeur: 'IFAS', label: 'Aide-soignant (IFAS)' },
  { valeur: 'MEDECINE_DFGSM', label: 'Médecine — 1er cycle (DFGSM)' },
  { valeur: 'MEDECINE_DFASM', label: 'Médecine — 2e cycle (DFASM / externat)' },
  { valeur: 'MEDECINE_DES', label: 'Médecine — 3e cycle (internat)' },
  { valeur: 'MAIEUTIQUE', label: 'Maïeutique (sage-femme)' },
  { valeur: 'ODONTOLOGIE', label: 'Odontologie (chirurgie dentaire)' },
  { valeur: 'KINE', label: 'Masso-kinésithérapie (IFMK)' },
  { valeur: 'ERGOTHERAPIE', label: 'Ergothérapie' },
  { valeur: 'PEDICURE_PODOLOGIE', label: 'Pédicurie-podologie' },
  { valeur: 'PSYCHOMOTRICITE', label: 'Psychomotricité' },
  { valeur: 'MANIP_RADIO', label: 'Manipulateur radio (MERM)' },
  { valeur: 'PHARMACIE', label: 'Pharmacie' },
] as const;
export const studentFormations = (profession: string) => STUDENT_FORMATIONS.filter(({ valeur }) =>
  profession === 'MEDECIN' ? valeur.startsWith('MEDECINE_') : valeur !== 'MEDECINE_DES');
export function studentDetails(form: NativeRegistrationForm): string | null {
  const formation = studentFormations(form.profession).find(f => f.valeur === form.scolariteFormation);
  if (!form.estEtudiant || !formation) return null;
  if (formation.valeur === 'MEDECINE_DES') return formation.label;
  return form.scolariteAnnee ? `${formation.label} — année ${form.scolariteAnnee} validée` : null;
}
export function restoreRegistrationForm(values: Record<string, unknown> = {}): NativeRegistrationForm {
  const form: NativeRegistrationForm = {
    prenom: '', nom: '', telephone: '', dateNaissance: '', profession: '', typesContrat: [], rpps: '', rayon: 30,
    estEtudiant: false, scolariteFormation: '', scolariteAnnee: '', siret: '', finess: '', type: '', rue: '', ville: '',
    codePostal: '', departement: '', emailContact: '', telephoneContact: '', numeroLicence: '',
  };
  for (const key of Object.keys(form) as (keyof NativeRegistrationForm)[]) {
    const value = values[key];
    if (key === 'typesContrat') {
      if (Array.isArray(value) && value.every(v => typeof v === 'string')) form.typesContrat = [...value];
    } else if (typeof value === typeof form[key]) Object.assign(form, { [key]: value });
  }
  if (!studentFormations(form.profession).some(f => f.valeur === form.scolariteFormation)) {
    form.scolariteFormation = ''; form.scolariteAnnee = '';
  }
  return form;
}
export function validateRegistrationForm(type: NativeAccountType, form: NativeRegistrationForm): void {
  if (type === 'ETABLISSEMENT') {
    if (!form.nom.trim() || !validerSiret(form.siret).valide || !TYPES_ETABLISSEMENT.some(t => t.valeur === form.type) || !form.ville.trim()) {
      throw new NativeAccountError('Renseignez le nom, un SIRET valide, le type et la ville de votre établissement.');
    }
    return;
  }
  if (!form.prenom.trim() || !form.nom.trim() || !PROFESSIONS.some(p => p.valeur === form.profession)
    || !/^[+]?[0-9\s]{8,15}$/.test(form.telephone.trim()) || !form.typesContrat.length) {
    throw new NativeAccountError('Renseignez votre prénom, nom, profession, téléphone et au moins un mode d’exercice.');
  }
  const birth = new Date(`${form.dateNaissance}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(form.dateNaissance) || !Number.isFinite(birth.getTime()) || birth.toISOString().slice(0, 10) !== form.dateNaissance) {
    throw new NativeAccountError('Saisissez une date de naissance valide au format AAAA-MM-JJ.');
  }
  const today = new Date();
  let age = today.getUTCFullYear() - birth.getUTCFullYear();
  if (today.getUTCMonth() < birth.getUTCMonth() || (today.getUTCMonth() === birth.getUTCMonth() && today.getUTCDate() < birth.getUTCDate())) age -= 1;
  if (age < 18) throw new NativeAccountError('Vous devez avoir au moins 18 ans pour vous inscrire.');
  if ((form.rpps || PROFESSIONS_RPPS_REQUIS.includes(form.profession)) && !/^\d{11}$/.test(form.rpps)) {
    throw new NativeAccountError('Renseignez un numéro RPPS à 11 chiffres pour cette profession.');
  }
}
export function registrationBody(type: NativeAccountType, form: NativeRegistrationForm, email: string | null) {
  validateRegistrationForm(type, form);
  return type === 'SOIGNANT' ? {
    prenom: form.prenom.trim(), nom: form.nom.trim(), telephone: form.telephone.trim(), dateNaissance: form.dateNaissance,
    profession: form.profession, typesContrat: form.typesContrat, rpps: form.rpps || null, rayon: form.rayon,
    est_etudiant: form.estEtudiant, etudiant_details: studentDetails(form),
  } : {
    nom: form.nom.trim(), siret: form.siret, finess: form.finess || null, type: form.type,
    adresse_rue: form.rue || null, adresse_ville: form.ville.trim(), adresse_code_postal: form.codePostal || null,
    adresse_departement: form.departement || null, email_contact: form.emailContact || email,
    telephone_contact: form.telephoneContact || null, numero_licence: form.numeroLicence || null,
  };
}
