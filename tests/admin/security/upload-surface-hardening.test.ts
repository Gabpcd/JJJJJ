import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');

const uploadSurfaces = [
  'src/components/AvatarUpload.tsx',
  'src/components/BlocContratTravailMission.tsx',
  'src/components/ImportHeuresExternes.tsx',
  'src/components/ModalTeleversement.tsx',
  'src/components/parcours-liberal/FormulaireHeuresExternes.tsx',
  'src/components/score/ModaleReclamationScore.tsx',
  'src/components/soignant/ModaleAnnulationCandidature.tsx',
  'src/hooks/useParcoursLiberal.ts',
  'src/pages/ActiverEtablissement.tsx',
  'src/pages/DetailMission.tsx',
  'src/pages/DocumentsSoignant.tsx',
  'src/pages/FinaliserInscriptionEtab.tsx',
  'src/pages/ProfilEtablissement.tsx',
  'src/pages/VerificationEtablissement.tsx',
  'src/pages/admin/AdminDetailUtilisateur.tsx',
];

describe('surfaces de téléversement — garde-fous préproduction', () => {
  it('centralise taille, MIME, extension et signature binaire', () => {
    const helper = read('src/lib/documentUpload.ts');
    expect(helper).toContain("startsWith([0x25, 0x50, 0x44, 0x46, 0x2d])");
    expect(helper).toContain('detectedMime !== expectedMime');
    expect(helper).toContain("format === 'HEIC_UNSUPPORTED'");
    expect(helper).toContain('file.size > maxBytes');
    expect(helper).toContain(".replace(/[^a-zA-Z0-9_-]+/g, '-')");
  });

  it('valide chaque surface documentaire avant upload et n’écrase aucune preuve', () => {
    for (const path of uploadSurfaces) {
      const source = read(path);
      expect(source, path).not.toContain('accept="image/*"');
      if (source.includes('.upload(')) {
        expect(source, path).toContain('verifierFichierDocument');
        expect(source, path).not.toMatch(/\.upload\([\s\S]{0,500}upsert:\s*true/);
      }
    }
  });

  it('stocke les nouvelles heures externes dans le bucket privé reproductible et conserve le legacy en lecture', () => {
    const hook = read('src/hooks/useParcoursLiberal.ts');
    const edge = read('supabase/functions/verify-heures-externes/index.ts');
    const liste = read('src/components/parcours-liberal/ListeHeuresExternes.tsx');
    const admin = read('src/pages/admin/AdminHeuresExternes.tsx');

    expect(hook).toContain(".from('jolene-documents')");
    expect(hook).toContain('/heures-externes/');
    expect(hook).toContain("action: 'cleanup_orphan'");
    expect(hook).toContain("action: 'delete'");
    expect(edge).toContain('"attestations-heures-externes"');
    expect(edge).toContain('import { corsHeaders } from "../_shared/cors.ts"');
    expect(edge).not.toContain('function getCorsOrigin');
    expect(edge).toContain('bucketSecours');
    expect(edge).toContain('resumed_cleanup');
    expect(edge).toContain('.eq("attestation_url", attestationPath)');
    expect(liste).toContain("? 'jolene-documents'");
    expect(admin).toContain("? 'jolene-documents'");
  });

  it('autorise le soignant assigné à lire son contrat via une URL courte, sans élargir la RLS Storage', () => {
    const component = read('src/components/BlocContratTravailMission.tsx');
    const edge = read('supabase/functions/verify-contrat-travail/index.ts');

    expect(component).toContain('/contrats-travail/${missionId}/');
    expect(component).toContain("action: 'signed_url'");
    expect(component).toContain("action: 'cleanup_orphan'");
    expect(edge).toContain('estSoignantAssigne');
    expect(edge).toContain('createSignedUrl(sourcePath, 300)');
    expect(edge).toContain('validateDocumentFile(bytes, "application/pdf")');
    expect(edge).toContain('.eq("pdf_s3_key", sourcePath)');
  });

  it('nettoie côté service les RIB/contrats non rattachés et refuse une clé encore référencée', () => {
    const rib = read('supabase/functions/verify-rib-etablissement/index.ts');
    const contrat = read('supabase/functions/verify-contrat-etablissement/index.ts');
    const profil = read('src/pages/ProfilEtablissement.tsx');

    expect(rib).toContain('body?.action === "cleanup_orphan"');
    expect(rib).toContain('.eq("rib_s3_key", sourcePath)');
    expect(rib).toContain('Ce RIB est encore référencé');
    expect(contrat).toContain('body?.action === "cleanup_orphan"');
    expect(contrat).toContain('.eq("contrat_url", sourcePath)');
    expect(contrat).toContain('Ce contrat est encore référencé');
    expect(profil).not.toContain("supabase.storage.from('jolene-documents').remove([path])");
  });

  it('nettoie les documents non rattachés via le service, jamais via une politique DELETE client', () => {
    const edge = read('supabase/functions/verify-document/index.ts');
    const soignant = read('src/pages/DocumentsSoignant.tsx');
    const admin = read('src/pages/admin/AdminDetailUtilisateur.tsx');

    expect(edge).toContain('body?.action === "cleanup_orphan"');
    expect(edge).toContain('auth.userId === ownerId');
    expect(edge).toContain('verifyAdminOrServiceRole(req)');
    expect(edge).toContain('segments.length === 4');
    expect(edge).toContain('segments[1] === "documents"');
    expect(edge).toContain('.eq("s3_cle", sourcePath)');
    expect(edge).toContain('Ce document est encore référencé');
    for (const source of [soignant, admin]) {
      expect(source).toContain("action: 'cleanup_orphan'");
      expect(source).not.toMatch(/storage\.from\('jolene-documents'\)\.remove/);
    }
  });

  it('exige les concordances serveur et un snapshot de source avant verdict automatique', () => {
    const hours = read('supabase/functions/verify-heures-externes/index.ts');
    const contract = read('supabase/functions/verify-contrat-travail/index.ts');

    for (const source of [hours, contract]) {
      expect(source).toContain('personNameMatches');
      expect(source).toContain('corporateNameMatches');
      expect(source).toContain('strictAiVerificationQuality');
      expect(source).toContain('document_complet === true');
    }
    expect(hours).toContain('periodeCorrespond === true');
    expect(hours).toContain('etablissementCorrespond === true');
    expect(contract).toContain('salarieMatch === true');
    expect(contract).toContain('employeurMatch === true');
  });
});
