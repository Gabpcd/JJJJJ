# Rappels fiscaux de la page Revenus

Le compte médecin fictif de staging affichait la CARPIMKO et des dates fixes
calculées à partir du jour courant. Aucun échéancier individuel n'était
synchronisé pour justifier ces dates ou les badges d'urgence.

La carte utilise maintenant les liens officiels de la matrice de professions
existante (par exemple CARMF pour MEDECIN), sans modifier cette matrice. La
requête de la page charge explicitement la profession. Un régime absent n'est
plus remplacé côté interface par Micro-BNC ; un régime enregistré mais non
confirmé conserve le libellé « à confirmer ».

## Vérifications

- TypeScript, lint ciblé et six tests unitaires réussis.
- Dix simulations Playwright réussies : médecin sans régime, IDE en déclaration
  contrôlée confirmée, sur iPhone, Android, iPad portrait/paysage et ordinateur.
  La simulation respecte les colonnes demandées à PostgREST pour détecter un
  oubli dans le SELECT ; contrôles après rechargement, erreurs et débordement.
- Cinq vérifications supplémentaires avec Auth et base staging réels sur le
  compte médecin isolé de recette : CARMF visible, aucun rappel CARPIMKO ni
  échéance calculée, accès et rechargement sans erreur HTTP/JavaScript.
  Ce profil possède en base Micro-BNC non confirmé. La première assertion
  supposait à tort un régime NULL ; elle a été corrigée après observation,
  sans modifier les données. Les traces initiales sont conservées.
- Capture iPhone réelle de staging relue visuellement. Les appareils physiques
  et les déclarations auprès des organismes ne sont pas couverts.

Preuves locales hors dépôt :
`audits/2026-09-28-finalisation/finance-ui/rappels-simules/` et
`audits/2026-09-28-finalisation/finance-ui/rappels-staging-reel/`.

## Limite distincte encore ouverte

La page liée `ChargesSociales` conserve des estimations forfaitaires et des
dates génériques, notamment CARPIMKO et le 15 mai. Leur pertinence par profession
et régime doit être revue séparément avant de présenter le module fiscal comme
validé. Cette correction ne valide aucun barème et ne change ni l'éligibilité
libérale, ni le moteur de paie, ni les paiements ou remboursements.
