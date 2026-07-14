import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260714062000_securiser_moderation_documents_soignants.sql'),
  'utf8',
);
const adminPage = readFileSync(
  join(process.cwd(), 'src/pages/admin/AdminModeration.tsx'),
  'utf8',
);
const reviewUi = readFileSync(
  join(process.cwd(), 'src/components/admin/DocumentModerationReview.tsx'),
  'utf8',
);
const adminDetailPage = readFileSync(
  join(process.cwd(), 'src/pages/admin/AdminDetailUtilisateur.tsx'),
  'utf8',
);

describe('RPC de modération documentaire fail-closed', () => {
  it('exige AAL2, RBAC complet et réserve l’ancienne signature à un hard stop', () => {
    expect(migration).toContain("COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'");
    expect(migration).toContain('OR NOT public.est_admin()');
    expect(migration).toMatch(
      /ancienne signature[\s\S]*CREATE OR REPLACE FUNCTION public\.fn_admin_moderer_document\([\s\S]*p_document_id uuid,[\s\S]*p_action text,[\s\S]*p_motif text DEFAULT NULL[\s\S]*Contexte documentaire obligatoire/i,
    );
    expect(migration).toContain('TO authenticated;');
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.fn_admin_moderer_document\([\s\S]*FROM PUBLIC, anon, authenticated, service_role/);
  });

  it('verrouille document et profil puis compare source, versions et statut avant le DML CAS', () => {
    expect(migration).toMatch(/FROM public\.documents_soignants[\s\S]*FOR UPDATE/);
    expect(migration).toMatch(/FROM public\.soignants[\s\S]*FOR UPDATE/);
    expect(migration).toContain('v_doc.modifie_le IS DISTINCT FROM v_expected_doc_modifie');
    expect(migration).toContain('v_soignant.modifie_le IS DISTINCT FROM v_expected_soignant_modifie');
    expect(migration).toContain("v_doc.s3_bucket IS DISTINCT FROM v_validation ->> 'expected_s3_bucket'");
    expect(migration).toContain("v_doc.s3_cle IS DISTINCT FROM v_validation ->> 'expected_s3_cle'");
    expect(migration).toContain("v_doc.s3_version_id IS DISTINCT FROM NULLIF(v_validation ->> 'expected_s3_version_id', '')");
    expect(migration).toMatch(/UPDATE public\.documents_soignants[\s\S]*AND modifie_le = v_expected_doc_modifie[\s\S]*GET DIAGNOSTICS v_row_count = ROW_COUNT/);
    expect(migration).toContain("RAISE EXCEPTION 'Décision concurrente détectée'");
  });

  it('recontrôle identité, DOB, diplôme IADE/IBODE, RPPS/ADELI, IBAN/titulaire et dates', () => {
    expect(migration).toContain('public.fn_noms_personne_correspondent');
    expect(migration).toContain('La date de naissance du document contredit le profil');
    expect(migration).toContain("WHEN 'IDE' THEN v_profession_certifiee IN ('IDE', 'IADE', 'IBODE')");
    expect(migration).toContain("WHEN 'IADE' THEN v_profession_certifiee = 'IADE'");
    expect(migration).toContain("WHEN 'IBODE' THEN v_profession_certifiee = 'IBODE'");
    expect(migration).toContain("v_numero_professionnel !~ '^\\d{11}$'");
    expect(migration).toContain("v_numero_professionnel !~ '^\\d{9}$'");
    expect(migration).toContain('private.fn_iban_valide_moderation(v_iban)');
    expect(migration).toContain('L’IBAN du RIB diffère de l’IBAN de versement enregistré');
    expect(migration).toContain('Un document expiré ne peut pas être validé');
    expect(migration).toContain('La date d’expiration est obligatoire pour ce document');
  });

  it('persiste la saisie manuelle sans IBAN complet et trace source, snapshot et override dans la même transaction', () => {
    expect(migration).toContain("WHEN v_ai_indisponible THEN 'ADMIN_SAISIE_MANUELLE'");
    expect(migration).toContain("WHEN v_override_requis THEN 'ADMIN_OVERRIDE_EXCEPTIONNEL'");
    expect(migration).toContain("- 'iban_extrait'");
    expect(migration).toContain("'iban_last4', v_iban_last4");
    expect(migration).not.toMatch(/'champs_confirmes'[\s\S]{0,1200}'iban',\s*v_iban/);
    expect(migration).toMatch(/UPDATE public\.documents_soignants[\s\S]*INSERT INTO public\.journaux_audit/);
    expect(migration).toContain("'snapshot', v_snapshot");
    expect(migration).toContain("'override_raison', v_raison_override");
    expect(migration).toContain('char_length(v_raison_override) < 30');
    expect(migration).not.toContain('PERFORM public.fn_ecrire_audit_safe');
  });

  it('interdit aussi à un admin de contourner la RPC par update direct', () => {
    const guard = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_proteger_document_verification\(\)[\s\S]*?\$\$;/,
    )?.[0] ?? '';
    expect(guard).toContain("current_setting('jolene.document_moderation_rpc'");
    expect(guard).not.toContain('OR public.est_admin()');
    expect(guard).toContain('NEW.verification_attempt_id IS DISTINCT FROM OLD.verification_attempt_id');
  });
});

describe('interface AdminModeration contextualisée', () => {
  it('charge profil, résultat IA, motif, source Storage et champs de version', () => {
    expect(adminPage).toContain('resultat_ia, nom_extrait_ia, prenom_extrait_ia');
    expect(adminPage).toContain('s3_version_id, type_mime, taille_octets');
    expect(adminPage).toContain('profession, date_naissance, numero_rpps, numero_adeli');
    expect(adminPage).toContain("['EN_ATTENTE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE']");
  });

  it('ne propose plus de validation directe et transmet le contexte à la surcharge sécurisée', () => {
    expect(adminPage).toContain('<DocumentValidationDialog');
    expect(adminPage).toContain('p_validation_manuelle: payload.validation');
    expect(adminPage).toContain('p_raison_override: payload.raisonOverride');
    expect(adminPage).not.toMatch(/onClick=\{\(\) => validerDocument\(d\.id\)\}/);
    expect(reviewUi).toContain('Ouvrir la revue de validation');
    expect(reviewUi).toContain('Confirmations obligatoires');
    expect(reviewUi).toContain('Dérogation exceptionnelle obligatoire');
  });

  it('place aussi les uploads du détail utilisateur en attente et renvoie vers la revue', () => {
    expect(adminDetailPage).toContain('p_valider: false');
    expect(adminDetailPage).toContain("navigate('/admin/moderation?onglet=documents')");
    expect(adminDetailPage).toContain('Revoir dans Modération');
    expect(adminDetailPage).not.toContain("supabase.rpc('fn_admin_moderer_document'");
    expect(adminDetailPage).not.toContain('il sera validé immédiatement');
    expect(adminPage).toContain("searchParams.get('onglet') === 'documents'");
  });
});
