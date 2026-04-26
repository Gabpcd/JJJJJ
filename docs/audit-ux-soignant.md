# Audit UX Soignant — Findings essentiels

**Date** : 26 avril 2026
**Contexte** : test@jolene.app (auth.users existe, 0 row soignants, 0 missions)

---

## 1. Inventaire routes /soignant/*

### Routes actives (19 pages)

| Route | Page | Sidebar | Notes |
|-------|------|---------|-------|
| `/soignant/tableau-de-bord` | DashboardSoignant | Accueil | Page principale |
| `/soignant/profil` | ProfilSoignant | Parametres | 952 lignes |
| `/soignant/missions` | MissionsSoignant | Missions > Disponibles | 3 onglets |
| `/soignant/recherche-missions` | RechercheMissions | Missions > Recherche | Carte Leaflet |
| `/soignant/missions/:id` | DetailMissionSoignant | — | Fiche mission |
| `/soignant/missions/serie/:serieId` | DetailSerieSoignant | — | Serie missions |
| `/soignant/mes-documents` | MesDocuments | Activite > Documents | Tabs contrats/justificatifs |
| `/soignant/planning` | PlanningSoignant | Missions > Planning | Tabs planning/historique |
| `/soignant/presences` | PresencesSoignant | Activite > Presences | Pointage GPS |
| `/soignant/litiges` | LitigesContestationsSoignant | Activite > Litiges | Tabs litiges/reclamations |
| `/soignant/mes-gains` | MesGains | Factures & paiements | Bottom bar mobile |
| `/soignant/passer-en-liberal` | PasserEnLiberal | Conditionnel | Redirect si non eligible |
| `/soignant/messagerie` | PageMessagerie | Messagerie | Partage 3 roles |
| `/soignant/stripe-connect` | PageStripeConnect | — | Hors sidebar |
| `/soignant/mandat-facturation` | MandatFacturation | — | Hors sidebar |
| `/soignant/mes-factures-honoraires` | MesFacturesHonoraires | — | Hors sidebar |
| `/soignant/mes-avances` | MesAvances | — | Hors sidebar |
| `/soignant/charges` | ChargesSociales | — | Hors sidebar |
| `/soignant/exclusions` | ExclusionsSoignant | — | Hors sidebar |

### Routes redirections (7)

| Route ancienne | Redirige vers |
|---------------|---------------|
| `/soignant/documents` | `/soignant/mes-documents?tab=justificatifs` |
| `/soignant/contrats` | `/soignant/mes-documents?tab=contrats` |
| `/soignant/calendrier-sync` | `/soignant/planning` |
| `/soignant/historique-missions` | `/soignant/planning?tab=historique` |
| `/soignant/reclamations` | `/soignant/litiges?tab=reclamations` |

### Routes orphelines (accessibles mais hors sidebar, pas de CTA evident)

| Route | Page | Probleme |
|-------|------|----------|
| `/soignant/parcours-3200h` | Parcours3200h | Ancienne page, remplacee par PasserEnLiberal mais encore routee |
| `/soignant/prevoyance` | PrevoyanceSoignant | Hors sidebar, accessible seulement via Dashboard parcours |
| `/soignant/attestation-heures` | AttestationHeures | Hors sidebar |
| `/soignant/fiabilite` | FiabiliteSoignant | Hors sidebar |
| `/soignant/conformite` | ConformiteSoignant | Hors sidebar |
| `/soignant/notifications` | PageNotifications | Hors sidebar (cloche suffit) |
| `/soignant/parrainage` | PageParrainage | Hors sidebar |
| `/soignant/premium` | PremiumSoignant | Hors sidebar |

---

## 2. Bug pharmacien fantome

### Cause exacte

**Fichier** : `src/pages/DashboardSoignant.tsx`, lignes 544-597

```
Onglet "Parcours" du dashboard :

if (type_exercice === 'LIBERAL')
  → "Vous exercez deja en liberal"
else if (profession && estEligibleLiberal(profession))
  → Jauge 3200h + parcours
else
  → "💊 Vous exercez en pharmacie d'officine"  ← BUG
```

Le `else` final (ligne 592-596) est un fallback hardcode qui assume que tout soignant non-eligible-liberal est pharmacien. Quand `profession` est NULL (pas de RPPS verifie), la condition `profession && estEligibleLiberal(profession)` est false (short-circuit sur null), donc le code tombe dans le fallback pharmacien.

### Fix propose

Remplacer le bloc else (lignes 592-596) par :

```tsx
) : soignantWithCounts.profession ? (
  <div className="card-base text-center py-8">
    <p className="text-sm text-muted-foreground">
      Votre profession ({getLabelProfession(soignantWithCounts.profession)})
      n'est pas eligible a l'exercice liberal via Jolene.
    </p>
  </div>
) : (
  <div className="card-base text-center py-8">
    <p className="text-sm text-muted-foreground">
      Verifiez votre RPPS pour debloquer votre parcours professionnel.
    </p>
    <button onClick={() => navigate('/soignant/profil')} className="btn-primary mt-3 text-sm">
      Completer mon profil
    </button>
  </div>
)}
```

---

## 3. Crash .single() — 9 pages affectees

`.single()` throw une erreur Supabase quand 0 rows sont retournees. Avec test@jolene.app (0 rows dans `soignants`), ces pages crashent silencieusement ou affichent l'ErrorBoundary.

| Page | Fichier | Ligne | Fix |
|------|---------|-------|-----|
| PresencesSoignant | PresencesSoignant.tsx | 44 | `.maybeSingle()` |
| FiabiliteSoignant | FiabiliteSoignant.tsx | 29 | `.maybeSingle()` |
| ChargesSociales | ChargesSociales.tsx | 92 | `.maybeSingle()` |
| PrevoyanceSoignant | PrevoyanceSoignant.tsx | 29 | `.maybeSingle()` |
| PageStripeConnect | PageStripeConnect.tsx | 64 | `.maybeSingle()` |
| MesGains | MesGains.tsx | 58 | `.maybeSingle()` |
| PasserEnLiberal | PasserEnLiberal.tsx | 26 | `.maybeSingle()` |
| Parcours3200h | Parcours3200h.tsx | 29 | `.maybeSingle()` + guard profession null |
| DocumentsSoignant | DocumentsSoignant.tsx | 30 | Deja fixe `.maybeSingle()` |

**Impact** : toute page soignant accessible par un user sans row `soignants` crashe.

**Fix global** : rechercher/remplacer tous `.single()` sur la table `soignants` par `.maybeSingle()` dans les fichiers soignant.

---

## 4. Triplon "Completez votre profil" sur Dashboard

Le Dashboard affiche 3 composants redondants pour la meme intention :

| Composant | Ce qu'il affiche | Position |
|-----------|-----------------|----------|
| `BandeauProfilIncomplet` | "Profil incomplet" + CTA profil | Tout en haut (si profession null) |
| `OnboardingGuide` | 5 etapes d'onboarding | Sous le bandeau |
| `BarreCompletionProfil` | Jauge X% + 5 criteres | Sous l'onboarding |

**Probleme** : l'utilisateur voit 3 fois le message "completez votre profil" avec des formats differents et des criteres potentiellement incoherents.

**Recommandation R2** : fusionner en un seul composant `OnboardingStepper` avec une checklist unifiee et une jauge unique.

---

## 5. Autres incoherences detectees

### 5a. ChargesSociales accessible a tous
La page `/soignant/charges` affiche "Mes charges sociales liberales" meme pour un salarie ou un profil sans profession. Pas de guard `type_exercice === 'LIBERAL'`.

### 5b. Parcours3200h encore route
`/soignant/parcours-3200h` pointe vers l'ancienne page Parcours3200h qui utilise `getRegleInstallation(profession)` — crash si profession null. Cette route devrait etre un redirect vers `/soignant/passer-en-liberal`.

### 5c. Prevoyance accessible sans guard
`/soignant/prevoyance` est accessible par URL directe mais n'est plus dans la sidebar. Pas de redirect ni de guard profession.

### 5d. Documents "tous a jour" quand profession null
Fixe dans le commit precedent : `completionDocs` retourne 0% au lieu de 100% quand profession null. Mais la jauge "2 documents manquants" ne s'affiche pas car `docsRequis` est vide quand profession null.

### 5e. RPC dashboard retourne profil null sans row soignants
Le `fn_dashboard_soignant_complet` retourne `profil: null` quand aucune row soignants n'existe. Le fallback `emptySoignant` dans DashboardSoignant.tsx masque le probleme mais les valeurs par defaut (profession null, type_exercice 'SALARIE') causent des affichages incoherents.

---

## 6. Plan de refonte R2/R3/R4

### R2 — Fix crash + coherence profil (2-3h)

**Perimetre** :
1. Remplacer 8x `.single()` → `.maybeSingle()` dans les 8 pages listees
2. Fix bug pharmacien fantome (DashboardSoignant.tsx L592-596)
3. Redirect `/soignant/parcours-3200h` → `/soignant/passer-en-liberal`
4. Guard `type_exercice === 'LIBERAL'` sur ChargesSociales
5. Guard profession sur PrevoyanceSoignant

**Fichiers** : 10 pages soignant + App.tsx
**Dependances** : aucune
**Risque** : faible (corrections ponctuelles)

### R3 — Dashboard refondu (4-5h)

**Perimetre** :
1. Fusionner BandeauProfilIncomplet + OnboardingGuide + BarreCompletionProfil en un seul `OnboardingStepper`
2. Checklist unifiee : RPPS verifie → Docs obligatoires uploades → Adresse → Telephone → Stripe Connect (si liberal)
3. Supprimer l'onglet "Parcours" du dashboard (redondant avec page PasserEnLiberal)
4. Section "Missions pour vous" en premier (apres le stepper)
5. Stats simplifiees (heures, score fiabilite, gains mois)

**Fichiers** : DashboardSoignant.tsx + nouveau OnboardingStepper.tsx
**Dependances** : R2 (les crashs doivent etre fixes avant)
**Risque** : moyen (refonte visuelle importante)

### R4 — Page Parametres soignant tabule (3-4h)

**Perimetre** :
1. Creer `/soignant/parametres` avec 4-5 tabs (comme cote etab)
2. Tab 1 : Profil (ProfilSoignant extrait en Content)
3. Tab 2 : Stripe Connect (si LIBERAL/MIXTE)
4. Tab 3 : Fiabilite + Conformite (fusionnes)
5. Tab 4 : Parrainage + Exclusions + Premium
6. Redirects anciennes routes → `/soignant/parametres?tab=X`

**Fichiers** : nouveau Parametres.tsx + extractions Content de 6 pages
**Dependances** : R2
**Risque** : faible (meme pattern que refonte etab Phase C)

### R5 (optionnel) — Pages finances unifiees (2-3h)

**Perimetre** :
1. Page `/soignant/factures` unifiee avec tabs conditionnels (spec Phase B de la refonte soignant initiale)
2. Fusionner MesGains + MesFacturesHonoraires + MandatFacturation + MesAvances + ChargesSociales
3. Tabs conditionnels selon type_exercice

**Dependances** : R2 + R4
**Risque** : moyen

---

## 7. Patterns herites de la refonte etab

| Pattern | Utilise cote etab | A appliquer cote soignant |
|---------|------------------|--------------------------|
| Extraction Content + wrapper LayoutApp | ProfilEtablissementContent, APIContent, etc. | ProfilSoignantContent, etc. pour tabs Parametres |
| Page tabulee avec ?tab=X | Parametres.tsx etab (5 tabs) | Parametres soignant (4-5 tabs) |
| Redirect 301 anciennes routes | 6 redirects etab | Idem pour routes orphelines soignant |
| BandeauProfilIncomplet | Cree pour soignant | Deja en place, a fusionner avec OnboardingGuide |
| SectionPlanning calendar | DashboardEtablissement | Reutilisable sur DashboardSoignant (vue planning missions assignees) |
| estEligibleLiberal() | Sidebar + PasserEnLiberal | A utiliser partout au lieu de PROFESSIONS_NON_LIBERAL.includes() |
| createPortal pour modals | PanneauNotifications | Pattern a generaliser si z-index issues |

---

*Audit genere le 26 avril 2026. Base pour sessions R2/R3/R4.*
