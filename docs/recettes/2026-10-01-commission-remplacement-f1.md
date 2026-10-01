# Commission après remplacement d’une facture F1

Une correction de taux à quantité stable recalculait deux fois la commission
globale d’une mission EN_COURS : par les triggers lors du changement de taux,
puis par le helper de commission documentaire. Pour une mission de 8 h corrigée
à 18 €/h, le net était de 144 €, mais la commission HT descendait à 20,40 € au
lieu de 21,60 €.

Le rouge réel initial est le job SQL [110294195031](https://github.com/Gabpcd/JJJJJ/actions/runs/36839281025/job/110294195031),
au commit `1ef76a17233d9e195b97a4efa7097ec42ffb7450` :
`F1_RECTIF_GLOBAL_COMMISSION_INCOHERENTE net attendu=144 obtenu=144.00 ; commission HT attendue=21.60 obtenue=20.40`.
Le préflight et le SELECT indépendant après échec ont confirmé les compteurs et
le catalogue inchangés, sans résidu. Le run antérieur `36838854229` avait échoué
dans une suite cron utilisant un correctif absent du staging, avant ce témoin ;
il ne constitue pas la preuve de ce défaut financier.

La migration modifie uniquement
`fn_preparer_commission_remplacement_honoraires(uuid)`. Elle évite le second
delta lorsque la mission est EN_COURS, que les quantités snapshot sont positives,
finies et identiques, que les deux taux sont positifs et finis mais différents,
et que le taux courant de mission correspond au nouveau snapshot. Dans ce cas,
la création de la commission conserve les agrégats déjà recalculés et lève le
marqueur `commission_a_recalculer` après succès. Sinon, le chemin historique
reste identique. Le taux historique de commission, la filiation documentaire,
les verrous, le refus d’une commission d’origine déjà payée, les droits et le
retour idempotent restent inchangés. Aucune correction de données historiques,
aucun nouveau taux et aucun changement de paiement, d’avoir ou de complément.

Les définitions LIVE staging et production ont la même empreinte
`md5(pg_get_functiondef) = b35b9b246690238ccb77e19e484c2a77` ; le corps seul a
`md5(prosrc) = e206148ca3a7073ccc05d76e68d710fa`. La migration vérifie les
empreintes, le propriétaire, le search_path, les droits service-only et
l’inventaire SECURITY DEFINER. Le snapshot reprend exactement le nouveau corps.
Les autres définitions LIVE restent dans les preuves locales.

Le test utilise trois identités synthétiques, le vrai résolveur administrateur
`ANNULER_REEMETTRE`, les triggers actifs, et cinq cas annulés séparément :

| Cas | Facture corrigée | Net global | Commission globale HT | Portée |
| --- | --- | --- | --- | --- |
| Heures seules, 4 h → 3 h à 20 €/h | 60 € | 160 € | 21 € | Caractérisation historique incohérente, **pas une validation métier** |
| Finale, 4 h à 18 €/h | 72 € | 72 € | 10,80 € | Préserver le chemin final |
| Hebdomadaire, 4 h à 18 €/h | 72 € | 144 € | 21,60 € | Corriger le double delta |
| Hebdomadaire, 4 h à 22 €/h | 88 € | 176 € | 26,40 € | Hausse symétrique |
| Payload UI : heures 4 et taux 18 transmis ensemble | 72 € | 144 € | 21,60 € | Même quantité, présence synthétique requise |

Le job [110304796369](https://github.com/Gabpcd/JJJJJ/actions/runs/36842541235/job/110304796369),
au commit `6f0160b6f7f8c3c0080174fa2da39c11748f6ac0`, a traversé les deux premiers
cas puis atteint le même rouge hebdomadaire. Il caractérise donc réellement
les heures seules et la finale avant correctif. Les jobs intermédiaires
`110302070404` et `110303315001` avaient arrêté le cas final sur une normalisation
bénigne : l’UPDATE de liaison de commission remet `taux_rist_plafonne` de NULL
à 20 sans activer de plafond. Le test vérifie explicitement ces valeurs, les
montants restant identiques, au lieu d’ignorer les modifications de mission.

**Écart restant confirmé :** les heures seules laissent un net de 160 € et une
commission de 21 €, qui ne correspond pas à 15 % de ce net. Le test de parité
empêche de dégrader ce chemin, mais ne valide pas son résultat comptable. Une
correction distincte reste nécessaire avant de déclarer ce parcours cohérent.
La suppression générique du delta aurait aussi retiré cet ajustement historique ;
elle n’a pas été publiée.

Le scénario final représente un historique de maintenance de 4 h entièrement
passées, sans prétendre prouver une clôture utilisateur. Les présences synthétiques
n’ont ni pointage, ni GPS, ni validation établissement. Les claims administrateur
ne prouvent ni login ni MFA ; les profils ne prouvent ni qualification ni mandat.
Les références PDF/XML sont fictives : aucun octet, objet Storage ou appel Edge.
Les éventuelles requêtes pg_net restent dans la transaction annulée ; leur
séquence technique peut avancer sans qu’une requête parte.

Les tests vérifient aussi TVA/TTC, les cinq agrégats avant/après pour le taux,
le refus non-service et le rejeu sans doublon. Un SELECT séparé contrôle le
catalogue, 22 compteurs et les résidus après succès ou échec. Le verrou staging
global est conservé. La voie sans migration exécute le seul témoin LIVE, sans
bootstrap/synchronisation ; la voie avec migration conserve les 48 suites SQL
historiques et ajoute F1. La validation du correctif par cette CI reste à obtenir.

La simulation frontend admin/parties (taux 18 et 22, cinq formats, rechargement)
est une preuve distincte ; elle ne remplace pas ce SQL réel ni une génération
documentaire cloud. Aucun avoir payé, remboursement, connexion native ou preuve
fournisseur n’est revendiqué par ce lot.
