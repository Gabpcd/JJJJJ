import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  from: vi.fn(), download: vi.fn(), error: vi.fn(), success: vi.fn(), table: vi.fn(), text: vi.fn(),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));
vi.mock('./telechargement', () => ({ telechargerOuPartagerPdf: mocks.download }));
vi.mock('sonner', () => ({ toast: { error: mocks.error, success: mocks.success } }));
vi.mock('jspdf', () => ({ default: class {
  lastAutoTable = { finalY: 120 };
  setTextColor() {} setFont() {} setFontSize() {} setDrawColor() {} setLineWidth() {}
  line() {} rect() {} addPage() {} setFillColor() {}
  text(...args: unknown[]) { mocks.text(...args); }
} }));
vi.mock('jspdf-autotable', () => ({ default: mocks.table }));
vi.mock('./pdf-design-system', () => ({
  JOLENE_COLORS: { textMuted: [1, 2, 3], text: [1, 2, 3], border: [1, 2, 3], primary: [1, 2, 3], primaryDark: [1, 2, 3], roseLight: [1, 2, 3], teal: [1, 2, 3] },
  PAGE: { margin: 15, width: 210, contentWidth: 180 },
  sanitizeForPdf: (s: string) => s, fmtEur: (n: number) => `${n} €`,
  createHeader: vi.fn(), createInfoBlock: () => 75, addInfoRow: vi.fn(),
  createTotalsBlock: () => 200, createFooter: vi.fn(), createHighlightBox: vi.fn(),
  createSectionTitle: (_doc: unknown, y: number) => y + 10,
}));

import { telechargerFactureCommissionPDF } from './facture-commission-pdf';

type Row = Record<string, any>;
const factureId = '00000000-0000-4000-8000-000000000001';
const missionId = '00000000-0000-4000-8000-000000000002';
const etablissementId = '00000000-0000-4000-8000-000000000003';
const soignantId = '00000000-0000-4000-8000-000000000004';
let rows: Record<string, Row[]>;
let failures: Record<string, string>;
let countAvailable: boolean;
let cap: number;
let selections: Array<{ table: string; select: string; count: boolean; offset: number; orders: string[] }>;

function query(table: string) {
  const filters: Array<(row: Row) => boolean> = [];
  let selection = '', count = false, single = false, offset = 0, end = 999;
  const orders: string[] = [];
  const q: any = {
    select(value: string, options?: { count?: string }) { selection = value; count = options?.count === 'exact'; return q; },
    eq(key: string, value: unknown) { filters.push(row => row[key] === value); return q; },
    in(key: string, values: unknown[]) { filters.push(row => values.includes(row[key])); return q; },
    order(key: string) { orders.push(key); return q; },
    range(start: number, last: number) { offset = start; end = last; return q; },
    maybeSingle() { single = true; return q; },
    then(resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) {
      selections.push({ table, select: selection, count, offset, orders: [...orders] });
      // Le serveur de test refuse réellement les anciennes colonnes ; aucune
      // donnée inventée pour faire réussir la requête fautive.
      const invalidColumn = table === 'mission_creneaux' && /\b(debut_le|fin_le|duree_heures)\b/.test(selection);
      const error = failures[table] || (invalidColumn ? 'column mission_creneaux.debut_le does not exist' : null);
      const all = (rows[table] ?? []).filter(row => filters.every(filter => filter(row)));
      all.sort((a, b) => {
        for (const order of orders) { const d = String(a[order]).localeCompare(String(b[order])); if (d) return d; }
        return 0;
      });
      const limited = all.slice(offset, Math.min(end + 1, offset + (table === 'mission_creneaux' ? cap : 1000)));
      return Promise.resolve({ data: error ? null : single ? limited[0] ?? null : limited,
        error: error ? { message: error, code: invalidColumn ? '42703' : 'TEST_READ_FAILED' } : null,
        count: count && countAvailable && !error ? all.length : null }).then(resolve, reject);
    },
  };
  return q;
}

function segment(id: string, debut: string, fin: string | null, estPause = false): Row {
  return { id, mission_id: missionId, debut, fin, est_pause: estPause, type_creneau: 'PREVISIONNEL' };
}
function plannedTable() {
  return mocks.table.mock.calls.map((call: unknown[]) => call[1] as { head?: string[][]; body: string[][] })
    .find(table => table.head?.[0]?.includes('Durée prév.'));
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, 'error').mockImplementation(() => {});
  failures = {}; countAvailable = true; cap = 2; selections = [];
  rows = {
    factures: [{ id: factureId, mission_id: missionId, etablissement_id: etablissementId,
      numero_facture: 'COMMISSION-TEST', statut: 'EMISE', montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4,
      periode_debut: '2026-09-21', periode_fin: '2026-09-27', mode_paiement: 'STRIPE' }],
    etablissements: [{ id: etablissementId, nom: 'Établissement synthétique' }],
    missions: [{ id: missionId, intitule: 'Mission synthétique', debut_le: '2026-09-21T08:00:00Z', fin_le: '2026-09-22T10:00:00Z',
      duree_heures: 3.5, taux_horaire_base: 20, total_brut: 80, type_contrat_applique: 'LIBERAL', taux_commission_fige: 15,
      soignant_assigne_id: soignantId, montant_commission_ht: 12, montant_commission_tva: 2.4, montant_commission_ttc: 14.4 }],
    soignants: [{ id: soignantId, prenom: 'Test', nom: 'Synthétique', profession: 'IDE', specialites: [] }],
    presences: [],
    mission_creneaux: [
      segment('avant', '2026-09-14T08:00:00Z', '2026-09-14T09:00:00Z'),
      segment('premier', '2026-09-21T08:00:00Z', '2026-09-21T09:30:00Z'),
      segment('pause', '2026-09-21T09:30:00Z', '2026-09-21T10:00:00Z', true),
      segment('second', '2026-09-22T08:00:00Z', '2026-09-22T10:00:00Z'),
      segment('apres', '2026-09-28T08:00:00Z', '2026-09-28T09:00:00Z'),
    ],
  };
  mocks.from.mockImplementation(query);
  mocks.download.mockResolvedValue(undefined);
});

describe('PDF commission : planning réellement chargé', () => {
  it('rend les heures issues de debut/fin, sans pauses, dans la période et sur toutes les pages', async () => {
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.error).not.toHaveBeenCalled();
    expect(mocks.download).toHaveBeenCalledOnce();
    const table = plannedTable();
    expect(table?.body).toHaveLength(2);
    expect(table?.body.map(row => [row[0], row[3]])).toEqual([['21/09', '1.5 h'], ['22/09', '2.0 h']]);
    const requests = selections.filter(s => s.table === 'mission_creneaux');
    expect(requests.map(request => request.offset)).toEqual([0, 2]);
    expect(requests.every(request => request.count && !/\b(debut_le|fin_le|duree_heures)\b/.test(request.select))).toBe(true);
  });

  it('privilégie les pointages réels lorsqu’ils existent', async () => {
    rows.presences = [{ mission_id: missionId, pointage_arrivee_le: '2026-09-21T08:00:00Z',
      pointage_depart_le: '2026-09-21T09:00:00Z', duree_pause_min: 0, heures_reelles: 1 }];
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.error).not.toHaveBeenCalled();
    expect(plannedTable()).toBeUndefined();
    expect(mocks.table.mock.calls.some(([, options]) => options.head?.[0]?.includes('Heures eff.'))).toBe(true);
    expect(mocks.download).toHaveBeenCalledOnce();
  });

  it('refuse un PDF quand les créneaux ne peuvent pas être lus', async () => {
    failures.mission_creneaux = 'Read refused';
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.download).not.toHaveBeenCalled();
    expect(mocks.error).toHaveBeenCalledWith('Impossible de vérifier les créneaux de la mission. Réessayez.');
  });

  it('refuse un planning dont l’exhaustivité ne peut pas être établie', async () => {
    countAvailable = false;
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.download).not.toHaveBeenCalled();
    expect(mocks.error).toHaveBeenCalledWith('Impossible de vérifier les créneaux de la mission. Réessayez.');
  });

  it.each(['factures', 'etablissements', 'missions', 'soignants', 'presences'])('ne génère pas un PDF silencieusement incomplet après une erreur %s', async table => {
    failures[table] = 'Read refused';
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.download).not.toHaveBeenCalled();
    expect(mocks.error).toHaveBeenCalledOnce();
  });

  it.each([null, '2026-09-21T07:00:00Z', 'invalid'])('refuse un créneau incomplet ou incohérent (%s)', async fin => {
    rows.mission_creneaux = [segment('incomplet', '2026-09-21T08:00:00Z', fin)];
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.download).not.toHaveBeenCalled();
    expect(mocks.error).toHaveBeenCalledWith('Le planning prévisionnel est incomplet. Vérifiez la mission avant de télécharger la facture.');
  });
});


describe('PDF commission : dates civiles de facturation', () => {
  it('affiche une période comptable sans heures ni parenthèses vides', async () => {
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.error).not.toHaveBeenCalled();
    const textes = mocks.text.mock.calls.map(([texte]) => texte);
    expect(textes).toContain('21/09/2026 -> 27/09/2026');
    expect(textes.some(texte => typeof texte === 'string' && texte.includes('()'))).toBe(false);
    expect(textes.some(texte => typeof texte === 'string' && /21\/09\/2026 \d{2}h/.test(texte))).toBe(false);
  });
  it('conserve les horaires et la durée de mission lorsqu’aucune période de facture ne les remplace', async () => {
    delete rows.factures[0].periode_debut; delete rows.factures[0].periode_fin;
    await telechargerFactureCommissionPDF(factureId);
    const textes = mocks.text.mock.calls.map(([texte]) => texte);
    expect(textes.some(texte => typeof texte === 'string' && /^21\/09\/2026 \d{2}h00 -> 22\/09\/2026 \d{2}h00 \(3\.5 h\)$/.test(texte))).toBe(true);
  });
  it('n’ajoute aucune parenthèse vide lorsque la durée de mission est absente', async () => {
    delete rows.factures[0].periode_debut; delete rows.factures[0].periode_fin; delete rows.missions[0].duree_heures;
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.text.mock.calls.some(([texte]) => typeof texte === 'string' && texte.includes('()'))).toBe(false);
    expect(mocks.download).toHaveBeenCalledOnce();
  });
});


describe('PDF commission : créneaux effectifs canoniques', () => {
  function effectif(id:string,debut:string,fin:string|null,pause=false) {
    return {...segment(id,debut,fin,pause),type_creneau:'EFFECTIF'};
  }
  function tableEffective() {
    return mocks.table.mock.calls.map(([,options])=>options).find(table=>table.head?.[0]?.includes('Durée effective'));
  }
  it('rend 4 h effectives sans présence historique au lieu du planning prévu', async () => {
    rows.mission_creneaux.push(effectif('effectif','2026-09-21T09:00:00Z','2026-09-21T13:00:00Z'));
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.error).not.toHaveBeenCalled();
    expect(tableEffective()?.body).toEqual([['21/09','11h00','15h00','4.00 h']]);
    expect(plannedTable()).toBeUndefined();
    expect(mocks.text.mock.calls.some(([texte])=>texte==='Créneaux effectifs enregistrés')).toBe(true);
    expect(mocks.text.mock.calls.some(([texte])=>typeof texte==='string' && texte.includes('Aucun pointage'))).toBe(false);
    expect(mocks.download).toHaveBeenCalledOnce();
  });
  it('ne valide pas un prévisionnel inutilisé quand un effectif complet est disponible', async () => {
    rows.mission_creneaux=[
      segment('ancien-planning','2026-09-21T09:00:00Z',null),
      effectif('effectif','2026-09-21T09:00:00Z','2026-09-21T13:00:00Z'),
    ];
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.error).not.toHaveBeenCalled();
    expect(tableEffective()?.body[0][3]).toBe('4.00 h');
    expect(mocks.download).toHaveBeenCalledOnce();
  });
  it('privilégie les créneaux canoniques sur une présence historique agrégée', async () => {
    rows.presences=[{mission_id:missionId,pointage_arrivee_le:'2026-09-21T08:00:00Z',pointage_depart_le:'2026-09-27T12:00:00Z',heures_reelles:148}];
    rows.mission_creneaux.push(effectif('effectif','2026-09-21T09:00:00Z','2026-09-21T13:00:00Z'));
    await telechargerFactureCommissionPDF(factureId);
    expect(tableEffective()?.body[0][3]).toBe('4.00 h');
    expect(mocks.table.mock.calls.some(([,options])=>options.head?.[0]?.includes('Heures eff.'))).toBe(false);
  });
  it('charge toutes les pages, exclut les pauses et tronque aux dates civiles françaises', async () => {
    rows.mission_creneaux=[
      effectif('chevauche-debut','2026-09-20T23:00:00+02:00','2026-09-21T02:00:00+02:00'),
      effectif('pause','2026-09-21T01:00:00+02:00','2026-09-21T01:30:00+02:00',true),
      effectif('chevauche-fin','2026-09-27T23:00:00+02:00','2026-09-28T02:00:00+02:00'),
      effectif('apres','2026-09-28T09:00:00+02:00','2026-09-28T12:00:00+02:00'),
      effectif('avant','2026-09-20T09:00:00+02:00','2026-09-20T12:00:00+02:00'),
    ];
    await telechargerFactureCommissionPDF(factureId);
    expect(tableEffective()?.body).toEqual([['21/09','00h00','02h00','2.00 h'],['27/09','23h00','00h00','1.00 h']]);
    expect(selections.filter(s=>s.table==='mission_creneaux').map(s=>s.offset)).toEqual([0,2]);
  });
  it.each([null,'invalide','2026-09-21T08:00:00Z'])('refuse un effectif incomplet (%s) sans lui substituer le planning', async fin => {
    rows.mission_creneaux.push(effectif('incomplet','2026-09-21T09:00:00Z',fin));
    await telechargerFactureCommissionPDF(factureId);
    expect(mocks.error).toHaveBeenCalledWith('Le planning effectif est incomplet. Vérifiez la mission avant de télécharger la facture.');
    expect(mocks.download).not.toHaveBeenCalled();
  });
});
