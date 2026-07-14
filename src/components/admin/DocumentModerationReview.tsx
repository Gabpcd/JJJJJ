import { useMemo, useState } from 'react';
import { AlertTriangle, Check, Eye, FileCheck2, ShieldCheck, UserRound, X } from 'lucide-react';

import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';

export type DocumentModerationProfile = {
  id: string;
  prenom: string;
  nom: string;
  email: string;
  profession: string | null;
  date_naissance: string | null;
  numero_rpps: string | null;
  numero_adeli: string | null;
  rpps_verifie: boolean | null;
  adeli_verifie: boolean | null;
  modifie_le: string | null;
};

export type DocumentModerationEntry = {
  id: string;
  nom_fichier: string;
  type_document: string;
  soignant_id: string;
  televerse_le: string | null;
  modifie_le: string | null;
  s3_bucket: string;
  s3_cle: string;
  s3_version_id: string | null;
  type_mime: string | null;
  taille_octets: number | null;
  statut_verification: string;
  motif_rejet: string | null;
  resultat_ia: Record<string, unknown> | null;
  nom_extrait_ia: string | null;
  prenom_extrait_ia: string | null;
  score_confiance_ia: number | null;
  coherence_nom: boolean | null;
  valide_depuis: string | null;
  valide_jusqua: string | null;
  exige_expiration: boolean;
  soignant: DocumentModerationProfile | null;
};

export type DocumentValidationPayload = {
  validation: Record<string, unknown>;
  raisonOverride: string | null;
};

const LABELS_PROFESSION: Record<string, string> = {
  IDE: 'Infirmier·ère diplômé·e d’État (IDE)',
  IADE: 'Infirmier·ère anesthésiste (IADE)',
  IBODE: 'Infirmier·ère de bloc opératoire (IBODE)',
  AS: 'Aide-soignant·e',
  AES: 'Accompagnant·e éducatif et social',
  SAGE_FEMME: 'Sage-femme',
  MEDECIN: 'Médecin',
  PHARMACIEN: 'Pharmacien·ne',
  KINE: 'Masseur-kinésithérapeute',
  DENTISTE: 'Chirurgien-dentiste',
  PREPARATEUR_PHARMA: 'Préparateur·rice en pharmacie',
  AUXILIAIRE_PUERICULTURE: 'Auxiliaire de puériculture',
  MANIPULATEUR_RADIO: 'Manipulateur·rice radio',
  ERGOTHERAPEUTE: 'Ergothérapeute',
  PSYCHOMOTRICIEN: 'Psychomotricien·ne',
  ORTHOPHONISTE: 'Orthophoniste',
  DIETETICIEN: 'Diététicien·ne',
};

const TYPES_IDENTITE = new Set(['CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR']);
const TYPES_DIPLOME = new Set(['DIPLOME', 'AUTORISATION_EXERCICE']);
const TYPES_HEURES = new Set(['BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL']);

const aiText = (analysis: Record<string, unknown> | null, key: string): string => {
  const value = analysis?.[key];
  return typeof value === 'string' ? value.trim() : '';
};

const aiNumber = (analysis: Record<string, unknown> | null, key: string): number | null => {
  const value = analysis?.[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
};

const formatDate = (date?: string | null) => date
  ? new Date(`${date.length === 10 ? `${date}T12:00:00` : date}`).toLocaleDateString('fr-FR')
  : 'Non renseignée';

const formatFileSize = (bytes: number | null) => {
  if (!bytes || bytes <= 0) return 'Taille inconnue';
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} Ko`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} Mo`;
};

export function documentAnalysisSource(document: DocumentModerationEntry) {
  const analysis = document.resultat_ia;
  if (document.statut_verification === 'API_INDISPONIBLE' || analysis?.erreur_anthropic || analysis?.erreur_parse) {
    return {
      label: 'IA indisponible — saisie manuelle requise',
      description: 'Aucun verdict automatique exploitable. La décision doit être renseignée champ par champ.',
      variant: 'warning' as const,
    };
  }
  if (analysis) {
    return {
      label: 'Analyse IA + contrôles serveur',
      description: 'Les extractions sont des aides à la revue : elles ne remplacent pas la lecture du fichier.',
      variant: 'info' as const,
    };
  }
  return {
    label: 'Aucune analyse automatique',
    description: 'Renseignez manuellement tous les champs obligatoires après lecture du fichier.',
    variant: 'warning' as const,
  };
}

export function documentRequiresExceptionalOverride(document: DocumentModerationEntry): boolean {
  const analysis = document.resultat_ia;
  if (document.statut_verification === 'API_INDISPONIBLE' || !analysis || analysis.erreur_anthropic || analysis.erreur_parse) return false;
  const indicators = analysis.indices_falsification;
  return aiText(analysis, 'verdict').toUpperCase() === 'REJETE'
    || aiText(analysis, 'verdict_serveur').toUpperCase() === 'REJETE'
    || analysis.type_correspond === false
    || analysis.document_lisible === false
    || analysis.document_complet === false
    || analysis.nom_correspond === false
    || document.coherence_nom === false
    || (Array.isArray(indicators) && indicators.length > 0);
}

export function buildDocumentCasSnapshot(document: DocumentModerationEntry) {
  return {
    expected_document_modifie_le: document.modifie_le,
    expected_soignant_modifie_le: document.soignant?.modifie_le ?? null,
    expected_statut: document.statut_verification,
    expected_type_document: document.type_document,
    expected_soignant_id: document.soignant_id,
    expected_s3_bucket: document.s3_bucket,
    expected_s3_cle: document.s3_cle,
    expected_s3_version_id: document.s3_version_id,
  };
}

type Detail = { label: string; value: string; alert?: boolean };

export function documentSpecificDetails(document: DocumentModerationEntry): Detail[] {
  const analysis = document.resultat_ia;
  const type = document.type_document;
  const details: Detail[] = [];
  if (TYPES_IDENTITE.has(type)) {
    details.push(
      { label: 'Date de naissance lue', value: aiText(analysis, 'date_naissance_extraite') || 'Non extraite', alert: !aiText(analysis, 'date_naissance_extraite') },
      { label: 'Expiration lue', value: aiText(analysis, 'date_expiration') || 'Non extraite', alert: !aiText(analysis, 'date_expiration') },
    );
  }
  if (TYPES_DIPLOME.has(type)) {
    details.push(
      { label: 'Profession certifiée', value: aiText(analysis, 'profession_certifiee') || 'Non extraite', alert: !aiText(analysis, 'profession_certifiee') },
      { label: 'Diplôme étranger', value: analysis?.diplome_etranger === true ? 'Oui — autorisation d’exercice requise' : analysis?.diplome_etranger === false ? 'Non' : 'Non déterminé' },
    );
  }
  if (type === 'RIB') {
    details.push(
      { label: 'Titulaire lu', value: [document.prenom_extrait_ia, document.nom_extrait_ia].filter(Boolean).join(' ') || 'Non extrait', alert: !document.nom_extrait_ia },
      { label: 'IBAN contrôlé', value: analysis?.iban_valide === true ? `Oui ···· ${aiText(analysis, 'iban_last4')}` : 'À contrôler manuellement', alert: analysis?.iban_valide !== true },
    );
  }
  if (type === 'RPPS_ADELI') {
    details.push(
      { label: 'Registre lu', value: aiText(analysis, 'type_identifiant_professionnel') || 'Non extrait', alert: !aiText(analysis, 'type_identifiant_professionnel') },
      { label: 'Numéro lu', value: aiText(analysis, 'numero_professionnel_extrait') || 'Non extrait', alert: !aiText(analysis, 'numero_professionnel_extrait') },
    );
  }
  if (type === 'ATTESTATION_SCOLARITE') {
    details.push(
      { label: 'Formation', value: aiText(analysis, 'scolarite_formation') || 'Non extraite', alert: !aiText(analysis, 'scolarite_formation') },
      { label: 'Année validée', value: String(analysis?.scolarite_annee_validee ?? 'Non extraite') },
      { label: 'Date d’émission', value: aiText(analysis, 'date_emission') || 'Non extraite', alert: !aiText(analysis, 'date_emission') },
    );
  }
  if (type === 'LICENCE_REMPLACEMENT') {
    details.push(
      { label: 'Spécialité / DES', value: aiText(analysis, 'licence_remplacement_specialite') || 'Non extrait', alert: !aiText(analysis, 'licence_remplacement_specialite') },
      { label: 'Période', value: `${aiText(analysis, 'date_emission') || '?'} → ${aiText(analysis, 'date_expiration') || '?'}` },
    );
  }
  if (TYPES_HEURES.has(type)) {
    details.push(
      { label: 'Employeur', value: aiText(analysis, 'employeur_extrait') || 'Non extrait', alert: !aiText(analysis, 'employeur_extrait') },
      { label: 'Période', value: `${aiText(analysis, 'periode_debut_extraite') || '?'} → ${aiText(analysis, 'periode_fin_extraite') || '?'}` },
      { label: 'Heures lues', value: String(analysis?.heures_extraites ?? 'Non extraites') },
    );
  }
  if (document.exige_expiration && !details.some((detail) => detail.label.toLowerCase().includes('expiration'))) {
    details.push({ label: 'Expiration requise', value: aiText(analysis, 'date_expiration') || 'Non extraite', alert: !aiText(analysis, 'date_expiration') });
  }
  return details;
}

type CardProps = {
  document: DocumentModerationEntry;
  typeLabel: string;
  onOpen: (document: DocumentModerationEntry) => void;
  onValidate: (document: DocumentModerationEntry) => void;
  onReject: (document: DocumentModerationEntry) => void;
};

export function DocumentModerationCard({ document, typeLabel, onOpen, onValidate, onReject }: CardProps) {
  const source = documentAnalysisSource(document);
  const details = documentSpecificDetails(document);
  const analysis = document.resultat_ia;
  const motif = aiText(analysis, 'motif_serveur') || document.motif_rejet || aiText(analysis, 'motif_rejet');
  const indicators = Array.isArray(analysis?.indices_falsification)
    ? analysis.indices_falsification.filter((value): value is string => typeof value === 'string')
    : [];
  const profile = document.soignant;
  const score = document.score_confiance_ia ?? aiNumber(analysis, 'score_confiance');

  return (
    <article className="rounded-2xl border border-border bg-card p-4 shadow-sm space-y-4" aria-labelledby={`document-${document.id}`}>
      <header className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <BadgeY2K variant="info" size="sm">{typeLabel}</BadgeY2K>
            <BadgeY2K variant={source.variant} size="sm">{source.label}</BadgeY2K>
          </div>
          <h3 id={`document-${document.id}`} className="font-semibold text-foreground break-words">{document.nom_fichier}</h3>
          <p className="text-xs text-muted-foreground">
            Téléversé le {formatDate(document.televerse_le)} · {document.type_mime || 'Format inconnu'} · {formatFileSize(document.taille_octets)}
          </p>
        </div>
        <BoutonY2K size="sm" variant="ghost" onClick={() => onOpen(document)} iconeGauche={<Eye className="h-4 w-4" />}>
          Ouvrir la preuve
        </BoutonY2K>
      </header>

      <div className="grid gap-3 xl:grid-cols-3">
        <section className="rounded-xl border border-border/70 bg-muted/30 p-3 space-y-2" aria-label="Identité et profession du profil">
          <h4 className="flex items-center gap-2 text-sm font-semibold"><UserRound className="h-4 w-4" />Profil à vérifier</h4>
          {profile ? (
            <dl className="grid gap-1.5 text-xs">
              <Row label="Identité" value={`${profile.prenom} ${profile.nom}`} />
              <Row label="Naissance" value={formatDate(profile.date_naissance)} alert={!profile.date_naissance && TYPES_IDENTITE.has(document.type_document)} />
              <Row label="Profession" value={profile.profession ? (LABELS_PROFESSION[profile.profession] || profile.profession) : 'Non renseignée'} alert={!profile.profession} />
              <Row label="RPPS" value={profile.numero_rpps ? `${profile.numero_rpps}${profile.rpps_verifie ? ' · registre vérifié' : ' · non vérifié'}` : 'Non renseigné'} />
              <Row label="ADELI" value={profile.numero_adeli ? `${profile.numero_adeli}${profile.adeli_verifie ? ' · registre vérifié' : ' · non vérifié'}` : 'Non renseigné'} />
            </dl>
          ) : (
            <p className="text-xs text-destructive">Profil indisponible : validation bloquée.</p>
          )}
        </section>

        <section className="rounded-xl border border-border/70 bg-muted/30 p-3 space-y-2" aria-label="Résultat de l'analyse automatique">
          <h4 className="flex items-center gap-2 text-sm font-semibold"><ShieldCheck className="h-4 w-4" />Analyse et motif</h4>
          <p className="text-xs text-muted-foreground">{source.description}</p>
          <dl className="grid gap-1.5 text-xs">
            <Row label="Type détecté" value={aiText(analysis, 'type_detecte') || 'Non détecté'} />
            <Row label="Verdict IA / serveur" value={[aiText(analysis, 'verdict'), aiText(analysis, 'verdict_serveur')].filter(Boolean).join(' → ') || 'Aucun'} />
            <Row label="Confiance" value={`${aiText(analysis, 'confiance') || 'Non renseignée'}${score !== null ? ` · ${score}/100` : ''}`} />
            <Row label="Identité extraite" value={[document.prenom_extrait_ia, document.nom_extrait_ia].filter(Boolean).join(' ') || 'Non extraite'} alert={document.coherence_nom === false} />
          </dl>
          {motif && <p className="rounded-lg bg-jolene-butter-100 p-2 text-xs text-jolene-butter-800"><strong>Motif :</strong> {motif}</p>}
          {indicators.length > 0 && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-2 text-xs text-destructive">
              <p className="font-semibold">Indices à examiner</p>
              <ul className="list-disc pl-4 mt-1 space-y-0.5">{indicators.map((indicator, index) => <li key={`${indicator}-${index}`}>{indicator}</li>)}</ul>
            </div>
          )}
        </section>

        <section className="rounded-xl border border-border/70 bg-muted/30 p-3 space-y-2" aria-label="Champs spécifiques au document">
          <h4 className="flex items-center gap-2 text-sm font-semibold"><FileCheck2 className="h-4 w-4" />Contrôles spécifiques</h4>
          {details.length > 0 ? (
            <dl className="grid gap-1.5 text-xs">{details.map((detail) => <Row key={detail.label} {...detail} />)}</dl>
          ) : (
            <p className="text-xs text-muted-foreground">Identité, type, lisibilité, complétude, antifraude et dates éventuelles restent à confirmer.</p>
          )}
        </section>
      </div>

      <footer className="flex flex-col gap-2 border-t border-border/70 pt-3 sm:flex-row sm:justify-end">
        <BoutonY2K size="sm" variant="destructive" onClick={() => onReject(document)} iconeGauche={<X className="h-4 w-4" />}>
          Rejeter avec motif
        </BoutonY2K>
        <BoutonY2K size="sm" variant="secondary" disabled={!profile} onClick={() => onValidate(document)} iconeGauche={<Check className="h-4 w-4" />}>
          Ouvrir la revue de validation
        </BoutonY2K>
      </footer>
    </article>
  );
}

function Row({ label, value, alert }: Detail) {
  return (
    <div className="flex items-start justify-between gap-3">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className={alert ? 'text-right font-medium text-destructive' : 'text-right text-foreground break-words'}>{value}</dd>
    </div>
  );
}

type ValidationDialogProps = {
  document: DocumentModerationEntry;
  typeLabel: string;
  loading?: boolean;
  onCancel: () => void;
  onConfirm: (payload: DocumentValidationPayload) => void;
};

export function DocumentValidationDialog({ document, typeLabel, loading, onCancel, onConfirm }: ValidationDialogProps) {
  const analysis = document.resultat_ia;
  const overrideRequired = documentRequiresExceptionalOverride(document);
  const [nomExtrait, setNomExtrait] = useState(document.nom_extrait_ia || aiText(analysis, 'nom_extrait'));
  const [prenomExtrait, setPrenomExtrait] = useState(document.prenom_extrait_ia || aiText(analysis, 'prenom_extrait'));
  const [dateNaissance, setDateNaissance] = useState(aiText(analysis, 'date_naissance_extraite'));
  const [dateEmission, setDateEmission] = useState(aiText(analysis, 'date_emission'));
  const [dateExpiration, setDateExpiration] = useState(aiText(analysis, 'date_expiration'));
  const [professionCertifiee, setProfessionCertifiee] = useState(aiText(analysis, 'profession_certifiee'));
  const [diplomeEtranger, setDiplomeEtranger] = useState(analysis?.diplome_etranger === true);
  const [typeIdentifiant, setTypeIdentifiant] = useState(aiText(analysis, 'type_identifiant_professionnel'));
  const [numeroProfessionnel, setNumeroProfessionnel] = useState(aiText(analysis, 'numero_professionnel_extrait'));
  const [iban, setIban] = useState('');
  const [formation, setFormation] = useState(aiText(analysis, 'scolarite_formation'));
  const [anneeValidee, setAnneeValidee] = useState(String(analysis?.scolarite_annee_validee ?? ''));
  const [specialiteLicence, setSpecialiteLicence] = useState(aiText(analysis, 'licence_remplacement_specialite'));
  const [employeur, setEmployeur] = useState(aiText(analysis, 'employeur_extrait'));
  const [periodeDebut, setPeriodeDebut] = useState(aiText(analysis, 'periode_debut_extraite'));
  const [periodeFin, setPeriodeFin] = useState(aiText(analysis, 'periode_fin_extraite'));
  const [heures, setHeures] = useState(String(analysis?.heures_extraites ?? ''));
  const [lisible, setLisible] = useState(false);
  const [complet, setComplet] = useState(false);
  const [typeConfirme, setTypeConfirme] = useState(false);
  const [antifraude, setAntifraude] = useState(false);
  const [overrideConfirme, setOverrideConfirme] = useState(false);
  const [raisonOverride, setRaisonOverride] = useState('');

  const specificComplete = useMemo(() => {
    if (TYPES_IDENTITE.has(document.type_document)) return Boolean(dateNaissance && dateExpiration);
    if (TYPES_DIPLOME.has(document.type_document)) return Boolean(professionCertifiee);
    if (document.type_document === 'RIB') return iban.replace(/\s/g, '').length >= 15;
    if (document.type_document === 'RPPS_ADELI') return Boolean(typeIdentifiant && numeroProfessionnel);
    if (document.type_document === 'ATTESTATION_SCOLARITE') return Boolean(formation && anneeValidee && dateEmission);
    if (document.type_document === 'LICENCE_REMPLACEMENT') return Boolean(specialiteLicence && dateEmission && dateExpiration);
    if (TYPES_HEURES.has(document.type_document)) return Boolean(employeur && periodeDebut && periodeFin && heures);
    if (document.exige_expiration) return Boolean(dateExpiration);
    return true;
  }, [anneeValidee, dateEmission, dateExpiration, dateNaissance, document.exige_expiration, document.type_document, employeur, formation, heures, iban, numeroProfessionnel, periodeDebut, periodeFin, professionCertifiee, specialiteLicence, typeIdentifiant]);

  const canSubmit = Boolean(
    document.soignant
      && nomExtrait.trim()
      && prenomExtrait.trim()
      && lisible
      && complet
      && typeConfirme
      && antifraude
      && specificComplete
      && (!overrideRequired || (overrideConfirme && raisonOverride.trim().length >= 30)),
  );

  const submit = () => {
    if (!canSubmit) return;
    onConfirm({
      validation: {
        ...buildDocumentCasSnapshot(document),
        document_lisible: lisible,
        document_complet: complet,
        type_document_confirme: typeConfirme,
        antifraude_verifiee: antifraude,
        override_confirme: overrideConfirme,
        nom_extrait: nomExtrait.trim(),
        prenom_extrait: prenomExtrait.trim(),
        date_naissance: dateNaissance || null,
        date_emission: dateEmission || null,
        date_expiration: dateExpiration || null,
        profession_certifiee: professionCertifiee || null,
        diplome_etranger: diplomeEtranger,
        type_identifiant_professionnel: typeIdentifiant || null,
        numero_professionnel: numeroProfessionnel || null,
        iban: iban || null,
        scolarite_formation: formation || null,
        scolarite_annee_validee: anneeValidee || null,
        licence_remplacement_specialite: specialiteLicence || null,
        employeur_extrait: employeur || null,
        periode_debut_extraite: periodeDebut || null,
        periode_fin_extraite: periodeFin || null,
        heures_extraites: heures || null,
      },
      raisonOverride: overrideRequired ? raisonOverride.trim() : null,
    });
  };

  return (
    <Dialog open onOpenChange={(open) => !open && !loading && onCancel()}>
      <DialogContent
        className="w-full max-w-3xl space-y-5 rounded-2xl bg-card p-5"
        onEscapeKeyDown={(event) => loading && event.preventDefault()}
        onPointerDownOutside={(event) => loading && event.preventDefault()}
      >
        <DialogHeader className="space-y-1 pr-7">
          <DialogTitle>Revue avant validation — {typeLabel}</DialogTitle>
          <DialogDescription>Lisez la preuve ouverte, comparez-la au profil puis confirmez chaque contrôle. La décision et le snapshot sont journalisés.</DialogDescription>
        </DialogHeader>

        {documentAnalysisSource(document).variant === 'warning' && (
          <div className="flex gap-2 rounded-xl border border-jolene-butter-400 bg-jolene-butter-100 p-3 text-sm text-jolene-butter-800" role="status">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <p>L’analyse automatique est indisponible ou incomplète. Une validation reste possible, mais uniquement avec tous les champs manuels ci-dessous.</p>
          </div>
        )}

        <section className="grid gap-3 sm:grid-cols-2" aria-labelledby="identite-lue">
          <h3 id="identite-lue" className="sm:col-span-2 text-sm font-semibold">Identité réellement lue sur le document</h3>
          <Field label="Nom *"><Input value={nomExtrait} onChange={(event) => setNomExtrait(event.target.value)} autoComplete="off" disabled={loading} /></Field>
          <Field label="Prénom *"><Input value={prenomExtrait} onChange={(event) => setPrenomExtrait(event.target.value)} autoComplete="off" disabled={loading} /></Field>
        </section>

        <SpecificValidationFields
          document={document}
          values={{ dateNaissance, dateEmission, dateExpiration, professionCertifiee, diplomeEtranger, typeIdentifiant, numeroProfessionnel, iban, formation, anneeValidee, specialiteLicence, employeur, periodeDebut, periodeFin, heures }}
          setters={{ setDateNaissance, setDateEmission, setDateExpiration, setProfessionCertifiee, setDiplomeEtranger, setTypeIdentifiant, setNumeroProfessionnel, setIban, setFormation, setAnneeValidee, setSpecialiteLicence, setEmployeur, setPeriodeDebut, setPeriodeFin, setHeures }}
          loading={loading}
        />

        <fieldset className="rounded-xl border border-border p-3 space-y-3">
          <legend className="px-1 text-sm font-semibold">Confirmations obligatoires</legend>
          <ReviewCheckbox checked={lisible} onChange={setLisible} label="Le document est lisible, sans page ou zone essentielle masquée." disabled={loading} />
          <ReviewCheckbox checked={complet} onChange={setComplet} label="Le document est complet et toutes les pages utiles ont été examinées." disabled={loading} />
          <ReviewCheckbox checked={typeConfirme} onChange={setTypeConfirme} label={`Le fichier est bien un document de type « ${typeLabel} ».`} disabled={loading} />
          <ReviewCheckbox checked={antifraude} onChange={setAntifraude} label="J’ai contrôlé les signes de retouche, montage, incohérence de police, photo, numéros et dates." disabled={loading} />
        </fieldset>

        {overrideRequired && (
          <fieldset className="rounded-xl border border-destructive/40 bg-destructive/5 p-3 space-y-3">
            <legend className="px-1 text-sm font-semibold text-destructive">Dérogation exceptionnelle obligatoire</legend>
            <p className="text-xs text-muted-foreground">L’analyse contient un rejet, une contradiction ou un indice de falsification. Les contrôles déterministes restent non contournables ; expliquez précisément pourquoi la lecture humaine permet néanmoins de retenir la preuve.</p>
            <ReviewCheckbox checked={overrideConfirme} onChange={setOverrideConfirme} label="Je confirme demander une dérogation exceptionnelle, personnellement tracée." disabled={loading} />
            <Field label="Motivation détaillée * (30 caractères minimum)">
              <Textarea value={raisonOverride} onChange={(event) => setRaisonOverride(event.target.value)} rows={4} disabled={loading} placeholder="Décrivez les éléments matériels vérifiés et la raison de l’écart avec l’analyse automatique…" />
            </Field>
          </fieldset>
        )}

        <footer className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <BoutonY2K variant="secondary" onClick={onCancel} disabled={loading}>Annuler</BoutonY2K>
          <BoutonY2K onClick={submit} disabled={!canSubmit || loading} loading={loading} iconeGauche={<ShieldCheck className="h-4 w-4" />}>
            Valider après contrôles
          </BoutonY2K>
        </footer>
      </DialogContent>
    </Dialog>
  );
}

type Values = {
  dateNaissance: string; dateEmission: string; dateExpiration: string;
  professionCertifiee: string; diplomeEtranger: boolean; typeIdentifiant: string;
  numeroProfessionnel: string; iban: string; formation: string; anneeValidee: string;
  specialiteLicence: string; employeur: string; periodeDebut: string;
  periodeFin: string; heures: string;
};

type Setters = {
  setDateNaissance: (value: string) => void; setDateEmission: (value: string) => void;
  setDateExpiration: (value: string) => void; setProfessionCertifiee: (value: string) => void;
  setDiplomeEtranger: (value: boolean) => void; setTypeIdentifiant: (value: string) => void;
  setNumeroProfessionnel: (value: string) => void; setIban: (value: string) => void;
  setFormation: (value: string) => void; setAnneeValidee: (value: string) => void;
  setSpecialiteLicence: (value: string) => void; setEmployeur: (value: string) => void;
  setPeriodeDebut: (value: string) => void; setPeriodeFin: (value: string) => void;
  setHeures: (value: string) => void;
};

function SpecificValidationFields({ document, values, setters, loading }: { document: DocumentModerationEntry; values: Values; setters: Setters; loading?: boolean }) {
  const type = document.type_document;
  if (TYPES_IDENTITE.has(type)) return (
    <section className="grid gap-3 sm:grid-cols-2" aria-label="Contrôles de la pièce d'identité">
      <Field label="Date de naissance lue *"><Input type="date" value={values.dateNaissance} onChange={(e) => setters.setDateNaissance(e.target.value)} disabled={loading} /></Field>
      <Field label="Date d’expiration lue *"><Input type="date" value={values.dateExpiration} onChange={(e) => setters.setDateExpiration(e.target.value)} disabled={loading} /></Field>
    </section>
  );
  if (TYPES_DIPLOME.has(type)) return (
    <section className="grid gap-3 sm:grid-cols-2" aria-label="Contrôles du diplôme ou de l'autorisation">
      <Field label="Profession certifiée *">
        <select className="input-base min-h-[44px]" value={values.professionCertifiee} onChange={(e) => setters.setProfessionCertifiee(e.target.value)} disabled={loading}>
          <option value="">— Sélectionner la qualification lue —</option>
          {Object.keys(LABELS_PROFESSION).map((code) => <option key={code} value={code}>{LABELS_PROFESSION[code]}</option>)}
        </select>
      </Field>
      {type === 'DIPLOME' && <ReviewCheckbox checked={values.diplomeEtranger} onChange={setters.setDiplomeEtranger} label="Diplôme délivré hors de France (une autorisation d’exercice vérifiée sera exigée)." disabled={loading} />}
    </section>
  );
  if (type === 'RIB') return (
    <section className="space-y-2" aria-label="Contrôle du RIB">
      <Field label="IBAN complet lu sur le RIB * (jamais conservé en clair)">
        <Input value={values.iban} onChange={(e) => setters.setIban(e.target.value.toUpperCase())} autoComplete="off" spellCheck={false} disabled={loading} placeholder="FR76…" />
      </Field>
      <p className="text-xs text-muted-foreground">Le serveur recalcule le checksum ISO 13616, compare l’IBAN de versement déjà enregistré s’il existe, puis ne conserve que les 4 derniers caractères.</p>
    </section>
  );
  if (type === 'RPPS_ADELI') return (
    <section className="grid gap-3 sm:grid-cols-2" aria-label="Contrôle de l'identifiant professionnel">
      <Field label="Registre *">
        <select className="input-base min-h-[44px]" value={values.typeIdentifiant} onChange={(e) => setters.setTypeIdentifiant(e.target.value)} disabled={loading}>
          <option value="">— Sélectionner —</option><option value="RPPS">RPPS</option><option value="ADELI">ADELI</option>
        </select>
      </Field>
      <Field label="Numéro complet lu *"><Input inputMode="numeric" value={values.numeroProfessionnel} onChange={(e) => setters.setNumeroProfessionnel(e.target.value)} disabled={loading} /></Field>
    </section>
  );
  if (type === 'ATTESTATION_SCOLARITE') return (
    <section className="grid gap-3 sm:grid-cols-3" aria-label="Contrôle de la scolarité">
      <Field label="Formation *"><Input value={values.formation} onChange={(e) => setters.setFormation(e.target.value.toUpperCase())} disabled={loading} placeholder="IFSI, IFAS…" /></Field>
      <Field label="Année validée *"><Input type="number" min="0" max="9" value={values.anneeValidee} onChange={(e) => setters.setAnneeValidee(e.target.value)} disabled={loading} /></Field>
      <Field label="Date d’émission *"><Input type="date" value={values.dateEmission} onChange={(e) => setters.setDateEmission(e.target.value)} disabled={loading} /></Field>
    </section>
  );
  if (type === 'LICENCE_REMPLACEMENT') return (
    <section className="grid gap-3 sm:grid-cols-3" aria-label="Contrôle de la licence de remplacement">
      <Field label="Spécialité / DES *"><Input value={values.specialiteLicence} onChange={(e) => setters.setSpecialiteLicence(e.target.value)} disabled={loading} /></Field>
      <Field label="Date d’émission *"><Input type="date" value={values.dateEmission} onChange={(e) => setters.setDateEmission(e.target.value)} disabled={loading} /></Field>
      <Field label="Date d’expiration *"><Input type="date" value={values.dateExpiration} onChange={(e) => setters.setDateExpiration(e.target.value)} disabled={loading} /></Field>
    </section>
  );
  if (TYPES_HEURES.has(type)) return (
    <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4" aria-label="Contrôle de la preuve d'heures">
      <Field label="Employeur *"><Input value={values.employeur} onChange={(e) => setters.setEmployeur(e.target.value)} disabled={loading} /></Field>
      <Field label="Début de période *"><Input type="date" value={values.periodeDebut} onChange={(e) => setters.setPeriodeDebut(e.target.value)} disabled={loading} /></Field>
      <Field label="Fin de période *"><Input type="date" value={values.periodeFin} onChange={(e) => setters.setPeriodeFin(e.target.value)} disabled={loading} /></Field>
      <Field label="Heures prouvées *"><Input type="number" min="0.01" step="0.01" value={values.heures} onChange={(e) => setters.setHeures(e.target.value)} disabled={loading} /></Field>
    </section>
  );
  if (document.exige_expiration) return <Field label="Date d’expiration lue *"><Input type="date" value={values.dateExpiration} onChange={(e) => setters.setDateExpiration(e.target.value)} disabled={loading} /></Field>;
  return (
    <section className="grid gap-3 sm:grid-cols-2" aria-label="Dates du document">
      <Field label="Date d’émission (si présente)"><Input type="date" value={values.dateEmission} onChange={(e) => setters.setDateEmission(e.target.value)} disabled={loading} /></Field>
      <Field label="Date d’expiration (si présente)"><Input type="date" value={values.dateExpiration} onChange={(e) => setters.setDateExpiration(e.target.value)} disabled={loading} /></Field>
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="block space-y-1"><span className="block text-xs font-medium text-foreground">{label}</span>{children}</label>;
}

function ReviewCheckbox({ checked, onChange, label, disabled }: { checked: boolean; onChange: (value: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <label className="flex min-h-[44px] cursor-pointer items-start gap-3 rounded-lg p-2 hover:bg-muted/50">
      <input type="checkbox" className="mt-0.5 h-5 w-5 shrink-0 accent-primary" checked={checked} onChange={(event) => onChange(event.target.checked)} disabled={disabled} />
      <span className="text-sm text-foreground">{label}</span>
    </label>
  );
}
