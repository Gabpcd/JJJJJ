/**
 * Tests E2E vérification documents — garde-fou anti-régression.
 *
 * Valide le pipeline bout-en-bout :
 *   upload Storage → row documents_soignants → verify-document edge function
 *   → appel API Anthropic → écriture statut + verdict en DB
 *
 * Skip graceful si Anthropic indisponible ou crédits épuisés.
 */

import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;
// Les tests qui appellent l'API Anthropic sont skippés en CI (pas de crédits Anthropic).
// Forcer le skip via ANTHROPIC_API_KEY absent ou variable CI explicite.
const HAS_ANTHROPIC = !!process.env.ANTHROPIC_API_KEY && !process.env.CI;
const VERIFY_TIMEOUT_MS = 30_000;

function makeMinimalPdf(): Uint8Array {
  const content = `%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>>>>>>>endobj
4 0 obj<</Length 44>>stream
BT /F1 24 Tf 100 700 Td (TEST DOCUMENT) Tj ET
endstream
endobj
xref
0 5
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000310 00000 n
trailer<</Size 5/Root 1 0 R>>
startxref
404
%%EOF`;
  return new TextEncoder().encode(content);
}

function makeMinimalJpeg(): Uint8Array {
  const hex = 'ffd8ffe000104a46494600010100000100010000ffdb00430008060607060508070707090908' +
    '0a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38' +
    '323c2e333432ffc0000b080001000101011100ffc4001f00000105010101010100000000000000000102030405060' +
    '708090a0bffc40000010100000000000000000000000000000000ffda00080101000003f100a0780000001ffd9';
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

async function uploadTestFile(
  soignantId: string, fileName: string, mimeType: string, fileBytes: Uint8Array,
): Promise<string> {
  const path = `${soignantId}/documents/TEST/${Date.now()}-${fileName}`;
  const blob = new Blob([fileBytes], { type: mimeType });
  const { error } = await adminClient().storage
    .from('jolene-documents')
    .upload(path, blob, { contentType: mimeType, upsert: false });
  if (error) throw new Error(`Storage upload failed: ${error.message}`);
  return path;
}

async function createDocRow(
  soignantId: string, typeDocument: string, s3Cle: string,
  fileName: string, mimeType: string, fileSize: number,
): Promise<string> {
  const { data, error } = await adminClient()
    .from('documents_soignants' as any)
    .insert({
      soignant_id: soignantId,
      type_document: typeDocument,
      s3_bucket: 'jolene-documents',
      s3_cle: s3Cle,
      nom_fichier: fileName,
      type_mime: mimeType,
      taille_octets: fileSize,
      statut_verification: 'EN_ATTENTE',
      libelle: '[playwright-test] verify-document',
    })
    .select('id')
    .single();
  if (error) throw new Error(`Insert doc failed: ${error.message}`);
  return (data as { id: string }).id;
}

async function triggerVerify(docId: string): Promise<void> {
  const admin = adminClient();
  const { error } = await (admin as any).functions.invoke('verify-document', {
    body: { document_id: docId },
  });
  if (error) {
    console.warn(`[verify-document] invoke fallback:`, error.message);
  }
}

async function waitForVerdict(docId: string, timeoutMs: number): Promise<any> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const { data } = await adminClient()
      .from('documents_soignants' as any)
      .select('statut_verification, resultat_ia, score_confiance_ia, motif_rejet')
      .eq('id', docId)
      .single();
    const row = data as any;
    if (row?.resultat_ia) return row;
    await new Promise((r) => setTimeout(r, 2000));
  }
  return null;
}

async function cleanupTestDocs(): Promise<void> {
  const admin = adminClient();
  const { data } = await admin
    .from('documents_soignants' as any)
    .select('id, s3_cle, s3_bucket')
    .eq('libelle', '[playwright-test] verify-document');
  if (data && Array.isArray(data)) {
    for (const doc of data as any[]) {
      await admin.storage.from(doc.s3_bucket).remove([doc.s3_cle]).catch(() => {});
    }
    await admin.from('documents_soignants' as any).delete()
      .eq('libelle', '[playwright-test] verify-document');
  }
}

test.describe('Vérification documents — pipeline bout-en-bout', () => {
  let soignantId: string;

  test.beforeAll(async () => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
    const id = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    test.skip(!id, 'Compte playwright-soignant non seedé');
    soignantId = id!;
  });

  test.afterAll(async () => {
    if (TEST_REQS) await cleanupTestDocs().catch(() => {});
  });

  test('Upload PDF déclaré CARTE_IDENTITE → IA retourne un verdict', async () => {
    test.skip(!HAS_ANTHROPIC, 'ANTHROPIC_API_KEY absent ou CI=true — test IA désactivé');
    const pdfBytes = makeMinimalPdf();
    const s3Path = await uploadTestFile(soignantId, 'test-doc.pdf', 'application/pdf', pdfBytes);
    const docId = await createDocRow(soignantId, 'CARTE_IDENTITE', s3Path, 'test-doc.pdf', 'application/pdf', pdfBytes.length);

    await triggerVerify(docId);
    const result = await waitForVerdict(docId, VERIFY_TIMEOUT_MS);

    if (result?.resultat_ia?.erreur_anthropic) {
      test.skip(true, `Anthropic indisponible : ${result.resultat_ia.erreur_anthropic.status}`);
      return;
    }

    expect(result, 'verify-document n\'a pas écrit de resultat_ia dans les 30s').not.toBeNull();
    expect(result.resultat_ia.verdict).toBeDefined();
    expect(['VERIFIE', 'EN_ATTENTE', 'REJETE']).toContain(result.resultat_ia.verdict);
  });

  test('Upload PDF déclaré DIPLOME (cross-type) → IA rejette', async () => {
    test.skip(!HAS_ANTHROPIC, 'ANTHROPIC_API_KEY absent ou CI=true — test IA désactivé');
    const pdfBytes = makeMinimalPdf();
    const s3Path = await uploadTestFile(soignantId, 'test-crosstype.pdf', 'application/pdf', pdfBytes);
    const docId = await createDocRow(soignantId, 'DIPLOME', s3Path, 'test-crosstype.pdf', 'application/pdf', pdfBytes.length);

    await triggerVerify(docId);
    const result = await waitForVerdict(docId, VERIFY_TIMEOUT_MS);

    if (result?.resultat_ia?.erreur_anthropic) {
      test.skip(true, `Anthropic indisponible : ${result.resultat_ia.erreur_anthropic.status}`);
      return;
    }

    expect(result).not.toBeNull();
    expect(result.resultat_ia.verdict).toBe('REJETE');
    expect(result.resultat_ia.type_correspond).toBe(false);
  });

  test('Upload JPEG déclaré CARTE_IDENTITE → IA retourne un verdict (non-régression images)', async () => {
    test.skip(!HAS_ANTHROPIC, 'ANTHROPIC_API_KEY absent ou CI=true — test IA désactivé');
    const jpegBytes = makeMinimalJpeg();
    const s3Path = await uploadTestFile(soignantId, 'test-img.jpg', 'image/jpeg', jpegBytes);
    const docId = await createDocRow(soignantId, 'CARTE_IDENTITE', s3Path, 'test-img.jpg', 'image/jpeg', jpegBytes.length);

    await triggerVerify(docId);
    const result = await waitForVerdict(docId, VERIFY_TIMEOUT_MS);

    if (result?.resultat_ia?.erreur_anthropic) {
      test.skip(true, `Anthropic indisponible : ${result.resultat_ia.erreur_anthropic.status}`);
      return;
    }

    expect(result, 'verify-document n\'a pas écrit de resultat_ia pour JPEG').not.toBeNull();
    expect(result.resultat_ia.verdict).toBeDefined();
  });

  test('Type MIME non supporté (application/zip) → REJETE sans appel IA', async () => {
    const fakeZip = new TextEncoder().encode('PK\x03\x04fake-zip-content');
    // Le bucket refuse déjà application/zip. On charge donc les octets sous un
    // MIME Storage autorisé, puis on conserve application/zip dans la ligne
    // métier : cela prouve le second verrou de verify-document sans assouplir
    // le premier verrou Storage.
    const s3Path = await uploadTestFile(soignantId, 'test.zip', 'application/pdf', fakeZip);
    const docId = await createDocRow(soignantId, 'CARTE_IDENTITE', s3Path, 'test.zip', 'application/zip', fakeZip.length);

    await triggerVerify(docId);
    await new Promise((r) => setTimeout(r, 5000));

    const { data } = await adminClient()
      .from('documents_soignants' as any)
      .select('statut_verification, motif_rejet')
      .eq('id', docId)
      .single();

    expect((data as any).statut_verification).toBe('REJETE');
    expect((data as any).motif_rejet).toContain('application/zip');
  });
});
