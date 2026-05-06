# Tests manuels CP-C-1 — Déclaration paiement soignant (E12 + E13)

Scope : **2 tickets RÉSOLUS** (E12 déclaration paiement étab + E13 audit données existantes). 1er CP de la Sub-PR C paiement salarié.

## Prérequis

- ✅ Migration `20260420150000_cp_c_1_declarer_paiement_v2` appliquée (vérifié via MCP).
- ✅ Template `PAIEMENT_SOIGNANT_DECLARE` ajouté à `send-email/index.ts`.
- ✅ UI `ObligationsFinancieres.tsx` refondue avec Dialog + attestation.
- 🟡 Workflow GitHub Actions post-push CP-C-1 : déploie send-email nouvelle version.

## Scénarios automatisables (SQL)

```bash
psql "$DB_URL" -f tests/paiements/cp-c-1.test.sql
```

Couvre :
- [1.1] Signature RPC v2 inclut `p_attestation_sur_l_honneur`
- [2.1] Attestation FALSE → error `ATTESTATION_REQUISE` (rejet avant autres checks)
- [3.1] Méthode `ESPECES` → rejetée (enum strict, retirée)
- [4.1] 4 méthodes valides acceptées : VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES
- [5] Double déclaration → checklist manuelle (nécessite contexte JWT étab)

## Scénarios end-to-end (manuels via UI)

### A. Nominal — déclaration réussie

1. Connexion étab sur `/etablissement/obligations-financieres`
2. Voir mission TERMINEE SALARIE avec bouton "Déclarer un paiement"
3. Clic → Dialog s'ouvre avec :
   - Rappel : intitulé mission + nom soignant
   - Champ montant (prérempli avec `net_a_payer` estimé)
   - Select méthode (VIREMENT/CHEQUE/BULLETIN_PAIE/NOTE_HONORAIRES)
   - Input référence (obligatoire sauf BULLETIN_PAIE)
   - Date picker (default today, max today)
   - **Checkbox attestation** avec texte complet
4. Remplir tous les champs **sans cocher** attestation → bouton "Valider" désactivé
5. Cocher attestation → bouton actif
6. Valider → toast "Paiement déclaré — le soignant a été notifié"
7. **Vérifications** :
   - [ ] Ligne insérée dans `paiements_soignant` : statut=DECLARE, confirme_par_etablissement=TRUE, montant/methode/reference/date corrects
   - [ ] `journaux_audit` entrée `PAIEMENT_SOIGNANT_DECLARE_ETAB` avec `attestation_sur_l_honneur=TRUE` + timestamp
   - [ ] Notification in-app soignant "Paiement déclaré"
   - [ ] Email `PAIEMENT_SOIGNANT_DECLARE` reçu par le soignant (subject : "Votre établissement a déclaré vous avoir payé X€ — confirmez")
   - [ ] Liste ObligationsFinancieres se rafraîchit (mission disparaît des lignes "à payer")

### B. Attestation non cochée — bloqué UI

1. Ouvrir Dialog, remplir tous les champs valides
2. **Ne pas cocher** attestation
3. **Vérifier** : bouton "Valider la déclaration" reste désactivé (grisé)
4. Cocher → bouton devient actif

### C. Double déclaration — erreur

1. Déclaration nominale sur mission M (scénario A)
2. Retour sur ObligationsFinancieres → la mission M ne doit plus être listée (commission à payer reste, mais paiement soignant disparaît). Sinon retenter :
3. Ouvrir Dialog de nouveau sur mission M (via admin / force UI)
4. Valider
5. **Vérifier** : toast erreur "Paiement déjà déclaré pour cette mission"

### D. Soignant Stripe Connect actif — redirection

1. Mission SALARIE assignée à soignant LIBERAL avec Stripe Connect actif
2. Clic "Déclarer un paiement"
3. Rempli + valider
4. **Vérifier** :
   - [ ] Toast info "Ce soignant a Stripe Connect actif — utilisez le paiement Stripe"
   - [ ] Dialog se ferme
   - [ ] UI propose flow Connect (bouton "Payer via Stripe" visible)

### E. Méthode BULLETIN_PAIE — référence optionnelle

1. Select méthode = BULLETIN_PAIE
2. **Vérifier** : label champ référence devient "(optionnelle)"
3. Laisser vide → bouton actif si attestation cochée + montant OK
4. Valider → succès (RPC accepte référence vide pour BULLETIN_PAIE)

### F. Date paiement future — rejetée

1. Choisir date_paiement demain
2. **Vérifier** : l'input `max={today}` bloque via le widget date picker HTML5
3. Si bypass (via console) : RPC retourne "La date de paiement ne peut pas être dans le futur"

### G. Confirmation côté soignant (flow existant, régression à valider)

1. Soignant reçoit email + ouvre Jolene
2. Bandeau "Paiement déclaré — confirmer la réception" visible sur dashboard
3. Clic "Confirmer" → appelle `fn_confirmer_paiement_soignant`
4. **Vérifier** : `paiements_soignant.statut` passe DECLARE → CONFIRME + `confirme_par_soignant=TRUE`

## Vérifications prod post-déploiement

```sql
-- Dernières déclarations post-CP-C-1
SELECT id, mission_id, statut, methode, montant_net, date_paiement, confirme_par_etablissement_le, cree_le
FROM public.paiements_soignant
WHERE cree_le > NOW() - INTERVAL '1 hour'
ORDER BY cree_le DESC;

-- Audit entries attestation
SELECT id, acteur_id, action, id_ressource, details->>'attestation_sur_l_honneur' AS attestation,
       details->>'methode' AS methode, details->>'montant_net' AS montant, cree_le
FROM public.journaux_audit
WHERE action = 'PAIEMENT_SOIGNANT_DECLARE_ETAB'
ORDER BY cree_le DESC
LIMIT 10;
```

## Tickets clôturés

- **E12** (P0, 12h → 12h) : Déclaration paiement soignant avec attestation sur l'honneur + audit + email → **RÉSOLU**
- **E13** (P1, 2h → 0h) : Audit source historique 14 lignes paiements_soignant existantes → **RÉSOLU sans nettoyage** (audit confirmé : mix seed + usage réel minime, acceptable)

## Décisions architecturales

1. **Rétrocompat RPC** (Option 2) : param `p_attestation_sur_l_honneur BOOLEAN DEFAULT FALSE` + validation `IF NOT p_attestation → RAISE error`. Pas de v2 parallèle.
2. **ESPECES retiré** de l'enum méthode (illégal >1500€ salaires entre pros, traçabilité URSSAF).
3. **Attestation obligatoire** : responsabilité URSSAF + article 441-1 Code pénal (déclaration frauduleuse).
4. **Audit RGPD systématique** : chaque déclaration trace `attestation_sur_l_honneur=TRUE` + timestamp pour défense en cas de litige URSSAF.
5. **Email soignant non-bloquant** : si send-email échoue, la déclaration reste valide, seule la notif email est ratée (notif in-app toujours émise par RPC).

## Prochaines étapes CP-C

- **CP-C-2** (12h) : Templates email + cron relances (E2, E6, E11)
- **CP-C-3** (14h) : Blocage auto + unfreeze (E1, E7, E9)
- **CP-C-4** (14h) : EXPIREE enum + seuils (E5, E8, E10)
- **CP-C-5** (30h) : Chorus Pro complet (E15) — prérequis secrets PISTE
