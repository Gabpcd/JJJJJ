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
