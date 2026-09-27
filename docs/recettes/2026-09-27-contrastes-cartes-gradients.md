# Contrastes des cartes et conversations renseignées

L'inspection des captures natives a révélé des badges de mission trop clairs.
Les anciens contrôles d'accessibilité avec une liste vide ne pouvaient pas
exercer ces textes. La nouvelle recette conserve les états vides et ajoute une
carte renseignée sur cinq formats, en clair et sombre.

Avant correction, axe mesure 3,53:1 pour le badge de profession et 2,49:1 pour
le contrat CDD : deux violations sérieuses. Les nuances plus foncées corrigent
les deux badges sans changer les données ni leurs conditions d'affichage.

Les dégradés demandent une mesure complémentaire : axe ne calcule pas le
contraste du texte sur une image de fond. Un contrôle du texte de l'onglet actif
reproduit 1,499:1 avec le blanc. L'encre opaque `#2b183d` est appliquée aux
dégradés pastel dans les deux thèmes et aux boutons concernés. Les descendants
des cartes KPI, de la célébration et des bulles de discussion conservent cette
encre ; les opacités qui diminuaient le contraste sont retirées.

La nouvelle recette de messagerie utilise uniquement des données fictives
locales. Elle ouvre une conversation contenant des messages reçus, envoyés,
d'administration et d'équipe, puis contrôle les archives. Elle vérifie les
textes, les horodatages, les noms accessibles, l'absence de débordement et les
violations axe graves/critiques pour les deux rôles, dans les deux thèmes et
sur les cinq formats. Elle ne soumet aucun message à un prestataire réel.

Le premier passage a aussi trouvé deux défauts dans la liste sur grand écran :
le compteur des archives semi-transparent (3,17:1 en clair, 3,83:1 en sombre)
et le libellé de mission (4,34:1). Le compteur reste désormais opaque et le
libellé utilise une nuance plus foncée. Le texte de lecture seule des archives
et les horodatages reçus restent opaques eux aussi. L'état archivé non lu a
révélé un horodatage rose trop clair (2,59:1) : sa nuance et celle du statut
de saisie sur le même fond sont également corrigées.

Les mesures de dégradé utilisent la couleur calculée du navigateur et une
interpolation de chaque segment, y compris ses extrémités. Elles refusent les
fonds ou textes transparents et les opacités intermédiaires, puis exigent
4,5:1. Ce contrôle ne prétend pas couvrir les contenus non exercés ni remplacer
un audit avec VoiceOver/TalkBack.

La première validation locale complète a réussi 50 cas, 95 états axe et
60 mesures de dégradé, dont le minimum est 4,8996:1. Les dix captures de carte
ont ensuite été reproduites sur les cinq formats. La recette de messagerie
a réussi ses 20 scénarios et 40 états conversation/archives, sans violation
grave/critique, débordement, endpoint inconnu ni erreur JavaScript, sans retry
ni scénario ignoré. La CI de la révision finale complète ces résultats ; son
statut doit être lu sur le commit effectivement proposé à la fusion.
