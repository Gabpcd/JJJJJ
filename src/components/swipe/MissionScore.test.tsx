import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { CardMissionSwipe, type MissionSwipePayload } from './CardMissionSwipe';
import { ModalDetailMissionSwipe } from './ModalDetailMissionSwipe';

function offre(score: number | null, extra: Partial<MissionSwipePayload> = {}): MissionSwipePayload {
  return {
    mission_id:'mission', intitule:'Mission de jour', profession_requise:'IDE',
    etablissement_id:'etab', etablissement_nom:'Résidence Camille', etablissement_ville:'Paris',
    etablissement_code_postal:'75011', etablissement_logo_url:null, etablissement_score:null,
    taux_horaire_base:30, total_brut:240, net_a_payer:240, net_estime:240,
    montant_ifm:null, montant_icp:null, montant_majoration_nuit:null,
    montant_majoration_dimanche:null, montant_majoration_ferie:null,
    type_contrat_applique:null, type_contrat_recherche:'LIBERAL', duree_heures:8,
    debut_le:'2026-10-06T08:00:00Z', fin_le:'2026-10-06T16:00:00Z', est_urgente:true,
    service:null, distance_km:null, score, breakdown:{distance:18}, paiement_rapide:true,
    ...extra,
  };
}

describe('Score de matching inconnu ou réellement calculé', () => {
  it('la carte sans score ne fabrique ni zéro, ni explication, ni score vocal et reste ouvrable', () => {
    const onTap = vi.fn();
    render(<CardMissionSwipe mission={offre(null)} onTap={onTap} />);
    expect(screen.queryByText(/\/100/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Pourquoi/)).not.toBeInTheDocument();
    const carte = screen.getByRole('button', {name:/Mission IDE à Résidence Camille/});
    expect(carte).not.toHaveAccessibleName(/score|null/);
    expect(screen.getByText('🔥 Urgent').parentElement).toHaveClass('ml-auto');
    expect(screen.getByText('⚡ Paiement rapide')).toBeInTheDocument();
    fireEvent.click(carte);
    expect(onTap).toHaveBeenCalledOnce();
  });

  it.each([0,85])('la carte conserve le vrai score %i et son nom accessible', score => {
    render(<CardMissionSwipe mission={offre(score)} />);
    expect(screen.getByText(`${score}/100`)).toBeInTheDocument();
    expect(screen.getByRole('button')).toHaveAccessibleName(new RegExp(`score ${score} sur 100`));
    expect(screen.getByText(`Pourquoi ${score} ?`)).toBeInTheDocument();
  });

  it('le détail sans score masque le matching mais conserve urgence, paiement et actions', () => {
    render(<ModalDetailMissionSwipe mission={offre(null)} open onOpenChange={vi.fn()} onPostuler={vi.fn()} onSuivant={vi.fn()} />);
    expect(screen.queryByText(/Match .*\/100/)).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', {name:'Pourquoi ce match'})).not.toBeInTheDocument();
    expect(screen.getByText('🔥 Urgent').parentElement).toHaveClass('ml-auto');
    expect(screen.getByText('⚡ Paiement rapide')).toBeInTheDocument();
    expect(screen.getByRole('button', {name:/Candidater|Postuler/i})).toBeEnabled();
  });

  it.each([0,85])('le détail conserve le vrai score %i et son explication', score => {
    render(<ModalDetailMissionSwipe mission={offre(score)} open onOpenChange={vi.fn()} onPostuler={vi.fn()} onSuivant={vi.fn()} />);
    expect(screen.getByText(`Match ${score}/100`)).toBeInTheDocument();
    expect(screen.getByRole('heading', {name:'Pourquoi ce match'})).toBeInTheDocument();
  });
});
