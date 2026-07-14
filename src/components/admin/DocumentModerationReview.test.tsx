import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import {
  buildDocumentCasSnapshot,
  DocumentModerationCard,
  DocumentValidationDialog,
  documentRequiresExceptionalOverride,
  type DocumentModerationEntry,
} from './DocumentModerationReview';

const makeDocument = (overrides: Partial<DocumentModerationEntry> = {}): DocumentModerationEntry => ({
  id: '11111111-1111-4111-8111-111111111111',
  nom_fichier: 'preuve-identite.pdf',
  type_document: 'CARTE_IDENTITE',
  soignant_id: '22222222-2222-4222-8222-222222222222',
  televerse_le: '2026-07-14T04:00:00.000Z',
  modifie_le: '2026-07-14T04:01:00.000Z',
  s3_bucket: 'jolene-documents',
  s3_cle: 'soignants/222/preuve.pdf',
  s3_version_id: 'version-1',
  type_mime: 'application/pdf',
  taille_octets: 204800,
  statut_verification: 'EN_ATTENTE',
  motif_rejet: 'Date de naissance à confirmer manuellement.',
  resultat_ia: {
    verdict: 'EN_ATTENTE',
    verdict_serveur: 'EN_ATTENTE',
    type_detecte: 'Carte nationale d’identité',
    confiance: 'MOYENNE',
    score_confiance: 74,
    nom_extrait: 'LEFEVRE',
    prenom_extrait: 'Marie',
    date_naissance_extraite: '1990-03-02',
    date_expiration: '2031-03-01',
    indices_falsification: [],
  },
  nom_extrait_ia: 'LEFEVRE',
  prenom_extrait_ia: 'Marie',
  score_confiance_ia: 74,
  coherence_nom: true,
  valide_depuis: null,
  valide_jusqua: null,
  exige_expiration: true,
  soignant: {
    id: '22222222-2222-4222-8222-222222222222',
    prenom: 'Marie',
    nom: 'Lefèvre',
    email: 'marie@example.test',
    profession: 'IADE',
    date_naissance: '1990-03-02',
    numero_rpps: '10101234567',
    numero_adeli: null,
    rpps_verifie: true,
    adeli_verifie: false,
    modifie_le: '2026-07-14T03:59:00.000Z',
  },
  ...overrides,
});

describe('DocumentModerationCard', () => {
  it('affiche identité, profession, source, motif IA et champs propres au type', () => {
    const document = makeDocument();
    render(
      <DocumentModerationCard
        document={document}
        typeLabel="Pièce d’identité"
        onOpen={vi.fn()}
        onValidate={vi.fn()}
        onReject={vi.fn()}
      />,
    );

    expect(screen.getByText('Marie Lefèvre')).toBeInTheDocument();
    expect(screen.getByText('Infirmier·ère anesthésiste (IADE)')).toBeInTheDocument();
    expect(screen.getByText('Analyse IA + contrôles serveur')).toBeInTheDocument();
    expect(screen.getByText(/Date de naissance à confirmer/)).toBeInTheDocument();
    expect(screen.getByText('1990-03-02')).toBeInTheDocument();
    expect(screen.getByText('2031-03-01')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Ouvrir la revue de validation' })).toBeEnabled();
  });

  it('bloque le bouton de validation si le profil ne peut pas être chargé', () => {
    render(
      <DocumentModerationCard
        document={makeDocument({ soignant: null })}
        typeLabel="Pièce d’identité"
        onOpen={vi.fn()}
        onValidate={vi.fn()}
        onReject={vi.fn()}
      />,
    );
    expect(screen.getByText(/Profil indisponible/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Ouvrir la revue de validation' })).toBeDisabled();
  });
});

describe('DocumentValidationDialog', () => {
  it('permet une décision manuelle contextualisée après timeout, jamais un clic simple', () => {
    const onConfirm = vi.fn();
    const document = makeDocument({
      resultat_ia: { erreur_anthropic: { status: 'timeout' } },
      nom_extrait_ia: null,
      prenom_extrait_ia: null,
      score_confiance_ia: null,
      coherence_nom: null,
    });
    render(
      <DocumentValidationDialog
        document={document}
        typeLabel="Pièce d’identité"
        onCancel={vi.fn()}
        onConfirm={onConfirm}
      />,
    );

    expect(screen.getByText(/analyse automatique est indisponible/i)).toBeInTheDocument();
    const submit = screen.getByRole('button', { name: 'Valider après contrôles' });
    expect(submit).toBeDisabled();

    fireEvent.change(screen.getByLabelText('Nom *'), { target: { value: 'Lefèvre' } });
    fireEvent.change(screen.getByLabelText('Prénom *'), { target: { value: 'Marie' } });
    fireEvent.change(screen.getByLabelText('Date de naissance lue *'), { target: { value: '1990-03-02' } });
    fireEvent.change(screen.getByLabelText('Date d’expiration lue *'), { target: { value: '2031-03-01' } });
    fireEvent.click(screen.getByLabelText(/document est lisible/i));
    fireEvent.click(screen.getByLabelText(/document est complet/i));
    fireEvent.click(screen.getByLabelText(/est bien un document de type/i));
    fireEvent.click(screen.getByLabelText(/contrôlé les signes de retouche/i));

    expect(submit).toBeEnabled();
    fireEvent.click(submit);
    expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(onConfirm).toHaveBeenCalledWith(expect.objectContaining({
      raisonOverride: null,
      validation: expect.objectContaining({
        expected_document_modifie_le: document.modifie_le,
        expected_soignant_modifie_le: document.soignant?.modifie_le,
        expected_s3_version_id: 'version-1',
        nom_extrait: 'Lefèvre',
        prenom_extrait: 'Marie',
        date_naissance: '1990-03-02',
        date_expiration: '2031-03-01',
        antifraude_verifiee: true,
      }),
    }));
  });

  it('exige une motivation et une confirmation explicites face à un rejet IA', () => {
    const onConfirm = vi.fn();
    const document = makeDocument({
      resultat_ia: {
        verdict: 'REJETE',
        verdict_serveur: 'REJETE',
        indices_falsification: ['Police incohérente autour du nom'],
        nom_extrait: 'LEFEVRE',
        prenom_extrait: 'Marie',
        date_naissance_extraite: '1990-03-02',
        date_expiration: '2031-03-01',
      },
    });
    expect(documentRequiresExceptionalOverride(document)).toBe(true);
    render(
      <DocumentValidationDialog
        document={document}
        typeLabel="Pièce d’identité"
        onCancel={vi.fn()}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.click(screen.getByLabelText(/document est lisible/i));
    fireEvent.click(screen.getByLabelText(/document est complet/i));
    fireEvent.click(screen.getByLabelText(/est bien un document de type/i));
    fireEvent.click(screen.getByLabelText(/contrôlé les signes de retouche/i));
    const submit = screen.getByRole('button', { name: 'Valider après contrôles' });
    expect(submit).toBeDisabled();

    fireEvent.click(screen.getByLabelText(/dérogation exceptionnelle, personnellement tracée/i));
    fireEvent.change(screen.getByLabelText(/Motivation détaillée/i), {
      target: { value: 'Le PDF original signé a été comparé au registre et la zone signalée correspond au filigrane officiel.' },
    });
    expect(submit).toBeEnabled();
    fireEvent.click(submit);
    expect(onConfirm).toHaveBeenCalledWith(expect.objectContaining({
      raisonOverride: expect.stringContaining('PDF original signé'),
      validation: expect.objectContaining({ override_confirme: true }),
    }));
  });

  it('ne préremplit ni ne conserve un IBAN complet dans les données affichées', () => {
    const document = makeDocument({
      type_document: 'RIB',
      exige_expiration: false,
      resultat_ia: { iban_valide: true, iban_last4: '0189', verdict_serveur: 'EN_ATTENTE' },
      nom_extrait_ia: 'LEFEVRE',
      prenom_extrait_ia: 'Marie',
    });
    render(
      <DocumentValidationDialog
        document={document}
        typeLabel="RIB"
        onCancel={vi.fn()}
        onConfirm={vi.fn()}
      />,
    );
    const iban = screen.getByLabelText(/IBAN complet lu sur le RIB/);
    expect(iban).toHaveValue('');
    expect(screen.getByText(/jamais conservé en clair/i)).toBeInTheDocument();
  });
});

describe('buildDocumentCasSnapshot', () => {
  it('lie la décision à la version du document, sa source et la version du profil', () => {
    const document = makeDocument();
    expect(buildDocumentCasSnapshot(document)).toEqual({
      expected_document_modifie_le: document.modifie_le,
      expected_soignant_modifie_le: document.soignant?.modifie_le,
      expected_statut: 'EN_ATTENTE',
      expected_type_document: 'CARTE_IDENTITE',
      expected_soignant_id: document.soignant_id,
      expected_s3_bucket: 'jolene-documents',
      expected_s3_cle: 'soignants/222/preuve.pdf',
      expected_s3_version_id: 'version-1',
    });
  });
});
