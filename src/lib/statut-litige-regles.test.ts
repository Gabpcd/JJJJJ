import { describe, expect, it } from 'vitest';
import {
  estResolu,
  peutConfirmerAccord,
  peutProposerMediation,
  statutLitigeRegle,
} from './statut-litige-regles';

// Partie pure de `statutLitige.ts` (sans lucide-react), extraite telle quelle.
const TABLE: Array<[string, string, string, string, string]> = [
  // statut, libellé, icône, groupe, classes
  ['OUVERT', 'Ouvert', 'Scale', 'OUVERT', 'bg-warning/10 text-warning border-warning/30'],
  ['EN_DISCUSSION', 'En discussion', 'MessageSquare', 'OUVERT', 'bg-warning/10 text-warning border-warning/30'],
  ['EN_MEDIATION', 'Médiation', 'AlertTriangle', 'MEDIATION', 'bg-info/10 text-info border-info/30'],
  ['MEDIATION_EN_COURS', 'Médiation en cours', 'Users', 'MEDIATION', 'bg-info/10 text-info border-info/30'],
  ['REVUE_ADMIN', 'Revue admin', 'Gavel', 'ACTION_ATTENDUE', 'bg-destructive/10 text-destructive border-destructive/30'],
  ['RESOLU_ACCORD_PARTIES', 'Accord mutuel ✅', 'CheckCircle2', 'RESOLU_ACCORD', 'bg-success/10 text-success border-success/30'],
  ['RESOLU_FAVEUR_SOIGNANT', 'Tranché en faveur soignant', 'Gavel', 'RESOLU_DECISION', 'bg-success/5 text-foreground border-border'],
  ['RESOLU_FAVEUR_ETAB', 'Tranché en faveur étab', 'Gavel', 'RESOLU_DECISION', 'bg-success/5 text-foreground border-border'],
  ['RESOLU_PARTAGE', 'Tranché : décision partagée', 'Gavel', 'RESOLU_DECISION', 'bg-success/5 text-foreground border-border'],
  ['RESOLU_SOIGNANT', 'Résolu (soignant)', 'CheckCircle2', 'RESOLU_DECISION', 'bg-success/5 text-foreground border-border'],
  ['RESOLU_ETABLISSEMENT', 'Résolu (étab)', 'CheckCircle2', 'RESOLU_DECISION', 'bg-success/5 text-foreground border-border'],
  ['RESOLU_ADMIN', 'Résolu admin', 'Gavel', 'FERME', 'bg-muted text-muted-foreground border-border'],
  ['FERME', 'Fermé', 'XCircle', 'FERME', 'bg-muted text-muted-foreground border-border'],
];

describe('statutLitigeRegle — libellé, groupe et icône par statut', () => {
  it.each(TABLE)('%s', (statut, label, icone, groupe, classes) => {
    expect(statutLitigeRegle(statut)).toEqual({ label, icone, groupe, classes });
  });

  it('un statut inconnu garde son code comme libellé, dans le groupe OUVERT', () => {
    expect(statutLitigeRegle('STATUT_FUTUR')).toEqual({
      label: 'STATUT_FUTUR',
      icone: 'Scale',
      groupe: 'OUVERT',
      classes: 'bg-muted text-muted-foreground border-border',
    });
  });
});

describe('prédicats de statut', () => {
  const tous = [...TABLE.map(([statut]) => statut), 'STATUT_FUTUR', ''];
  const vrais = (predicat: (statut: string) => boolean) => tous.filter(predicat);

  it('estResolu : statuts résolus et fermés', () => {
    expect(vrais(estResolu)).toEqual([
      'RESOLU_ACCORD_PARTIES',
      'RESOLU_FAVEUR_SOIGNANT',
      'RESOLU_FAVEUR_ETAB',
      'RESOLU_PARTAGE',
      'RESOLU_SOIGNANT',
      'RESOLU_ETABLISSEMENT',
      'RESOLU_ADMIN',
      'FERME',
    ]);
  });

  it('peutProposerMediation : ouvert, en discussion, en médiation', () => {
    expect(vrais(peutProposerMediation)).toEqual(['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION']);
  });

  it('peutConfirmerAccord : ouvert, en discussion, en médiation, médiation en cours', () => {
    expect(vrais(peutConfirmerAccord)).toEqual(['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS']);
  });
});
