import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import ContratMission from './ContratMission';

const ids = vi.hoisted(() => ({
  contract: 'f1560000-0000-4000-8000-000000000002',
  soignant: 'f1560000-0000-4000-8000-000000000001',
  etablissement: 'f1560000-0000-4000-8000-000000000004',
}));
const mocks = vi.hoisted(() => ({
  userId: 'f1560000-0000-4000-8000-000000000001',
  hash: 'a'.repeat(64),
  admissions: [] as Array<(value: any) => void>,
  smsRequests: 0,
  validations: 0,
  holdSecondSms: false,
  pendingSms: [] as Array<(value: any) => void>,
}));
vi.mock('react-router-dom', async importOriginal => ({
  ...(await importOriginal<any>()), useParams: () => ({id: ids.contract}), useNavigate: () => vi.fn(),
}));
vi.mock('@/contexts/AuthContext', () => ({useAuth: () => ({user: {id: mocks.userId}})}));
vi.mock('@/hooks/useRole', () => ({useRole: () => ({role: 'SOIGNANT'})}));
vi.mock('@/contexts/NotificationContext', () => ({useNotification: () => ({afficherNotification: vi.fn()})}));
vi.mock('@/components/LayoutApp', () => ({LayoutApp: ({children}: any) => <main>{children}</main>}));
vi.mock('@/components/ChargementPage', () => ({ChargementPage: () => <p>Chargement de recette</p>}));
vi.mock('@/components/Countdown72hSignature', () => ({Countdown72hSignature: () => null}));
vi.mock('@/components/SignerContratOtp', async importOriginal => {
  const original = await importOriginal<typeof import('@/components/SignerContratOtp')>();
  return {SignerContratOtp: (props: any) => <section data-testid="signature-otp-recette">
    <original.SignerContratOtp {...props} />
    <button onClick={() => { void props.onSigne(); }}>Relire contrat de recette</button>
  </section>};
});
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'https://mejpriaetwgtcstbgfid.supabase.co',
  supabase: {
    rpc: (name: string) => {
      if (name === 'fn_admission_otp_signature_recette') return new Promise(resolve => { mocks.admissions.push(resolve); });
      if (name === 'fn_envoyer_otp_signature') {
        mocks.smsRequests++;
        if (mocks.holdSecondSms && mocks.smsRequests === 2) return new Promise(resolve => { mocks.pendingSms.push(resolve); });
        return Promise.resolve({data: {success: true, telephone_masked: 'numéro fictif', sms_restants: 2, expire_dans_minutes: 10}, error: null});
      }
      if (name === 'fn_signer_contrat_otp') {
        mocks.validations++;
        return Promise.resolve({data: {success: true, role: 'soignant', contrat_complet: false}, error: null});
      }
      return Promise.resolve({data: {nom: 'Établissement de recette'}, error: null});
    },
    from: (table: string) => {
      const query: any = {
        select: () => query, eq: () => query,
        single: async () => ({data: {
          id: ids.contract, mission_id: 'f1560000-0000-4000-8000-000000000003',
          soignant_id: ids.soignant, etablissement_id: ids.etablissement, numero_contrat: 'recette',
          type_contrat: 'LIBERAL', statut: 'EN_ATTENTE_SIGNATURES', cree_le: new Date().toISOString(),
          signature_soignant: false, signature_etablissement: false,
          hash_document: mocks.hash, storage_path: 'recette.pdf', contenu_html: '<p>Contrat fictif de recette</p>',
        }, error: null}),
        maybeSingle: async () => ({data: table === 'soignants'
          ? {prenom: 'Camille', nom: 'Recette', est_compte_test: true}
          : table === 'etablissements' ? {id: ids.etablissement, est_compte_test: true} : {}, error: null}),
      };
      return query;
    },
  },
}));

const optionOtp = () => screen.queryByRole('radio', {name: /Signature électronique OTP SMS/});
const tick = async () => { await act(async () => {}); };
const latestRead = () => mocks.admissions.length - 1;
async function resolveAdmission(index: number, admitted = true, expiresAt = Date.now() + 30_000, remaining = Math.max(0, 2 - mocks.smsRequests), canValidate = mocks.smsRequests > 0, otpExpiresAt = Date.now() + 10 * 60_000) {
  await act(async () => mocks.admissions[index]({data: {admitted, can_send: remaining > 0, can_validate: canValidate, remaining,
    expires_at: new Date(expiresAt).toISOString(), otp_expires_at: canValidate ? new Date(otpExpiresAt).toISOString() : null}, error: null}));
}
async function openAdmission(expiresAt = Date.now() + 30_000) {
  const view = render(<ContratMission />);
  await tick();
  expect(mocks.admissions).toHaveLength(1);
  expect(optionOtp()).not.toBeInTheDocument();
  await resolveAdmission(0, true, expiresAt);
  expect(optionOtp()).toBeInTheDocument();
  fireEvent.click(optionOtp()!);
  await resolveAdmission(latestRead(), true, expiresAt);
  expect(screen.getByTestId('signature-otp-recette')).toBeInTheDocument();
  return view;
}
beforeEach(() => {
  // This suite tests admission and OTP continuity, never canvas drawing.
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-10-14T13:00:00Z'));
  mocks.userId = ids.soignant; mocks.hash = 'a'.repeat(64); mocks.admissions.length = 0;
  mocks.smsRequests = 0; mocks.validations = 0;
  mocks.holdSecondSms = false; mocks.pendingSms.length = 0;
});
afterEach(() => {cleanup(); vi.restoreAllMocks(); vi.useRealTimers();});

it('referme avant une relecture lente et reste fermé après expiration puis révocation', async () => {
  await openAdmission();
  fireEvent.focus(window);
  expect(mocks.admissions).toHaveLength(3);
  expect(optionOtp()).not.toBeInTheDocument();
  expect(screen.getByRole('button', {name: 'Recevoir le code SMS pour signer'})).toBeDisabled();
  fireEvent.click(screen.getByRole('button', {name: 'Recevoir le code SMS pour signer'}));
  expect(mocks.smsRequests).toBe(0);
  await act(async () => vi.advanceTimersByTime(31_000));
  expect(optionOtp()).not.toBeInTheDocument();
  await resolveAdmission(latestRead(), false);
  expect(optionOtp()).not.toBeInTheDocument();
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
});

async function enterReceivedCode(expiresAt = Date.now() + 30_000) {
  fireEvent.click(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/}));
  fireEvent.click(screen.getByRole('button', {name: 'Recevoir le code SMS pour signer'}));
  await tick();
  expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toBeDisabled();
  await resolveAdmission(latestRead(), true, expiresAt);
  fireEvent.change(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'}), {target: {value: '123456'}});
  expect(mocks.smsRequests).toBe(1);
}

it('conserve le code au retour de lecture du SMS, suspend les actions puis reprend sans nouvel envoi', async () => {
  await openAdmission();
  await enterReceivedCode();
  const input = screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'});
  fireEvent.focus(window);
  expect(input).toHaveValue('123456');
  expect(input).toBeDisabled();
  expect(screen.getByRole('button', {name: 'Signer'})).toBeDisabled();
  expect(screen.getByRole('button', {name: 'Renvoyer le code'})).toBeDisabled();
  fireEvent.click(screen.getByRole('button', {name: 'Signer'}));
  fireEvent.click(screen.getByRole('button', {name: 'Renvoyer le code'}));
  expect(mocks.smsRequests).toBe(1); expect(mocks.validations).toBe(0);
  await resolveAdmission(latestRead());
  expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toBe(input);
  expect(input).toHaveValue('123456'); expect(input).not.toBeDisabled();
  expect(mocks.smsRequests).toBe(1); expect(mocks.validations).toBe(0);
  fireEvent.click(screen.getByRole('button', {name: 'Signer'}));
  await tick();
  expect(mocks.validations).toBe(1); expect(mocks.smsRequests).toBe(1);
});

it('détruit la saisie à un retour révoqué sans envoyer ni valider de nouveau code', async () => {
  await openAdmission();
  await enterReceivedCode();
  fireEvent.focus(window);
  expect(screen.getByRole('button', {name: 'Signer'})).toBeDisabled();
  await resolveAdmission(latestRead(), false);
  expect(screen.queryByRole('textbox', {name: 'Code SMS à 6 chiffres'})).not.toBeInTheDocument();
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
  expect(mocks.smsRequests).toBe(1); expect(mocks.validations).toBe(0);
});

it('une relecture sans OTP valide retire la saisie et exige un nouvel envoi explicite autorisé', async () => {
  await openAdmission(); await enterReceivedCode(); fireEvent.focus(window);
  await resolveAdmission(latestRead(), true, Date.now() + 30_000, 1, false);
  expect(screen.queryByRole('textbox', {name: 'Code SMS à 6 chiffres'})).not.toBeInTheDocument();
  expect(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/})).not.toBeChecked();
  expect(screen.getByRole('button', {name: 'Recevoir le code SMS pour signer'})).toBeDisabled();
  expect(mocks.smsRequests).toBe(1); expect(mocks.validations).toBe(0);
});

async function receiveSecondCode(expiresAt = Date.now() + 30_000) {
  await enterReceivedCode(expiresAt);
  fireEvent.click(screen.getByRole('button', {name: 'Renvoyer le code'}));
  await tick();
  expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toBeDisabled();
  await resolveAdmission(latestRead(), true, expiresAt);
  fireEvent.change(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'}), {target: {value: '234567'}});
  expect(mocks.smsRequests).toBe(2);
}

it('conserve le deuxième OTP à remaining zéro et permet uniquement sa validation au retour du SMS', async () => {
  await openAdmission(); await receiveSecondCode();
  const input = screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'});
  fireEvent.focus(window);
  expect(input).toBeDisabled();
  await resolveAdmission(latestRead(), true, Date.now() + 30_000, 0, true);
  expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toBe(input);
  expect(input).toHaveValue('234567'); expect(input).not.toBeDisabled();
  expect(screen.getByRole('button', {name: 'Renvoyer le code'})).toBeDisabled();
  fireEvent.click(screen.getByRole('button', {name: 'Renvoyer le code'}));
  expect(mocks.smsRequests).toBe(2);
  expect(screen.getByRole('button', {name: 'Signer'})).not.toBeDisabled();
  fireEvent.click(screen.getByRole('button', {name: 'Signer'})); await tick();
  expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(1);
});

it('remaining zéro ne survit ni à une révocation ni à l’échéance pendant la relecture', async () => {
  await openAdmission(); await receiveSecondCode(); fireEvent.focus(window);
  await resolveAdmission(latestRead(), false, Date.now() + 30_000, 0, false);
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
  expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(0);
});

it('expire aussi la continuation du deuxième OTP sans prolonger la capacité', async () => {
  await openAdmission(); await receiveSecondCode(); fireEvent.focus(window);
  await resolveAdmission(latestRead(), true, Date.now() + 30_000, 0, true);
  fireEvent.focus(window);
  await act(async () => vi.advanceTimersByTime(30_000));
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
  expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(0);
  await resolveAdmission(latestRead(), false, Date.now(), 0, false);
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
});

for (const userId of [ids.soignant, ids.etablissement]) {
  it(`${userId === ids.soignant ? 'soignant' : 'établissement'} relit OTP2 reçu après démontage pendant l’envoi`, async () => {
    mocks.userId = userId;
    const capacityExpiry = Date.now() + 30 * 60_000;
    await openAdmission(capacityExpiry); await enterReceivedCode(capacityExpiry);
    mocks.holdSecondSms = true;
    fireEvent.click(screen.getByRole('button', {name: 'Renvoyer le code'})); await tick();
    expect(mocks.pendingSms).toHaveLength(1);
    const readsBeforeCanvas = mocks.admissions.length;
    fireEvent.click(screen.getByRole('radio', {name: /Signature manuscrite/})); await tick();
    await act(async () => mocks.pendingSms[0]({data: {success: true, telephone_masked: 'numéro fictif', sms_restants: 1, expire_dans_minutes: 10}, error: null}));
    expect(mocks.admissions).toHaveLength(readsBeforeCanvas); // Unmounted sender callback is still ignored.
    fireEvent.click(optionOtp()!);
    expect(mocks.admissions).toHaveLength(readsBeforeCanvas + 1);
    expect(screen.getByRole('button', {name: 'Recevoir le code SMS pour signer'})).toBeDisabled();
    fireEvent.click(screen.getByRole('button', {name: 'Recevoir le code SMS pour signer'}));
    expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(0);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true);
    expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toHaveValue('');
    expect(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/})).not.toBeChecked();
    expect(screen.getByRole('button', {name: 'Renvoyer le code'})).toBeDisabled();
    fireEvent.change(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'}), {target: {value: '234567'}});
    fireEvent.click(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/}));
    fireEvent.click(screen.getByRole('button', {name: 'Signer'})); await tick();
    expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(1);
  });

  it(`${userId === ids.soignant ? 'soignant' : 'établissement'} reprend OTP2 par CANVAS→OTP directement après l’envoi`, async () => {
    mocks.userId = userId;
    const capacityExpiry = Date.now() + 30 * 60_000;
    await openAdmission(capacityExpiry); await receiveSecondCode(capacityExpiry);
    expect(mocks.admissions).toHaveLength(4); // Initial/selection reads, then each successful send.
    fireEvent.click(screen.getByRole('radio', {name: /Signature manuscrite/}));
    const readsBeforeSelection = mocks.admissions.length;
    fireEvent.click(optionOtp()!);
    expect(mocks.admissions).toHaveLength(readsBeforeSelection + 1);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true);
    expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toHaveValue('');
    expect(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/})).not.toBeChecked();
    expect(screen.getByRole('button', {name: 'Renvoyer le code'})).toBeDisabled();
    fireEvent.change(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'}), {target: {value: '234567'}});
    fireEvent.click(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/}));
    fireEvent.click(screen.getByRole('button', {name: 'Signer'})); await tick();
    expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(1);
  });

  it(`${userId === ids.soignant ? 'soignant' : 'établissement'} reprend OTP2 après recharge et CANVAS→OTP sans troisième SMS`, async () => {
    mocks.userId = userId;
    const issuedExpiry = Date.now() + 10 * 60_000, capacityExpiry = Date.now() + 30 * 60_000;
    const view = await openAdmission(capacityExpiry); await receiveSecondCode(capacityExpiry);
    view.unmount();
    render(<ContratMission />); await tick();
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    fireEvent.click(optionOtp()!);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).toHaveValue('');
    expect(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/})).not.toBeChecked();
    expect(screen.getByRole('button', {name: 'Renvoyer le code'})).toBeDisabled();
    fireEvent.change(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'}), {target: {value: '234567'}});
    fireEvent.click(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/}));
    fireEvent.click(screen.getByRole('radio', {name: /Signature manuscrite/}));
    fireEvent.click(optionOtp()!);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    const input = screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'});
    expect(input).toHaveValue('');
    expect(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/})).not.toBeChecked();
    fireEvent.change(input, {target: {value: '234567'}});
    fireEvent.click(screen.getByRole('checkbox', {name: /J'ai lu l'intégralité du contrat/}));
    fireEvent.focus(window);
    expect(input).toBeDisabled(); expect(screen.getByRole('button', {name: 'Signer'})).toBeDisabled();
    fireEvent.click(screen.getByRole('button', {name: 'Signer'}));
    expect(mocks.validations).toBe(0);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    expect(input).toHaveValue('234567');
    fireEvent.click(screen.getByRole('button', {name: 'Renvoyer le code'}));
    fireEvent.click(screen.getByRole('button', {name: 'Signer'})); await tick();
    expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(1);
  });

  it(`${userId === ids.soignant ? 'soignant' : 'établissement'} ne redonne pas dix minutes à OTP2 après remount`, async () => {
    mocks.userId = userId;
    const issuedExpiry = Date.now() + 10 * 60_000, capacityExpiry = Date.now() + 30 * 60_000;
    const view = await openAdmission(capacityExpiry); await receiveSecondCode(capacityExpiry);
    view.unmount();
    await act(async () => vi.advanceTimersByTime(10 * 60_000 - 10_000));
    render(<ContratMission />); await tick();
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    fireEvent.click(optionOtp()!);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    expect(screen.getByRole('textbox', {name: 'Code SMS à 6 chiffres'})).not.toBeDisabled();
    fireEvent.click(screen.getByRole('radio', {name: /Signature manuscrite/})); fireEvent.click(optionOtp()!);
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    fireEvent.focus(window);
    await act(async () => vi.advanceTimersByTime(10_000));
    expect(optionOtp()).not.toBeInTheDocument();
    expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
    await resolveAdmission(latestRead(), true, capacityExpiry, 0, true, issuedExpiry);
    expect(optionOtp()).not.toBeInTheDocument();
    expect(mocks.smsRequests).toBe(2); expect(mocks.validations).toBe(0);
  });
}

it('lie l’admission au hash affiché et ignore une réponse de l’ancien document', async () => {
  await openAdmission();
  mocks.hash = 'b'.repeat(64);
  fireEvent.click(screen.getByRole('button', {name: 'Relire contrat de recette'}));
  await tick();
  expect(optionOtp()).not.toBeInTheDocument();
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
  const oldRead = mocks.admissions.length - 1;
  fireEvent.focus(window);
  const newRead = mocks.admissions.length - 1;
  expect(newRead).toBeGreaterThan(oldRead);
  await resolveAdmission(oldRead);
  expect(optionOtp()).not.toBeInTheDocument();
  await resolveAdmission(newRead, false);
  expect(optionOtp()).not.toBeInTheDocument();
});

it('referme au changement d’utilisateur et ignore une admission tardive de son ancienne session', async () => {
  const {rerender} = await openAdmission();
  fireEvent.focus(window);
  const oldRead = mocks.admissions.length - 1;
  mocks.userId = ids.etablissement;
  rerender(<ContratMission />);
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
  await tick();
  expect(optionOtp()).not.toBeInTheDocument();
  await resolveAdmission(oldRead);
  expect(optionOtp()).not.toBeInTheDocument();
  await resolveAdmission(mocks.admissions.length - 1, false);
  expect(optionOtp()).not.toBeInTheDocument();
});

it('ferme à l’échéance même sans action et exige une nouvelle admission avant réouverture', async () => {
  await openAdmission();
  await act(async () => vi.advanceTimersByTime(30_000));
  expect(optionOtp()).not.toBeInTheDocument();
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
  fireEvent.focus(window);
  expect(optionOtp()).not.toBeInTheDocument();
  await resolveAdmission(latestRead());
  expect(optionOtp()).toBeInTheDocument();
  expect(screen.queryByTestId('signature-otp-recette')).not.toBeInTheDocument();
});
