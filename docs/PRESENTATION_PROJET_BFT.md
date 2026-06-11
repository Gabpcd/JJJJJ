# Présentation du projet — Bourse French Tech

> Texte structuré prêt à copier dans le formulaire Bpifrance.
> Catégorie : Innovation. SASU Jolene, Paris 6e, < 1 an.

## 1. L'équipe

**Gabrielle Picard** — fondatrice unique, présidente de Jolene SASU (créée il y a
3 mois, SIRET 10330574400015). Profil technique-produit : a conçu, développé et
déployé seule l'intégralité de la plateforme (frontend React, backend Supabase,
edge functions, intégrations Stripe Connect, API Chorus Pro, vérification
documentaire par IA). Double ancrage géographique : Paris 6e (siège) et Lorient
(56), les deux premiers départements du pilote.

## 2. Le problème

Le remplacement de personnel soignant en France repose encore sur le
téléphone, le fax et les agences d'intérim médicales :

- **Dizaines de milliers de postes vacants** dans les EHPAD, cliniques et
  hôpitaux ; absentéisme quotidien ; fermetures de cabinets l'été faute de
  remplaçants.
- **35-50 % de surcoût** par rapport au salariat direct pour les établissements
  qui passent par l'intérim.
- **La loi Rist (2021-2023)** a plafonné les tarifs de l'intérim médical sans
  créer d'alternative outillée — les établissements sont bloqués entre un
  plafond légal et une pénurie structurelle.
- **Les obligations employeur** (vérification d'inscription à l'Ordre, DPAE,
  contrat, déclarations) sont chronophages et source de non-conformité.

## 3. La solution : jolene.app

Jolene est une plateforme de mise en relation directe entre établissements de
santé et soignants (toutes professions, salariat + libéral), avec une chaîne
complète automatisée :

1. **L'établissement publie une mission** (poste, horaires, taux).
2. **Les soignants qualifiés sont notifiés** et postulent en 1 clic (ou swipent
   façon Hinge).
3. **Le contrat est généré et signé électroniquement** (CDD d'usage, vacation,
   ou contrat de remplacement libéral conforme au modèle de l'Ordre).
4. **Le soignant pointe par GPS**, l'établissement valide.
5. **La facturation et le paiement sont automatiques** (Stripe Connect pour le
   paiement direct, Chorus Pro pour le secteur public).

## 4. L'innovation (argumentaire instruction)

Innovation de **service ET de procédé**, avec 4 briques technologiques
propriétaires déjà en production :

- **Vérification documentaire par IA** : analyse instantanée des CNI, diplômes,
  RPPS, RCP, certificats d'arrêt — concordance d'identité, dates, cohérence
  croisée inter-documents. Le marché vérifie manuellement en 24-72 h.
- **Matching temps réel** : scoring multicritère (distance, tarif, fiabilité
  comportementale, urgence, fraîcheur) + mécanique d'engagement
  (swipe, streaks, badges) inédite sur ce marché.
- **Conformité automatisée de bout en bout** : contrats générés et signés
  (art. 1366 C. civ.), DPAE, plafonds loi Rist appliqués au calcul,
  facturation Chorus Pro, gestion contradictoire des rétrocessions libérales.
- **Fiabilité industrialisée** : détection de no-show en 30 min et re-staffing
  automatique, anti-fraude GPS au pointage, score comportemental contestable.

**Différenciation** : Hublo (diffusion de vacations, sans contrat/paiement),
Mediflash (salariat uniquement), agences d'intérim (non outillées). Jolene est
la seule chaîne complète multi-statuts.

## 5. Le marché

- **Cible primaire** : 10 207 EHPAD (CA staffing adressable > 1 Md €),
  35 000+ cabinets dentaires/médicaux pour le remplacement libéral,
  pharmacies d'officine (groupement Leader Santé intéressé).
- **Base de prospection construite** : 63 000 établissements (import FINESS),
  245 000 libéraux (import CNAM), 899 écoles de santé.
- **Modèle économique** : commission 15 % dégressive (paliers par volume),
  options premium (mise en avant, garantie remplacement), SaaS RH (post-PMF).

## 6. Programme de travail (12 mois, 105 k€)

| Lot | Contenu | Dépenses |
|---|---|---|
| L1 Expérimentation terrain | Pilote 2 départements (75/56) : 30 étabs, 300 soignants ; instrumentation, mesure fill-rate/time-to-fill, itérations | 45 k€ |
| L2 IA conformité v2 | Vérification arrêts de travail, attestations étudiantes, détection fraude documentaire renforcée ; évaluation robustesse | 30 k€ |
| L3 Application native | Industrialisation iOS/Android (builds Capacitor, parité native, tests dispositifs) | 15 k€ |
| L4 Matching v3 | Préférences temporelles apprises, taux d'acceptation établissements, re-ranking | 15 k€ |
| **Total** | | **105 k€** |

## 7. Plan de financement

| Source | Montant | Assiette |
|---|---|---|
| BFT Bpifrance (demandé) | 50 k€ (≤ 70 % faisabilité) | L2 + L3 |
| Innov'up Faisabilité IDF (demandé) | 30 k€ (70 %, SASU < 1 an) | L4 + L1 partiel |
| Prêt d'honneur PIE/RE (demandé) | 30 k€ (taux 0) | BFR + avances soignants |
| Fonds propres + CA A1 | 19 k€ | Complément |
| **Total** | **129 k€** | |

**Assiettes BFT et Innov'up distinctes** — pas de double financement d'une même
dépense. Le prêt d'honneur finance le fonds de roulement (hors assiette
subvention).

## 8. Jalons à 12 mois

- **M3** : 10 établissements pilotes actifs, 50 soignants inscrits, 1re mission terminée de bout en bout
- **M6** : 20 établissements, 150 soignants, fill-rate mesuré > 60 %, IA v2 déployée
- **M9** : app native publiée (App Store + Play Store), matching v3 en A/B test
- **M12** : 30 établissements actifs, 300 soignants, break-even mensuel atteint sur les commissions
