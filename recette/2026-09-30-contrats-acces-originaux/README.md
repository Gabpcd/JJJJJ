# Contrats : accès canonique et conservation de l’original

Base examinée : `58fda7df712cbc5637e41a9dc06a639288a05554`. Recette locale du 30 septembre 2026. Pas de mutation production, de document personnel, de SMS réel, de livraison mobile ni de modification du brouillon établissement v1.1/DPA.

## Défaut et résultat

L’Edge acceptait directement un propriétaire Auth encore présent même après fermeture de son profil, et régénérait un contrat déjà signé depuis les données/templates courants. La RPC autorisait aussi les membres sans `lecture_contrats`.

Tous les utilisateurs passent maintenant par `fn_contrat_storage_path`, qui exige le compte actif, le tenant canonique et la permission de lecture (ou le soignant concerné / administrateur valide). La décision est renouvelée avant/après Storage ; aucun lien n’est retourné après révocation. Le bypass système historique compare exactement la clé configurée.

Un document déjà stocké ou signé, même partiellement, est relu sans génération ni écrasement de son hash. Un original absent/incomplet produit une erreur explicite. Le premier rendu utilise un nom unique et une mise à jour conditionnelle : une signature, un rendu ou un changement de parties concurrent empêche la publication du résultat devenu obsolète.

L’écran conserve le contenu historique et ne remplace pas un original signé manquant par un nouveau template. La recette a également révélé que le bouton OTP restait actif avec un document indisponible : OTP et canvas exigent désormais le document figé affiché. Un changement de disponibilité réinitialise la session OTP et ignore sa réponse tardive.

## Preuves

| Vérification | Résultat et portée |
| --- | --- |
| Edge réelle transpilée, clients simulés, réseau interdit | 31 tests verts : refus Auth/garde/compte fermé/permission, premier rendu y compris HTML initial prérempli, relecture signée ou partiellement signée, hash des octets, courses signature/rendu/affectation, révocation pendant upload/URL, erreurs Storage/SQL, idempotence et service exact. |
| UI unitaire | 15 tests verts : sélection de l’original, continuité page et OTP, refus de signer sans document et réponse OTP tardive. |
| Manifeste d’authentification Edge | 7 tests verts. |
| Frontend nouveau scénario | 10/10 verts : soignant et établissement dans iPhone, Android, iPad portrait/paysage, ordinateur ; original signé, téléchargement HTML fictif contenant exactement le contenu historique, reload, original partiellement signé manquant, refus 403 de rendu, reprise, absence de lecture après refus. ARIA et captures enregistrés. |
| Non-régression OTP existante | 4/5 verts au premier passage ; iPad paysage a manqué le message « Code incorrect » sans appel RPC de signature dans la trace. Rejeu identique ciblé vert (1/1), sans modification ni relâchement d’assertion. La trace initiale est conservée ; son diagnostic a ensuite identifié une notification superposée au clic. Voir `otp-inline-diagnostic.md` pour la correction du formulaire et sa recette. Session expirée, réseau, code invalide/expiré puis une signature unique exercés. |
| Compilation | `tsc -b` et build Vite web verts ; avertissements de taille des chunks existants. |
| Garde-fous dépôt | 17/17 verts. |
| SQL complet | Migration et recette parsées par `pglast.parse_sql` ET `parse_plpgsql` (3 instructions SQL / 1 corps PLpgSQL chacune). Pas de serveur PostgreSQL local : exécution réelle de la recette restant à obtenir en CI. |

La nouvelle recette SQL est raccordée à `validate-pr.yml`, dans la transaction des migrations PR avec rollback. Fixtures synthétiques isolées et sentinelle de rollback interne : propriétaire, soignant, RH, lecture seule, groupe ; refus tiers, autre tenant, pointage, permission révoquée, membre inactif, Auth suspendu/supprimé, profils publics fermés avec Auth vivant et tenant fermé. Aucun objet Storage n’est créé par cette recette.

### Contrôles LIVE en lecture seule

Définition/ACL de `fn_contrat_storage_path` relues avant migration, puis gardes `fn_compte_auth_actif`, `mon_etablissement_id`, `fn_a_permission_etablissement` et fonctions d’intégrité.

`fn_finaliser_attribution_mission` insère le HTML initial et le statut sans hash, chemin ou date de rendu ; ces trois colonnes ont toutes un défaut NULL. Les triggers d’intégrité/sanitisation n’en préremplissent pas la valeur. Le premier rendu reste donc possible.

Aucun corps de fonction LIVE (tous schémas) ni tâche `cron.job` ne référence `generate-contrat-mission-pdf`. Le seul appel concret repéré dans le dépôt est celui de l’interface authentifiée. Aucune clé Vault n’a été lue ni aucun mécanisme d’authentification `sb_secret_*` inventé ; le commentaire ancien sur un trigger candidature a été corrigé.

## Reproduire

```sh
./node_modules/.bin/tsc -b --pretty false
./node_modules/.bin/vitest run tests/admin/security/contrat-original-acces.test.ts src/lib/contratMissionUi.test.ts src/pages/ContratMission.continuite.test.tsx src/components/SignerContratOtp.continuite.test.tsx tests/admin/security/edge-auth-manifest.test.ts
npm run test:guards
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_PUBLISHABLE_KEY=simulation-public-key npm run build
npm run preview -- --host 127.0.0.1 --port 18457 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18457 RECETTE_RESULTS_DIR=/private/tmp/jolene-contrats-ui-results-cinq-formats ./node_modules/.bin/playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-contrats-originaux.spec.ts
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18457 RECETTE_RESULTS_DIR=/private/tmp/jolene-contrats-ui-otp-regression ./node_modules/.bin/playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-mission.spec.ts --grep 'signature OTP'
```

Preuves locales : `/private/tmp/jolene-contrats-vitest.txt`, `jolene-contrats-manifest.txt`, `jolene-contrats-guards.txt`, `jolene-contrats-tsc.txt`, `jolene-contrats-build.txt`, `jolene-contrats-ui-cinq-formats.txt`, `jolene-contrats-ui-otp.txt`, `jolene-contrats-ui-otp-reprise.txt` (tous sous `/private/tmp`). ARIA représentatif conservé dans ce dossier ; résultats complets/captures fictives sous `/private/tmp/jolene-contrats-ui-results-cinq-formats`.

## Limites et revue restante

- Les échanges réseau du navigateur sont simulés. L’Edge est exécutée localement avec doubles de clients. Les contrôles LIVE sont des lectures du catalogue, pas une recette réelle Storage/OTP. Aucun appareil physique n’a été utilisé.
- La recette SQL doit réussir dans la CI de l’intégration avant merge. Revue indépendante et déploiement contrôlé restent à effectuer. Pour la preview humaine : vérifier le contenu historique dans `/contrat/:id`, l’état original absent avec actions désactivées, puis erreur/reprise d’un premier rendu.
- Un upload réussi dont la publication SQL échoue peut laisser un objet sans référence. Il n’est pas supprimé automatiquement dans ce correctif, afin de ne pas effacer une preuve au statut incertain. Pas de nouvelle purge/rétention.
- Les URLs déjà délivrées conservent leur TTL existant (24 h pour cette Edge). Les nouveaux liens sont refusés après révocation ; aucune révocation rétroactive d’un lien signé n’est promise.
- Le téléchargement de l’écran reste un HTML enveloppé à partir du contenu serveur préservé ; il ne constitue pas encore un export octet pour octet du fichier Storage. L’Edge relit l’objet stocké existant. Ce lot ne prétend pas livrer l’export documentaire complet.
