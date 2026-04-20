# Smoke-test visuel — tampons ANNULEE / REMPLACEE (CP-LITIGES-7a FIX 7)

Ce dossier centralise les captures d'écran du rendu PDF pour les statuts
`ANNULEE` et `REMPLACEE`. Le but : détecter visuellement toute régression
sur la position, la couleur, la rotation ou la transparence du tampon.

## Prérequis

- Accès à un environnement Supabase (dev ou staging).
- `SUPABASE_SERVICE_ROLE_KEY` exporté dans l'env.
- Une facture `factures_honoraires` existante avec PDF déjà généré.

## Procédure

### Cas 1 — statut ANNULEE

```sql
-- 1. Identifier une facture émise
SELECT id, numero_facture FROM public.factures_honoraires
 WHERE statut = 'EMISE' ORDER BY cree_le DESC LIMIT 1;
```

```sql
-- 2. Forcer en ANNULEE + flag regen (hors admin RPC pour smoke-test rapide)
UPDATE public.factures_honoraires
   SET statut = 'ANNULEE', pdf_a_regenerer = TRUE
 WHERE id = '<facture_id>';
```

```bash
# 3. Déclencher la regen
curl -X POST "$SUPABASE_URL/functions/v1/generate-invoice" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"facture_id": "<facture_id>", "service_role_reason": "ops_test_fix7_annulee"}'
```

```sql
-- 4. Récupérer le chemin du PDF
SELECT pdf_s3_key FROM public.factures_honoraires WHERE id = '<facture_id>';
```

Télécharger le PDF depuis Supabase Storage (`jolene-documents` bucket) et
sauvegarder une capture PNG de la première page sous :
`docs/tests-annulation/annulee-<numero>.png`.

### Cas 2 — statut REMPLACEE

Même procédure avec `statut = 'REMPLACEE'`. Au préalable, assurer qu'une
facture successeur existe (via `facture_precedente_id`) sinon le sous-titre
`par facture <numero>` sera absent :

```sql
-- Simuler successeur
INSERT INTO public.factures_honoraires (
  soignant_id, etablissement_id, numero_facture,
  montant_ht, montant_tva, montant_ttc,
  facture_precedente_id, statut
) SELECT soignant_id, etablissement_id,
         'FH-TEST-SUCC-' || substring(gen_random_uuid()::text, 1, 8),
         montant_ht, montant_tva, montant_ttc,
         id, 'EMISE'
  FROM public.factures_honoraires WHERE id = '<facture_id>';

UPDATE public.factures_honoraires
   SET statut = 'REMPLACEE', pdf_a_regenerer = TRUE
 WHERE id = '<facture_id>';
```

Sauvegarder : `docs/tests-annulation/remplacee-<numero>.png`.

## Critères de validation

- Tampon visible **par-dessus** le contenu (pas en arrière-plan).
- Rotation diagonale visible (+30° environ).
- Couleur : rouge vif (ANNULEE) ou orange (REMPLACEE).
- Opacité suffisante pour rester lisible mais permettre de lire le texte
  de la facture en dessous.
- Sous-titre `par facture <numero>` aligné sous le tampon principal pour
  REMPLACEE.
- Mention orange `Facture rectificative remplacee par <numero> (art. L441-9 C. com.)`
  visible dans le corps (en-tête) pour REMPLACEE.
- Pas de tampon pour `BROUILLON`, `EMISE`, `PAYEE`, `FACTORISEE`, `EN_RETARD`.

## Nettoyage

```sql
-- Rétablir statuts d'origine
UPDATE public.factures_honoraires SET statut = 'EMISE' WHERE id IN (...);
DELETE FROM public.factures_honoraires WHERE numero_facture LIKE 'FH-TEST-SUCC-%';
```
