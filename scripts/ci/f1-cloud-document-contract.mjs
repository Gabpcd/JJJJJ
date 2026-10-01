import { ORIGIN, refuse } from './f1-cloud-core.mjs';

const CARD = 'id,numero_facture,statut,montant_ht,montant_ttc,montant_signe,taux_tva,exoneration_tva,date_emission,date_echeance,date_paiement,date_remboursement,type_document,template_version,cree_le,periode_debut,periode_fin,numero_semaine_iso,annee_iso,est_facture_finale_mission';
const ORDER = 'date_emission.desc,cree_le.desc,id.desc';
const PREFIX = '/storage/v1/object/sign/jolene-documents/';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const exactKeys = (object, expected) => object && typeof object === 'object' && !Array.isArray(object)
  && JSON.stringify(Object.keys(object).sort()) === JSON.stringify([...expected].sort());
function trustedUrl(input) {
  try {
    const url = new URL(input);
    return url.origin === ORIGIN && !url.username && !url.password && !url.hash ? url : null;
  } catch { return null; }
}
function params(url, expected) {
  const entries = [...url.searchParams];
  return entries.length === new Set(entries.map(([key]) => key)).size
    && exactKeys(Object.fromEntries(entries), expected);
}

/** A per-context document subset: it cannot authorize dashboard/Auth traffic.
 * Signed URLs are bound to the exact successful signing response, in memory only.
 * No URL, key, ID, number or token escapes through the public projection. */
export function documentContractF1({ missionId, soignantId, documents }) {
  if (!UUID.test(missionId ?? '') || !UUID.test(soignantId ?? '') || documents?.length !== 2
    || new Set(documents.map(d => d.id)).size !== 2) refuse('F1_DOCUMENT_CONTRACT_INVALID');
  const known = new Map(), signed = new Map();
  for (const document of documents) {
    if (!UUID.test(document.id ?? '') || !['original', 'replacement'].includes(document.slot)) refuse('F1_DOCUMENT_CONTRACT_INVALID');
    const parts = document.pdf?.key?.split('/') ?? [];
    if (parts.length !== 4 || parts[0] !== 'invoices' || parts[1] !== soignantId
      || parts[2] !== document.number || !parts[2] || parts[2] === '.' || parts[2] === '..'
      || !UUID.test(parts[3].replace(/\.pdf$/, '')) || !parts[3].endsWith('.pdf')
      || known.has(document.pdf.key)) refuse('F1_DOCUMENT_CONTRACT_INVALID');
    known.set(document.pdf.key, document);
  }
  if (new Set(documents.map(d => d.slot)).size !== 2) refuse('F1_DOCUMENT_CONTRACT_INVALID');
  const counts = { list: 0, metadata_original: 0, metadata_replacement: 0,
    sign_original: 0, sign_replacement: 0, download_original: 0, download_replacement: 0 };
  const responses = { original: 0, replacement: 0 };
  function classify({ url: input, method, body = null }) {
    const url = trustedUrl(input);
    if (!url) return null;
    if (url.pathname === '/rest/v1/factures_honoraires' && method === 'GET' && body === null) {
      if (params(url, ['select', 'mission_id', 'order']) && url.searchParams.get('select') === CARD
        && url.searchParams.get('mission_id') === `eq.${missionId}` && url.searchParams.get('order') === ORDER) return 'list';
      const document = documents.find(d => url.searchParams.get('id') === `eq.${d.id}`);
      if (document && params(url, ['select', 'id'])
        && url.searchParams.get('select') === 'numero_facture,pdf_s3_key') return `metadata_${document.slot}`;
    }
    if (!url.pathname.startsWith(PREFIX)) return null;
    let key;
    try { key = decodeURIComponent(url.pathname.slice(PREFIX.length)); } catch { return null; }
    const document = known.get(key);
    if (!document) return null;
    if (method === 'POST' && !url.search && exactKeys(body, ['expiresIn']) && body.expiresIn === 300) return `sign_${document.slot}`;
    if (method === 'GET' && body === null && signed.get(url.href) === document.slot) return `download_${document.slot}`;
    return null;
  }
  return {
    authorize(request) {
      const category = classify(request);
      if (!category || counts[category] >= 2) return false;
      counts[category]++; return true;
    },
    registerSignedPdf(key, absoluteUrl) {
      const document = known.get(key), url = trustedUrl(absoluteUrl);
      if (!document || !url || !url.pathname.startsWith(PREFIX) || !params(url, ['token'])
        || !url.searchParams.get('token') || responses[document.slot] >= counts[`sign_${document.slot}`]) refuse('F1_SIGNED_URL_REFUSED');
      let returnedKey;
      try { returnedKey = decodeURIComponent(url.pathname.slice(PREFIX.length)); } catch { refuse('F1_SIGNED_URL_REFUSED'); }
      if (returnedKey !== key) refuse('F1_SIGNED_URL_REFUSED');
      responses[document.slot]++;
      signed.set(url.href, document.slot);
    },
    projection() { return { ...counts }; },
    complete() { return Object.values(counts).every(count => count === 2)
      && responses.original === 2 && responses.replacement === 2; },
  };
}
