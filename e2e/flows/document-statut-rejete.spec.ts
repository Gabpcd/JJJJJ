/**
 * Test E2E — statut REJETE persiste (ne bascule pas en "Expiré").
 *
 * Bug Sprint Hotfix UX Documents Bug 2 : un doc REJETE dont l'IA avait
 * extrait une date_expiration passée (du mauvais fichier) s'affichait
 * "Expiré". Fix : verify-document n'écrit plus valide_jusqua sur REJETE.
 *
 * Ce test valide l'invariant côté données : aucun document REJETE ne doit
 * porter de valide_jusqua. Plus un test bout-en-bout via verify-document
 * (skip graceful si Anthropic indisponible).
 */

import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;
const VERIFY_TIMEOUT_MS = 30_000;
// Les tests qui appellent l'API Anthropic sont skippés en CI (pas de crédits Anthropic).
const HAS_ANTHROPIC = !!process.env.ANTHROPIC_API_KEY && !process.env.CI;

function makeMinimalPdf(): Uint8Array {
  const content = `%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R>>endobj
4 0 obj<</Length 44>>stream
BT /F1 24 Tf 100 700 Td (TEST DOCUMENT) Tj ET
endstream
endobj
trailer<</Size 5/Root 1 0 R>>
%%EOF`;
  return new TextEncoder().encode(content);
}

test.describe('Statut REJETE — ne bascule pas en Expiré', () => {
  let soignantId: string;

  test.beforeAll(async () => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
    const id = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    test.skip(!id, 'Compte playwright-soignant non seedé');
    soignantId = id!;
  });

  test.afterAll(async () => {
    if (TEST_REQS) {
      const admin = adminClient();
      const { data } = await admin
        .from('documents_soignants' as any)
        .select('id, s3_cle, s3_bucket')
        .eq('libelle', '[playwright-test] statut-rejete');
      for (const doc of (data as any[]) || []) {
        await admin.storage.from(doc.s3_bucket).remove([doc.s3_cle]).catch(() => {});
      }
      await admin.from('documents_soignants' as any).delete()
        .eq('libelle', '[playwright-test] statut-rejete');
    }
  });

  test('Invariant données : aucun document REJETE ne porte de valide_jusqua', async () => {
    const { data, error } = await adminClient()
      .from('documents_soignants' as any)
      .select('id')
      .eq('statut_verification', 'REJETE')
      .not('valide_jusqua', 'is', null);
    expect(error).toBeFalsy();
    expect((data as any[]) || []).toHaveLength(0);
  });

  test('verify-document REJETE (cross-type PDF) → valide_jusqua reste NULL', async () => {
    test.skip(!HAS_ANTHROPIC, 'ANTHROPIC_API_KEY absent ou CI=true — test IA désactivé');
    const admin = adminClient();
    const pdfBytes = makeMinimalPdf();
    const path = `${soignantId}/documents/TEST/${Date.now()}-rejete.pdf`;
    const blob = new Blob([pdfBytes], { type: 'application/pdf' });
    const up = await admin.storage.from('jolene-documents').upload(path, blob, { contentType: 'application/pdf' });
    expect(up.error).toBeFalsy();

    const { data: docRow } = await admin
      .from('documents_soignants' as any)
      .insert({
        soignant_id: soignantId,
        type_document: 'DIPLOME',
        s3_bucket: 'jolene-documents',
        s3_cle: path,
        nom_fichier: 'rejete.pdf',
        type_mime: 'application/pdf',
        taille_octets: pdfBytes.length,
        statut_verification: 'EN_ATTENTE',
        libelle: '[playwright-test] statut-rejete',
      })
      .select('id')
      .single();
    const docId = (docRow as { id: string }).id;

    await (admin as any).functions.invoke('verify-document', { body: { document_id: docId } }).catch(() => {});

    let result: any = null;
    const start = Date.now();
    while (Date.now() - start < VERIFY_TIMEOUT_MS) {
      const { data } = await admin
        .from('documents_soignants' as any)
        .select('statut_verification, valide_jusqua, resultat_ia')
        .eq('id', docId)
        .single();
      if ((data as any)?.resultat_ia) { result = data; break; }
      await new Promise((r) => setTimeout(r, 2000));
    }

    if (result?.resultat_ia?.erreur_anthropic) {
      test.skip(true, `Anthropic indisponible : ${result.resultat_ia.erreur_anthropic.status}`);
      return;
    }

    expect(result, 'verify-document n\'a pas répondu en 30s').not.toBeNull();
    expect(result.statut_verification).toBe('REJETE');
    // Le fix : pas de valide_jusqua écrit sur un REJETE
    expect(result.valide_jusqua).toBeNull();
  });
});
