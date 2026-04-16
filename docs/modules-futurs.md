# Modules futurs — Structures en sommeil

> Dernière mise à jour : 2026-04-16

## Tables en sommeil

| Table | Statut | Description | Décision |
|---|---|---|---|
| `shifts` | DEPRECATED | Module planning par équipes. 0 lignes en prod. | Conserver sans modifier. Pas dans le périmètre multi-créneaux. |
| `shift_affectations` | DEPRECATED | Affectations soignant ↔ shift ↔ mission. 0 lignes. | Idem. Dépend de `shifts`. |

## Colonnes en sommeil (avant migration multi-créneaux)

| Colonne | Table | Ancien statut | Migration |
|---|---|---|---|
| `serie_id` | `missions` | Nullable, jamais peuplé (0/268) | Rendu fonctionnel : FK → `mission_series`. |

## Notes

- Le système `shifts` pourrait devenir un module de planning RH indépendant (planning d'équipe, rotation, roulement) distinct du modèle mission marketplace. Si ce besoin émerge, il faudra un audit dédié.
- Ne pas réutiliser `shifts` comme base pour `mission_creneaux` — les deux concepts sont différents (planning prévisionnel vs créneaux contractuels d'une mission).
