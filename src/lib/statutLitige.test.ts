import { describe, expect, it } from 'vitest';
import { AlertTriangle, CheckCircle2, Gavel, MessageSquare, Scale, Users, XCircle } from 'lucide-react';
import { estResolu, peutConfirmerAccord, peutProposerMediation, statutBadgeV2 } from './statutLitige';

// Caractérisation du badge web : l'extraction de la partie pure vers
// `statut-litige-regles.ts` ne doit rien changer à ce que rendent les écrans.
describe('statutBadgeV2 — badge web inchangé', () => {
  it.each([
    ['OUVERT', 'Ouvert', Scale, 'bg-warning/10 text-warning border-warning/30', 'OUVERT'],
    ['EN_DISCUSSION', 'En discussion', MessageSquare, 'bg-warning/10 text-warning border-warning/30', 'OUVERT'],
    ['EN_MEDIATION', 'Médiation', AlertTriangle, 'bg-info/10 text-info border-info/30', 'MEDIATION'],
    ['MEDIATION_EN_COURS', 'Médiation en cours', Users, 'bg-info/10 text-info border-info/30', 'MEDIATION'],
    ['REVUE_ADMIN', 'Revue admin', Gavel, 'bg-destructive/10 text-destructive border-destructive/30', 'ACTION_ATTENDUE'],
    ['RESOLU_ACCORD_PARTIES', 'Accord mutuel ✅', CheckCircle2, 'bg-success/10 text-success border-success/30', 'RESOLU_ACCORD'],
    ['RESOLU_FAVEUR_SOIGNANT', 'Tranché en faveur soignant', Gavel, 'bg-success/5 text-foreground border-border', 'RESOLU_DECISION'],
    ['RESOLU_FAVEUR_ETAB', 'Tranché en faveur étab', Gavel, 'bg-success/5 text-foreground border-border', 'RESOLU_DECISION'],
    ['RESOLU_PARTAGE', 'Tranché : décision partagée', Gavel, 'bg-success/5 text-foreground border-border', 'RESOLU_DECISION'],
    ['RESOLU_SOIGNANT', 'Résolu (soignant)', CheckCircle2, 'bg-success/5 text-foreground border-border', 'RESOLU_DECISION'],
    ['RESOLU_ETABLISSEMENT', 'Résolu (étab)', CheckCircle2, 'bg-success/5 text-foreground border-border', 'RESOLU_DECISION'],
    ['RESOLU_ADMIN', 'Résolu admin', Gavel, 'bg-muted text-muted-foreground border-border', 'FERME'],
    ['FERME', 'Fermé', XCircle, 'bg-muted text-muted-foreground border-border', 'FERME'],
    ['STATUT_FUTUR', 'STATUT_FUTUR', Scale, 'bg-muted text-muted-foreground border-border', 'OUVERT'],
  ])('%s', (statut, label, icon, classes, groupe) => {
    expect(statutBadgeV2(statut)).toEqual({ label, icon, classes, groupe });
  });

  it('réexporte les prédicats de statut', () => {
    expect(estResolu('FERME')).toBe(true);
    expect(estResolu('OUVERT')).toBe(false);
    expect(peutProposerMediation('EN_MEDIATION')).toBe(true);
    expect(peutConfirmerAccord('MEDIATION_EN_COURS')).toBe(true);
  });
});
