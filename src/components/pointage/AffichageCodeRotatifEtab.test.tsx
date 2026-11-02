import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AffichageCodeRotatifEtab } from './AffichageCodeRotatifEtab';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  signature: vi.fn(),
  permissions: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: (name: string, args: unknown) => (
    name === 'fn_contrat_signe_pour_pointage' ? mocks.signature(args)
      : name === 'fn_mes_permissions_etab' ? mocks.permissions(args)
        : mocks.rpc(name, args)) },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'membre-1' } }),
}));

// Matrice de fn_a_permission_etablissement (supabase/schema/public.sql
// l.4916-4934) pour les clés lues par l'écran : le serveur reste l'autorité,
// le composant ne lit que le booléen « pointage » renvoyé par
// fn_mes_permissions_etab.
const CLES = ['gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement',
  'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture'] as const;
const ACCORDEES: Record<string, readonly string[]> = {
  PROPRIETAIRE: CLES,
  ADMIN_GROUPE: ['profil_etab', 'paiement', 'lecture_paiement', 'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture'],
  RH: ['missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture'],
  POINTAGE_ONLY: ['pointage', 'lecture'],
  LECTURE_SEULE: ['lecture_paiement', 'lecture'],
  ADMIN_PLATEFORME: CLES,
};
function reponsePermissions(role: keyof typeof ACCORDEES) {
  return {
    data: {
      success: true,
      role,
      etablissement_id: 'etab-1',
      permissions: Object.fromEntries(CLES.map((cle) => [cle, ACCORDEES[role].includes(cle)])),
    },
    error: null,
  };
}

vi.mock('qrcode.react', () => ({
  QRCodeSVG: ({ value }: { value: string }) => <div data-testid="qr-code">{value}</div>,
}));

vi.mock('sonner', () => ({
  toast: {
    error: mocks.toastError,
    success: mocks.toastSuccess,
  },
}));

function creerBuilder(data: unknown, single = false) {
  const builder: Record<string, any> = {};
  for (const methode of ['select', 'eq', 'not', 'order']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.single = vi.fn(() => Promise.resolve({ data, error: null }));
  builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => (
    Promise.resolve({ data: single ? data : data, error: null }).then(resolve, reject)
  );
  return builder;
}

function renderCode() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  render(
    <QueryClientProvider client={queryClient}>
      <AffichageCodeRotatifEtab missionId="mission-1" etablissementId="etab-1" />
    </QueryClientProvider>,
  );
  return queryClient;
}

describe('AffichageCodeRotatifEtab — fenêtre du créneau', () => {
  let creneauxBuilder: Record<string, any>;
  let creneaux: unknown[];
  let nbCreneaux: number;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));
    creneaux = [];
    nbCreneaux = 1;
    mocks.signature.mockReset().mockResolvedValue({ data: true, error: null });
    mocks.permissions.mockReset().mockResolvedValue(reponsePermissions('PROPRIETAIRE'));
    mocks.from.mockReset();
    mocks.rpc.mockReset();
    mocks.toastError.mockReset();
    mocks.toastSuccess.mockReset();
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [],
        code_pointage_actif: '123456',
      },
      error: null,
    });
    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({
          id: 'mission-1',
          debut_le: '2026-07-06T08:00:00+02:00',
          fin_le: '2026-08-31T16:00:00+02:00',
          nb_creneaux: nbCreneaux,
        }, true);
      }
      if (table === 'contrats_mission') throw new Error('Le rôle pointage ne peut pas lire les contrats.');
      creneauxBuilder = creerBuilder(creneaux);
      return creneauxBuilder;
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('masque le code et explique le prochain créneau lorsqu’il est trop tôt', async () => {
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-08-31T08:00:00+02:00',
      fin: '2026-08-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByText('Code masqué hors créneau')).toBeInTheDocument();
    expect(screen.getByText(/créneau 1\/1, le lundi 31 août 2026 à 08:00/i)).toBeInTheDocument();
    expect(screen.queryByText('123 456')).not.toBeInTheDocument();
    expect(screen.queryByTestId('qr-code')).not.toBeInTheDocument();
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('type_creneau', 'PREVISIONNEL');
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('est_pause', false);
  });

  it('affiche le code et la progression pendant le créneau', async () => {
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByText('123 456')).toBeInTheDocument();
    expect(screen.getByText(/Créneau 1\/1 · vendredi 31 juillet 2026 à 08:00 → 16:00/i)).toBeInTheDocument();
    expect(screen.getByTestId('qr-code')).toHaveTextContent('123456');
    expect(screen.queryByText('Code masqué hors créneau')).not.toBeInTheDocument();
    expect(mocks.signature).toHaveBeenCalledWith({ p_mission_id: 'mission-1' });
    expect(mocks.from).not.toHaveBeenCalledWith('contrats_mission');
  });

  it('associe un EFFECTIF au shift qui contient son début lorsqu’il y en a deux le même jour', async () => {
    vi.setSystemTime(new Date('2026-07-31T15:00:00+02:00'));
    nbCreneaux = 2;
    creneaux = [
      {
        id: 'creneau-matin',
        mission_id: 'mission-1',
        debut: '2026-07-31T08:00:00',
        fin: '2026-07-31T12:00:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
      {
        id: 'creneau-apres-midi',
        mission_id: 'mission-1',
        debut: '2026-07-31T14:00:00',
        fin: '2026-07-31T18:00:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
    ];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'FERMETURE',
        segment_ouvert: true,
        segments: [{ id: 'segment-apres-midi', debut: '2026-07-31T14:05:00', fin: null }],
        code_pointage_actif: '654321',
      },
      error: null,
    });

    renderCode();

    expect(await screen.findByText('654 321')).toBeInTheDocument();
    expect(screen.getByText(/Créneau 2\/2 · vendredi 31 juillet 2026 à 14:00 → 18:00/i)).toBeInTheDocument();
    expect(screen.queryByText(/Créneau 1\/2/i)).not.toBeInTheDocument();
  });

  it('nomme reprise une nouvelle ouverture après un segment fermé le même jour', async () => {
    vi.setSystemTime(new Date('2026-07-31T14:00:00+02:00'));
    creneaux = [{
      id: 'creneau-journee',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T18:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [{ id: 'segment-matin', debut: '2026-07-31T08:00:00+02:00', fin: '2026-07-31T12:00:00+02:00' }],
        code_pointage_actif: '123456',
      },
      error: null,
    });

    renderCode();

    expect(await screen.findByText('Reprise (fin de pause)')).toBeInTheDocument();
  });

  it('nomme arrivée le second PREVISIONNEL distinct du même jour', async () => {
    vi.setSystemTime(new Date('2026-07-31T14:00:00+02:00'));
    nbCreneaux = 2;
    creneaux = [
      {
        id: 'creneau-matin',
        mission_id: 'mission-1',
        debut: '2026-07-31T08:00:00+02:00',
        fin: '2026-07-31T12:00:00+02:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
      {
        id: 'creneau-apres-midi',
        mission_id: 'mission-1',
        debut: '2026-07-31T14:00:00+02:00',
        fin: '2026-07-31T18:00:00+02:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
    ];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [{ id: 'segment-matin', debut: '2026-07-31T08:00:00+02:00', fin: '2026-07-31T12:00:00+02:00' }],
        code_pointage_actif: '123456',
      },
      error: null,
    });

    renderCode();

    expect(await screen.findByText('Arrivée')).toBeInTheDocument();
    expect(screen.queryByText('Reprise (fin de pause)')).not.toBeInTheDocument();
  });

  it('nomme arrivée la première ouverture du jour malgré un segment la veille', async () => {
    creneaux = [{
      id: 'creneau-jour',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [{ id: 'segment-veille', debut: '2026-07-30T08:00:00+02:00', fin: '2026-07-30T16:00:00+02:00' }],
        code_pointage_actif: '123456',
      },
      error: null,
    });

    renderCode();

    expect(await screen.findByText('Arrivée')).toBeInTheDocument();
    expect(screen.queryByText('Reprise (fin de pause)')).not.toBeInTheDocument();
  });

  it('laisse toujours visible le code de sortie lorsqu’un segment est déjà ouvert', async () => {
    nbCreneaux = 2;
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-07-30T08:00:00+02:00',
      fin: '2026-07-30T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'FERMETURE',
        segment_ouvert: true,
        segments: [{ id: 'segment-1', debut: '2026-07-31T08:00:00+02:00', fin: null }],
        code_pointage_actif: '654321',
      },
      error: null,
    });

    renderCode();

    expect(await screen.findByText('654 321')).toBeInTheDocument();
    expect(screen.getByText('Segment en cours')).toBeInTheDocument();
    expect(screen.queryByText('Code masqué hors créneau')).not.toBeInTheDocument();
  });

  it('masque une arrivée lorsque le nombre de créneaux reçu est incomplet', async () => {
    nbCreneaux = 2;
    creneaux = [{
      id: 'creneau-partiel',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByRole('alert')).toHaveTextContent(/planning détaillé est incomplet/i);
    expect(screen.queryByText('123 456')).not.toBeInTheDocument();
    expect(screen.queryByTestId('qr-code')).not.toBeInTheDocument();
  });

  it("signale une heure rétroactive inexistante et réactive toujours le bouton", async () => {
    vi.setSystemTime(new Date('2026-03-29T01:30:00+01:00'));
    creneaux = [{
      id: 'creneau-dst',
      mission_id: 'mission-1',
      debut: '2026-03-29T00:00:00+01:00',
      fin: '2026-03-29T06:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'FERMETURE',
        segment_ouvert: true,
        segments: [{ id: 'segment-dst', debut: '2026-03-29T00:15:00+01:00', fin: null }],
        code_pointage_actif: '654321',
      },
      error: null,
    });

    renderCode();
    fireEvent.click(await screen.findByRole('button', { name: /clôturer le segment/i }));
    const saisie = screen.getByLabelText('Heure de fin réelle');
    fireEvent.change(saisie, { target: { value: '2026-03-29T02:30' } });
    fireEvent.click(screen.getByRole('button', { name: 'Clôturer le segment' }));

    await waitFor(() => {
      expect(mocks.toastError).toHaveBeenCalledWith(expect.stringMatching(/n’existe pas à Paris/i));
      expect(screen.getByRole('button', { name: 'Clôturer le segment' })).not.toBeDisabled();
    });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
  });

  it('masque le code d’arrivée tant que le contrat n’est pas signé', async () => {
    mocks.signature.mockResolvedValue({ data: false, error: null });
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByText('Code masqué — contrat non signé')).toBeInTheDocument();
    expect(screen.getByText(/signé par les deux parties/i)).toBeInTheDocument();
    expect(screen.queryByText('123 456')).not.toBeInTheDocument();
  });

  it.each([null, 'true', { signed: true }])('refuse une arrivée si la signature renvoie une valeur invalide (%j)', async data => {
    mocks.signature.mockResolvedValue({ data, error: null });
    creneaux = [{ id: 'creneau-1', mission_id: 'mission-1', debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' }];
    renderCode();
    expect(await screen.findByRole('alert')).toHaveTextContent('Code masqué');
    expect(screen.queryByTestId('qr-code')).not.toBeInTheDocument();
  });

  it('permet toujours de terminer un segment déjà ouvert si la lecture de signature échoue', async () => {
    mocks.signature.mockResolvedValue({ data: null, error: new Error('Lecture refusée') });
    mocks.rpc.mockResolvedValue({ data: {
      statut: 'EN_COURS', prochain_type_scan: 'FERMETURE', segment_ouvert: true,
      segments: [{ id: 'segment-1', debut: '2026-07-31T08:00:00+02:00', fin: null }],
      code_pointage_actif: '654321',
    }, error: null });
    renderCode();
    expect(await screen.findByText('654 321')).toBeInTheDocument();
    expect(screen.getByTestId('qr-code')).toHaveTextContent('654321');
  });

  it('affiche une erreur actionnable si l’état serveur est indisponible', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: new Error('RPC indisponible') });

    renderCode();

    expect(await screen.findByRole('alert')).toHaveTextContent('Code de pointage indisponible');
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });
});

describe('AffichageCodeRotatifEtab — permission « pointage » (B5b)', () => {
  const creneauEnCours = [{
    id: 'creneau-1',
    mission_id: 'mission-1',
    debut: '2026-07-31T08:00:00+02:00',
    fin: '2026-07-31T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  }];
  const MESSAGE_RESERVE = 'Le code de pointage est réservé aux membres disposant du droit de pointage pour cet établissement.';

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));
    mocks.signature.mockReset().mockResolvedValue({ data: true, error: null });
    mocks.permissions.mockReset();
    mocks.rpc.mockReset().mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'FERMETURE',
        segment_ouvert: true,
        segments: [{ id: 'segment-1', debut: '2026-07-31T08:00:00+02:00', fin: null }],
        code_pointage_actif: '123456',
      },
      error: null,
    });
    mocks.from.mockReset().mockImplementation((table: string) => (table === 'missions'
      ? creerBuilder({
        id: 'mission-1',
        debut_le: '2026-07-31T08:00:00+02:00',
        fin_le: '2026-07-31T16:00:00+02:00',
        nb_creneaux: 1,
      }, true)
      : creerBuilder(creneauEnCours)));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it.each(['PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'ADMIN_PLATEFORME'] as const)(
    'affiche le code et le QR au rôle %s, habilité au pointage de l’établissement de la mission',
    async (role) => {
      mocks.permissions.mockResolvedValue(reponsePermissions(role));

      renderCode();

      expect(await screen.findByText('123 456')).toBeInTheDocument();
      expect(screen.getByTestId('qr-code')).toHaveTextContent('123456');
      expect(screen.getByRole('button', { name: /clôturer le segment/i })).toBeInTheDocument();
      expect(screen.queryByText(MESSAGE_RESERVE)).not.toBeInTheDocument();
      expect(mocks.permissions).toHaveBeenCalledWith({ p_etablissement_id: 'etab-1' });
      expect(mocks.rpc).toHaveBeenCalledWith('fn_etat_pointage_mission', { p_mission_id: 'mission-1' });
    },
  );

  it('réserve le code à LECTURE_SEULE sans lire l’état ni annoncer une indisponibilité passagère', async () => {
    mocks.permissions.mockResolvedValue(reponsePermissions('LECTURE_SEULE'));

    renderCode();

    const titre = await screen.findByRole('heading', { name: 'Code de pointage' });
    const carte = titre.closest('.card-base');
    expect(carte).not.toBeNull();
    // Texte exact et complet de la carte (preuve texte, pas de capture).
    expect(carte!.textContent).toBe(`Code de pointage${MESSAGE_RESERVE}`);
    expect(screen.queryByText('123 456')).not.toBeInTheDocument();
    expect(screen.queryByTestId('qr-code')).not.toBeInTheDocument();
    expect(screen.queryByText(/momentanément indisponible/i)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /clôturer le segment/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(mocks.permissions).toHaveBeenCalledWith({ p_etablissement_id: 'etab-1' });
    // Aucun polling de 5 s ni lecture de planning ou de signature pour un rôle non habilité.
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.signature).not.toHaveBeenCalled();
    expect(mocks.from).not.toHaveBeenCalled();
  });

  it('réserve aussi le code quand le serveur ne rattache le compte à aucun rôle', async () => {
    mocks.permissions.mockResolvedValue({
      data: { success: true, role: null, etablissement_id: null, permissions: {} },
      error: null,
    });

    renderCode();

    expect(await screen.findByText(MESSAGE_RESERVE)).toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('annonce la vérification des accès avant toute lecture du code', async () => {
    let repondre: (valeur: unknown) => void = () => {};
    mocks.permissions.mockReturnValue(new Promise((resolve) => { repondre = resolve; }));

    renderCode();

    expect(screen.getByRole('status')).toHaveTextContent('Vérification des accès au pointage…');
    expect(mocks.rpc).not.toHaveBeenCalled();
    repondre(reponsePermissions('POINTAGE_ONLY'));
    expect(await screen.findByText('123 456')).toBeInTheDocument();
  });

  it('propose de réessayer quand les droits ne peuvent pas être vérifiés, sans afficher de code', async () => {
    mocks.permissions
      .mockResolvedValueOnce({ data: null, error: { message: 'Service indisponible' } })
      .mockResolvedValue(reponsePermissions('RH'));

    renderCode();

    const alerte = await screen.findByRole('alert');
    expect(alerte).toHaveTextContent('Code de pointage indisponible');
    expect(alerte).toHaveTextContent('Vos droits d’accès au pointage n’ont pas pu être vérifiés.');
    expect(screen.queryByTestId('qr-code')).not.toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer les accès' }));

    expect(await screen.findByText('123 456')).toBeInTheDocument();
    expect(mocks.permissions).toHaveBeenCalledTimes(2);
  });
});
