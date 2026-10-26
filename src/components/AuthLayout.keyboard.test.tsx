import { fireEvent, render } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AuthLayout } from './AuthLayout';

describe('navigation clavier des formulaires Auth', () => {
  beforeEach(() => {
    Object.defineProperty(HTMLElement.prototype, 'scrollTo', {
      configurable: true,
      value: vi.fn(),
    });
  });

  it('annonce Suivant puis place le focus sur le champ suivant', () => {
    const { getByLabelText } = render(
      <MemoryRouter>
        <AuthLayout showBack={false}>
          <form>
            <label>Email<input aria-label="Email" type="email" /></label>
            <label>Mot de passe<input aria-label="Mot de passe" type="password" /></label>
            <button type="submit">Continuer</button>
          </form>
        </AuthLayout>
      </MemoryRouter>,
    );
    const email = getByLabelText('Email') as HTMLInputElement;
    const password = getByLabelText('Mot de passe') as HTMLInputElement;

    expect(email.enterKeyHint).toBe('next');
    expect(password.enterKeyHint).toBe('done');
    email.focus();
    fireEvent.keyDown(email, { key: 'Enter' });
    expect(document.activeElement).toBe(password);
  });

  it('inclut les champs étudiant ajoutés sans changer d’étape ni remonter le formulaire', () => {
    const formulaire = (etudiant: boolean) => (
      <MemoryRouter>
        <AuthLayout showBack={false} scrollKey={2}>
          <form>
            <input aria-label="Date de naissance" type="date" />
            {etudiant && <div>
              <select aria-label="Formation"><option>Médecine</option></select>
              <input aria-label="Année validée" inputMode="numeric" />
            </div>}
            <input aria-label="RPPS" />
          </form>
        </AuthLayout>
      </MemoryRouter>
    );
    const { container, getByLabelText, rerender } = render(formulaire(false));
    const scroller = container.querySelector('main')!;
    scroller.scrollTop = 240;
    vi.mocked(scroller.scrollTo).mockClear();

    rerender(formulaire(true));
    const date = getByLabelText('Date de naissance');
    const formation = getByLabelText('Formation');
    const annee = getByLabelText('Année validée') as HTMLInputElement;
    const rpps = getByLabelText('RPPS');
    const focusFormation = vi.spyOn(formation, 'focus');
    date.focus();
    fireEvent.keyDown(date, { key: 'Enter' });
    expect(document.activeElement).toBe(formation);
    expect(focusFormation).toHaveBeenCalledWith({ preventScroll: true });

    annee.focus();
    expect(annee.enterKeyHint).toBe('next');
    fireEvent.keyDown(annee, { key: 'Enter' });
    expect(document.activeElement).toBe(rpps);
    expect(scroller.scrollTop).toBe(240);
    expect(scroller.scrollTo).not.toHaveBeenCalled();
  });

  it('repart en haut lors d’une nouvelle étape, sans écraser une position restaurée au montage', () => {
    const formulaire = (etape: number) => (
      <MemoryRouter><AuthLayout scrollKey={etape}><form><input aria-label="Email" /></form></AuthLayout></MemoryRouter>
    );
    const { getByRole, rerender } = render(formulaire(1));
    const scroller = getByRole('main');
    expect(scroller.scrollTo).not.toHaveBeenCalled();
    scroller.scrollTop = 240;
    rerender(formulaire(2));
    expect(scroller.scrollTo).toHaveBeenCalledExactlyOnceWith({ top: 0, behavior: 'instant' });
  });

  it('ignore le RPPS retiré et les champs masqués, inertes, désactivés ou en lecture seule', () => {
    const formulaire = (rpps: boolean) => (
      <MemoryRouter>
        <AuthLayout showBack={false} scrollKey={2}>
          <form>
            <input aria-label="Prénom" />
            {rpps && <input key="rpps" aria-label="RPPS" />}
            <div hidden><input aria-label="Champ masqué" /></div>
            <div style={{ display: 'none' }}><input aria-label="Champ sans affichage" /></div>
            <input aria-label="Champ invisible" style={{ visibility: 'hidden' }} />
            <div ref={element => { element?.setAttribute('inert', ''); }}><input aria-label="Champ inerte" /></div>
            <fieldset disabled><input aria-label="Champ désactivé" /></fieldset>
            <input aria-label="Identité vérifiée" readOnly />
            <input aria-label="Téléphone" type="tel" />
          </form>
        </AuthLayout>
      </MemoryRouter>
    );
    const { getByLabelText, rerender } = render(formulaire(true));
    const ancienRpps = getByLabelText('RPPS');
    const focusAncienRpps = vi.spyOn(ancienRpps, 'focus');
    rerender(formulaire(false));

    const prenom = getByLabelText('Prénom');
    prenom.focus();
    fireEvent.keyDown(prenom, { key: 'Enter' });
    expect(document.activeElement).toBe(getByLabelText('Téléphone'));
    expect(focusAncienRpps).not.toHaveBeenCalled();
    expect((getByLabelText('Téléphone') as HTMLInputElement).enterKeyHint).toBe('done');
  });

  it('préserve Entrée sur le dernier champ, les zones multilignes et la composition', () => {
    const { getByLabelText } = render(
      <MemoryRouter>
        <AuthLayout showBack={false}>
          <form>
            <input aria-label="Prénom" />
            <textarea aria-label="Précisions" />
            <input aria-label="Téléphone" type="tel" />
          </form>
        </AuthLayout>
      </MemoryRouter>,
    );
    const prenom = getByLabelText('Prénom');
    prenom.focus();
    expect(fireEvent.keyDown(prenom, { key: 'Enter', isComposing: true })).toBe(true);
    expect(document.activeElement).toBe(prenom);

    const precisions = getByLabelText('Précisions');
    precisions.focus();
    expect(fireEvent.keyDown(precisions, { key: 'Enter' })).toBe(true);
    expect(document.activeElement).toBe(precisions);

    const telephone = getByLabelText('Téléphone');
    telephone.focus();
    expect(fireEvent.keyDown(telephone, { key: 'Enter' })).toBe(true);
    expect(document.activeElement).toBe(telephone);
  });

  it('attend la fin du toucher avant de masquer le clavier sur le fond', () => {
    const { container, getByLabelText } = render(
      <MemoryRouter>
        <AuthLayout showBack={false}>
          <form>
            <label>Email<input aria-label="Email" type="email" /></label>
          </form>
        </AuthLayout>
      </MemoryRouter>,
    );
    const email = getByLabelText('Email') as HTMLInputElement;
    const background = container.querySelector('main');
    expect(background).toBeTruthy();

    email.focus();
    fireEvent.pointerDown(background!);
    expect(document.activeElement).toBe(email);

    fireEvent.click(background!);
    expect(document.activeElement).not.toBe(email);
  });
});
