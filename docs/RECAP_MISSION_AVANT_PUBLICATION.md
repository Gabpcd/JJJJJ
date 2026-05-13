# Modal récap mission avant publication (Sprint 7)

> Fix **P1-4** audit Sprint 5. Affiche un récap structuré avant le submit final du formulaire mission étab.

## Composant

`ModalRecapMission` (`src/components/mission/ModalRecapMission.tsx`).

## Sections

1. **Infos mission** : intitulé, profession, dates, durée, service, type contrat, préférence
2. **Coût estimé** : taux horaire / brut soignant / commission Jolene (12% par défaut) / total HT à charge étab
3. **Restrictions appliquées** : Mediflash (jurisprudence CE 11/02/2025), majorations CCN potentielles
4. **Pointage anti-triche Sprint 4.5** : tolérance GPS, QR auto, alertes possibles

## Workflow

```
Étab remplit FormulaireMission
  ↓
Clique "📤 Publier la mission"
  ↓
handleSubmit() valide les champs requis
  ↓
Au lieu de submit direct → setShowRecap(true)
  ↓
ModalRecapMission affichée avec données live
  ↓
2 boutons :
  - "← Modifier" → fermer modal, retour au form
  - "📤 Publier" → handlePublierConfirme() → fn_creer_mission
```

## Pas de migration DB

Composant 100% UI. Réutilise les RPCs existantes (`fn_creer_mission`).

## Tests à venir

- Test playwright étab : remplir form → clic publier → modal apparaît → confirmer → mission créée
- Test calcul coûts : 8h × 25€ + 12% = 224€ total
