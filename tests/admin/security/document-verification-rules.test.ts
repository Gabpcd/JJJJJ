import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  corporateNameMatches,
  diplomaMatchesDeclaredProfession,
  ibanLast4,
  isValidIban,
  personNameMatches,
  professionalIdentifierMatches,
  sanitizeBankAnalysis,
} from '../../../supabase/functions/_shared/verification-rules';

const verifyDocumentSource = readFileSync(
  join(process.cwd(), 'supabase/functions/verify-document/index.ts'),
  'utf8',
);
const identityMigration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713223000_durcir_identite_soignant_documents.sql'),
  'utf8',
);
const historicalBackfill = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713224000_revalider_preuves_historiques_reelles.sql'),
  'utf8',
);

describe('garde-fous déterministes de vérification documentaire', () => {
  it('relie le document à l’identité déclarée en tolérant accents et prénoms composés', () => {
    expect(personNameMatches('Lefèvre', 'Marie-Claire', 'LEFEVRE', 'Marie Claire')).toBe(true);
    expect(personNameMatches('Lefèvre', 'Marie', 'Martin', 'Marie')).toBe(false);
    expect(personNameMatches('Lefèvre', 'Marie', 'Lefèvre', 'Marion')).toBe(false);
    expect(personNameMatches('Lefèvre', 'Marie', null, null)).toBeNull();
  });

  it('applique une compatibilité diplôme → profession asymétrique', () => {
    expect(diplomaMatchesDeclaredProfession('IDE', 'IADE')).toBe(true);
    expect(diplomaMatchesDeclaredProfession('IADE', 'IDE')).toBe(false);
    expect(diplomaMatchesDeclaredProfession('IBODE', 'IDE')).toBe(false);
    expect(diplomaMatchesDeclaredProfession('MEDECIN', 'DENTISTE')).toBe(false);
    expect(diplomaMatchesDeclaredProfession('AS', 'AS')).toBe(true);
  });

  it('exige l’égalité exacte du RPPS/ADELI après normalisation', () => {
    expect(professionalIdentifierMatches('10101234567', '10 101 234 567')).toBe(true);
    expect(professionalIdentifierMatches('10101234567', '10101234568')).toBe(false);
    expect(professionalIdentifierMatches('10101234567', null)).toBeNull();
  });

  it('valide le checksum IBAN et ne conserve que les quatre derniers caractères', () => {
    const iban = 'FR76 3000 6000 0112 3456 7890 189';
    expect(isValidIban(iban)).toBe(true);
    expect(isValidIban('FR76 3000 6000 0112 3456 7890 188')).toBe(false);
    expect(ibanLast4(iban)).toBe('0189');

    const sanitized = sanitizeBankAnalysis({ iban_extrait: iban, titulaire_extrait: 'Jolene Santé' });
    expect(sanitized).not.toHaveProperty('iban_extrait');
    expect(sanitized.iban_last4).toBe('0189');
    expect(sanitized.iban_valide).toBe(true);
  });

  it('ne persiste aucune coordonnée bancaire cachée dans des champs IA inventés', () => {
    const iban = 'FR76 3000 6000 0112 3456 7890 189';
    const sanitized = sanitizeBankAnalysis({
      iban_extrait: iban,
      raw_text: `Compte ${iban}`,
      iban_detected: iban,
      nested: { account: iban },
      motif: `IBAN observé : ${iban}`,
      indices_falsification: [`Texte retouché près de ${iban}`],
      titulaire_extrait: 'Jolene Santé',
    });

    expect(sanitized).not.toHaveProperty('raw_text');
    expect(sanitized).not.toHaveProperty('iban_detected');
    expect(sanitized).not.toHaveProperty('nested');
    expect(JSON.stringify(sanitized)).not.toContain('FR76');
    expect(JSON.stringify(sanitized)).not.toContain('3000');
    expect(sanitized.iban_last4).toBe('0189');
  });

  it('compare les raisons sociales sans dépendre de la forme juridique', () => {
    expect(corporateNameMatches('JOLENE SERVICES SANTE SAS', 'SAS Jolene Services Santé')).toBe(true);
    expect(corporateNameMatches('Clinique des Lilas', 'Hôpital Saint-Louis')).toBe(false);
    expect(corporateNameMatches('Centre Santé Paris', 'Paris')).toBeNull();
    expect(corporateNameMatches('Cabinet médical Jean Dupont', 'Jean Dupont')).toBe(true);
    expect(corporateNameMatches('', 'Jolene Santé')).toBeNull();
  });
});

describe('gate des documents à expiration', () => {
  const migration = readFileSync(
    join(process.cwd(), 'supabase/migrations/20260713222000_durcir_verifications_preproduction.sql'),
    'utf8',
  );

  it('refuse une date absente, passée ou égale à aujourd’hui', () => {
    expect(migration).toMatch(
      /a_expiration IS FALSE\s+OR \(ds\.valide_jusqua IS NOT NULL AND ds\.valide_jusqua > current_date\)/i,
    );
    expect(migration).not.toMatch(/ds\.valide_jusqua IS NULL OR ds\.valide_jusqua > current_date/i);
  });

  it('cherche un renouvellement couvrant la mission au lieu de bloquer sur une ancienne preuve', () => {
    expect(migration).toMatch(/CREATE OR REPLACE FUNCTION public\.dec_verifier_docs_jusqua_fin\(\)/i);
    expect(migration).toMatch(/NOT EXISTS \([\s\S]*ds\.valide_jusqua >= NEW\.fin_le::date/i);
    expect(migration).not.toMatch(/ds\.valide_jusqua < NEW\.fin_le::date[\s\S]*LIMIT 1/i);
  });
});

describe('gate FINESS', () => {
  const source = readFileSync(
    join(process.cwd(), 'supabase/functions/verify-finess/index.ts'),
    'utf8',
  );

  it('n’auto-valide que sur le SIRET exact publié par l’Annuaire Santé', () => {
    expect(source).toMatch(/const coherent = lienSiretFort;/);
    expect(source).toMatch(/const mode = lienSiretFort \? 'SIRET_EXACT' : null;/);
    expect(source).not.toMatch(/const coherent =[^;]*lienNomAdresse/);
  });
});

describe('fail-closed de verify-document', () => {
  it('exige une confiance HAUTE, un score borné et une analyse de falsification explicite', () => {
    expect(verifyDocumentSource).toMatch(
      /const confianceHaute = confianceIa === "HAUTE"\s*&& scoreConfianceIa !== null\s*&& scoreConfianceIa >= 85/,
    );
    expect(verifyDocumentSource).toContain('analysis.score_confiance <= 100');
    expect(verifyDocumentSource).toContain('!falsificationRenseignee');
    expect(verifyDocumentSource).not.toMatch(/confiance === "HAUTE"\s*\|\|/);
  });

  it('relie une attestation professionnelle au bon registre et à son format', () => {
    expect(verifyDocumentSource).toContain('rpps_verifie, adeli_verifie');
    expect(verifyDocumentSource).toContain('analysis.type_identifiant_professionnel');
    expect(verifyDocumentSource).toContain('soignant?.rpps_verifie === true');
    expect(verifyDocumentSource).toContain('soignant?.adeli_verifie === true');
    expect(verifyDocumentSource).toContain('/^\\d{11}$/.test(expectedDigits)');
    expect(verifyDocumentSource).toContain('/^\\d{9}$/.test(expectedDigits)');
  });

  it('injecte l’exigence documentaire exacte et relie aussi l’autorisation à la profession', () => {
    expect(verifyDocumentSource).toContain('.select("a_expiration, description")');
    expect(verifyDocumentSource).toContain('Exigence documentaire exacte:');
    expect(verifyDocumentSource).toContain('doc.type_document === "DIPLOME" || doc.type_document === "AUTORISATION_EXERCICE"');
    expect(verifyDocumentSource).toContain('type === "AUTORISATION_EXERCICE" && !analysis.profession_certifiee');
  });

  it('refuse les dates ambiguës, futures, incohérentes ou déjà expirées', () => {
    expect(verifyDocumentSource).toContain('dateEmissionFournie && dateEmission === null');
    expect(verifyDocumentSource).toContain('dateEmission > aujourdHuiIso');
    expect(verifyDocumentSource).toContain('dateExpiration < dateEmission');
    expect(verifyDocumentSource).toContain('dateExpiration <= aujourdHuiIso');
    expect(verifyDocumentSource).toContain('dateNaissanceExtraite >= aujourdHuiIso');
  });

  it('borne la scolarité et n’élève pas automatiquement la profession', () => {
    expect(verifyDocumentSource).toContain('SCOLARITE_MAX_ANNEE_VALIDEE');
    expect(verifyDocumentSource).toContain('analysis.scolarite_annee_validee <= anneeMax');
    expect(verifyDocumentSource).toContain('Date.now() - emissionScolariteMs <= 400 * 24 * 60 * 60 * 1000');
    expect(verifyDocumentSource).toContain('scolarite_profession_autorisee: soignant.profession');
    expect(verifyDocumentSource).not.toContain('priorite.find((profession)');
  });

  it('limite une licence médicale au profil médecin et à une spécialité extraite', () => {
    expect(verifyDocumentSource).toContain('soignant.profession !== "MEDECIN"');
    expect(verifyDocumentSource).toContain('else if (!specialiteLicence)');
  });

  it('ignore les comptes et documents supprimés', () => {
    expect(verifyDocumentSource.match(/\.is\("supprime_le", null\)/g)?.length).toBeGreaterThanOrEqual(2);
  });

  it('invalide un ancien verdict avant toute réanalyse', () => {
    const invalidationIndex = verifyDocumentSource.indexOf('await beginDocumentVerification(supabase, doc, verificationAttemptId)');
    const downloadIndex = verifyDocumentSource.indexOf('.download(doc.s3_cle)');
    const aiIndex = verifyDocumentSource.indexOf('ai = await appelerAnthropic({');

    expect(invalidationIndex).toBeGreaterThan(0);
    expect(downloadIndex).toBeGreaterThan(invalidationIndex);
    expect(aiIndex).toBeGreaterThan(downloadIndex);
    expect(verifyDocumentSource).toContain('verification_attempt_id: attemptId');
    expect(verifyDocumentSource).toContain('.eq("verification_attempt_id", attemptId)');
  });

  it('laisse le trigger DB recalculer seul les droits dérivés pendant une réanalyse', () => {
    expect(verifyDocumentSource).not.toContain('clearDerivedVerificationForReanalysis');
    expect(verifyDocumentSource).not.toContain('saveSoignantFields');
    expect(verifyDocumentSource).not.toMatch(/\.from\("soignants"\)\s*\.update\(/);
    expect(identityMigration).toMatch(
      /AFTER UPDATE OF[\s\S]*statut_verification[\s\S]*ON public\.documents_soignants[\s\S]*fn_trg_recalculer_preuves_etudiant_document/i,
    );
  });

  it('expose un probe Anthropic admin réel sans corps fournisseur', () => {
    const probeStart = verifyDocumentSource.indexOf('if (body?.probe === true)');
    const warmStart = verifyDocumentSource.indexOf('return new Response(JSON.stringify({\n        warm: true', probeStart);
    const probeBlock = verifyDocumentSource.slice(probeStart, warmStart);

    expect(probeStart).toBeGreaterThan(0);
    expect(warmStart).toBeGreaterThan(probeStart);
    expect(probeBlock).toContain('await appelerAnthropic({');
    expect(probeBlock).toContain('maxTokens: 1');
    expect(probeBlock).toContain('verify-document-probe');
    expect(probeBlock).toContain('reachable: probe.ok');
    expect(probeBlock).toContain('model: probe.model || null');
    expect(probeBlock).toContain('status: probe.status');
    expect(probeBlock).not.toContain('probe.body');
  });
});

describe('droits dérivés scolarité et licence', () => {
  it('recalcule les droits à chaque mutation pertinente de la preuve', () => {
    expect(identityMigration).toContain('CREATE OR REPLACE FUNCTION public.fn_recalculer_preuves_etudiant');
    expect(identityMigration).toContain('AFTER INSERT OR DELETE ON public.documents_soignants');
    expect(identityMigration).toMatch(
      /AFTER UPDATE OF[\s\S]*statut_verification,[\s\S]*supprime_le,[\s\S]*valide_depuis,[\s\S]*valide_jusqua,[\s\S]*resultat_ia,[\s\S]*coherence_nom[\s\S]*ON public\.documents_soignants/,
    );
    expect(identityMigration).toContain('AFTER UPDATE OF profession ON public.soignants');
  });

  it('n’accepte que des preuves actuelles, cohérentes et issues du verdict serveur', () => {
    expect(identityMigration).toContain("ds.type_document = 'ATTESTATION_SCOLARITE'");
    expect(identityMigration).toContain("ds.valide_depuis BETWEEN current_date - 400 AND current_date");
    expect(identityMigration).toContain("COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'");
    expect(identityMigration).toContain('FROM public.fn_professions_autorisees_scolarite(');
    expect(identityMigration).toContain("v_profession = 'MEDECIN'");
    expect(identityMigration).toContain("ds.type_document = 'LICENCE_REMPLACEMENT'");
    expect(identityMigration).toContain("ds.valide_jusqua > current_date");
    expect(identityMigration).toContain("ds.valide_jusqua <= (ds.valide_depuis + interval '13 months')::date");
  });

  it('empêche le profil authentifié de forger directement les champs dérivés', () => {
    const protection = identityMigration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_protect_soignant_verification\(\)[\s\S]*?\$\$;/i,
    )?.[0] || '';
    expect(protection.match(/NEW\.scolarite_verifiee := OLD\.scolarite_verifiee/g)?.length).toBe(2);
    expect(protection.match(/NEW\.licence_remplacement_verifiee := OLD\.licence_remplacement_verifiee/g)?.length).toBe(2);
  });

  it('recalcule le backfill réel sans toucher aux comptes test', () => {
    expect(historicalBackfill).toContain('PERFORM public.fn_recalculer_preuves_etudiant(v_soignant_id)');
    expect(historicalBackfill).toContain('WHERE s.est_compte_test IS FALSE');
  });
});

describe('preuve de diplôme active', () => {
  it('ne réutilise jamais le booléen historique sans document encore vérifié', () => {
    const gate = identityMigration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_documents_ok_pour_mission[\s\S]*?\$\$;/i,
    )?.[0] || '';
    expect(gate).not.toContain('diplome_verifie');
    expect(gate).not.toContain('v_diplome_officiel');
    expect(gate).toMatch(
      /drp\.type_document = 'DIPLOME'[\s\S]*ds\.type_document = 'DIPLOME'[\s\S]*ds\.statut_verification = 'VERIFIE'/i,
    );
  });
});
