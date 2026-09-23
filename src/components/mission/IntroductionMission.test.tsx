import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { IntroductionMission } from './IntroductionMission';

describe('Introduction du formulaire mission', () => {
  it('un marqueur de brouillon vide ne prétend pas reprendre une mission', () => {
    render(<IntroductionMission enPreparation brouillon={{ brouillonMission: true, missionFormulaire: {} }} />);
    expect(screen.queryByText(/Brouillon repris/)).not.toBeInTheDocument();
    expect(screen.getByTestId('introduction-mission')).toHaveTextContent('Préparez votre mission. Votre dossier vous sera demandé pour la publier.');
    expect(screen.getByTestId('introduction-mission')).not.toHaveTextContent('·');
  });

  it('réunit le vrai brouillon et sa consigne dans un seul encart', () => {
    render(<IntroductionMission enPreparation brouillon={{
      brouillonMission: true, missionVille: 'Paris', missionDate: '2026-10-01',
      missionFormulaire: { intitule: 'IDE de nuit' },
    }} />);
    expect(screen.getAllByTestId('introduction-mission')).toHaveLength(1);
    expect(screen.getByTestId('introduction-mission')).toHaveTextContent('Brouillon repris — IDE de nuit · Paris · 2026-10-01');
    expect(screen.getByTestId('introduction-mission')).toHaveTextContent('Votre dossier vous sera demandé pour la publier.');
  });

  it('une mission neuve avec établissement complet n’ajoute aucun encart', () => {
    const { container } = render(<IntroductionMission enPreparation={false} brouillon={null} />);
    expect(container).toBeEmptyDOMElement();
  });
});
