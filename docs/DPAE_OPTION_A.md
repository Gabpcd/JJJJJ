# DPAE — Déclaration Préalable à l'Embauche

> Sprint 1 PR 6 + Sprint 2 PR 2 : workflow Option A (manuel assisté).
> Référence légale : art. R1221-2 Code du travail.

## Obligation légale

L'établissement employeur doit déclarer chaque nouvel embauché CDD/CDDU auprès
de l'URSSAF avant la prise de poste effective (max 8 jours avant). La DPAE
remplace simultanément :

- Déclaration unique d'embauche
- Demande d'immatriculation salarié
- Adhésion service santé travail
- Déclaration arrêt de travail

Sanction défaut DPAE : 300× SMIC horaire / salarié non déclaré + travail dissimulé.

**Contrats non concernés** : libéral (relation B2B), bénévolat, stage. Jolene
détecte automatiquement et n'affiche pas le module DPAE pour les libéraux.

## Approche Jolene — Option A (actuelle, lancement)

```
1. Soignant complète son profil DPAE (sexe, lieu naissance, nationalité, NIR)
   via la section src/components/profil-soignant/SectionDpaeIdentite.tsx
2. Étab signe le contrat CDD
3. Composant DPAEStatus.tsx s'affiche :
   - Bouton "Générer DPAE pré-remplie"
   - Appel RPC fn_generer_donnees_dpae(contrat_id)
   - Affichage payload formaté (établissement, salarié, embauche)
   - Champs manquants flaggés "⚠ À COMPLÉTER MANUELLEMENT"
4. Étab clique "Copier" → presse-papier
5. Étab ouvre net-entreprises.fr (lien fourni)
6. Étab colle / saisit dans le formulaire URSSAF
7. URSSAF retourne un numéro DPAE
8. Étab saisit ce numéro dans le champ "Numéro DPAE URSSAF"
9. Appel fn_enregistrer_numero_dpae → contrats_mission.dpae_numero
   + contrats_mission.dpae_effectuee = true
10. DPAEStatus affiche "✅ DPAE déclarée — n° XYZ"
```

## Schéma DPAE complet (PR 2 Sprint 2)

Colonnes ajoutées à `soignants` :

| Colonne | Type | Default | Note |
|---|---|---|---|
| `sexe` | text | NULL | CHECK ∈ ('M', 'F') |
| `lieu_naissance_commune` | text | NULL | Requis si pays = France |
| `lieu_naissance_departement` | text | NULL | 01-95, 2A, 2B, 971-976 |
| `pays_naissance` | text | 'France' | |
| `nationalite` | text | 'Française' | |

Validation RPC `fn_maj_infos_dpae` :
- sexe ∈ {M, F} ou NULL
- département validé par regex `^(0[1-9]|[1-8][0-9]|9[0-5]|2A|2B|97[1-6])$`

Helper RPC `fn_soignant_dpae_complet(soignant_id)` :
```json
{
  "complet": false,
  "manquants": ["sexe", "lieu_naissance_commune", "numero_securite_sociale"]
}
```

## Option B (future, Sprint 3+)

API tiers déclarant URSSAF directe — démarche d'agrément complexe (3-6 mois).
Permettrait à Jolene de soumettre la DPAE pour le compte de l'étab et de
récupérer le numéro automatiquement.

**Pas dans le scope launch** — l'Option A est légalement parfaitement valide
(c'est l'étab qui déclare via son compte URSSAF) et gère 90% du friction.

## Format payload `fn_generer_donnees_dpae`

```json
{
  "success": true,
  "contrat_id": "...",
  "type_contrat": "CDD",
  "etablissement": {
    "nom": "...", "siret": "...", "naf": "...",
    "adresse_rue": "...", "adresse_ville": "...", "adresse_code_postal": "...",
    "telephone": "...", "email": "...",
    "organisme_protection_sociale": "URSSAF"
  },
  "salarie": {
    "nom": "...", "prenom": "...", "sexe": "M",
    "date_naissance": "1985-06-15",
    "lieu_naissance_commune": "Lyon",
    "lieu_naissance_departement": "69",
    "pays_naissance": "France",
    "nationalite": "Française",
    "numero_securite_sociale": "...",
    "adresse_rue": "...", "adresse_code_postal": "...", "adresse_ville": "...",
    "profession": "MEDECIN",
    "champs_a_completer_sur_net_entreprises": [
      // Liste auto-générée à partir des champs NULL (cf. PR 2 Sprint 2)
    ]
  },
  "embauche": {
    "date_prevue": "2026-06-01T08:00",
    "heure_prevue": "08:00",
    "date_fin": "2026-06-14T20:00",
    "type_contrat": "CDD",
    "duree_heures_prevues": 80
  },
  "urssaf_url": "https://www.net-entreprises.fr/declaration-prealable-embauche/",
  "note": "..."
}
```

## Erreurs courantes

- **`Numéro NIR manquant`** : le soignant n'a pas renseigné son n° de sécurité sociale.
  Le DPAE est techniquement possible sans (l'URSSAF retourne le NIR), mais c'est
  plus rapide si on l'a déjà.
- **`Sexe manquant`** : obligatoire DPAE. Soignant doit compléter via
  `SectionDpaeIdentite`.
- **`Lieu de naissance manquant`** : si naissance en France, commune + dept obligatoires.
  Si naissance étrangère, seul le pays est requis.
