import { render, screen, cleanup } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it } from 'vitest';
import { RappelsFiscaux } from './RappelsFiscaux';

afterEach(cleanup);
describe('Accès aux échéanciers officiels', () => {
  it('ne suppose aucun régime, caisse ou délai lorsque le profil est incomplet', () => {
    render(<MemoryRouter><RappelsFiscaux /></MemoryRouter>);
    expect(screen.getByText('Régime fiscal à renseigner')).toBeInTheDocument();
    expect(screen.queryByText(/Micro-BNC|CARPIMKO|dans \d+j|aujourd’hui|trimestrielle/)).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Mes charges et mon régime fiscal' })).toHaveAttribute('href', '/soignant/charges');
  });
  it.each([['MEDECIN','CARMF','https://www.carmf.fr'],['IDE','CARPIMKO','https://www.carpimko.com'],['SAGE_FEMME','CARCDSF','https://www.carcdsf.fr'],['ERGOTHERAPEUTE','CIPAV','https://www.lacipav.fr']])('utilise la caisse déjà configurée pour %s', (profession, caisse, href) => {
    render(<MemoryRouter><RappelsFiscaux profession={profession} /></MemoryRouter>);
    expect(screen.getByRole('link', { name: `${caisse} — site officiel (nouvelle fenêtre)` })).toHaveAttribute('href', href);
    if (caisse !== 'CARPIMKO') expect(screen.queryByRole('link', { name: /CARPIMKO/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/cotisation annuelle|Échéance dans|mai 20\d\d/)).not.toBeInTheDocument();
  });
  it('conserve le régime confirmé sans lui attribuer un calendrier calculé', () => {
    render(<MemoryRouter><RappelsFiscaux profession="MEDECIN" regimeFiscal="DECLARATION_CONTROLEE" regimeFiscalConfirme /></MemoryRouter>);
    expect(screen.getByText('Déclaration contrôlée')).toBeInTheDocument();
    expect(screen.queryByText(/à confirmer|2035|Échue/)).not.toBeInTheDocument();
    for (const link of screen.getAllByRole('link', { name: /site officiel/ })) expect(link).toHaveAttribute('rel','noopener noreferrer');
  });
});
