import React, { useState } from 'react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Info, ChevronDown, ChevronRight, AlertTriangle, Ban } from 'lucide-react';
import { useModeExerciceMission } from '@/hooks/useModeExerciceMission';
import { resoudreTypeContratFinancier } from '@/lib/financeMission';

/**
 * DecompositionFinanciere — affichage selon type_contrat_applique
 *
 * Règles issues de docs/logique-paiements-v1.md :
 *
 * - LIBERAL : brut honoraires = taux × heures + majorations. Pas de IFM/ICP/
 *   cotisations. Le soignant touche 100 % du brut honoraires. Commission
 *   Jolene visible uniquement côté ÉTAB/ADMIN (§5.5 : soignant ne voit JAMAIS
 *   la commission).
 *
 * - SALARIE (Modèle A CDD) : NET en évidence (= ce que l'étab vire au
 *   soignant). Détail brut + IFM + ICP + cotisations salariales dans
 *   accordéon fermé par défaut ("Détail comptable"). Super brut pas en avant
 *   (éviter surpaiement). Commission idem LIBERAL côté ÉTAB/ADMIN uniquement.
 *
 * - type_contrat_applique = null (mission pas encore assignée) : régime
 *   prévisionnel résolu par fn_mode_exercice depuis la profession requise par
 *   la mission et le type/secteur de l'établissement. Le public reste salarié
 *   par défaut. Une vraie mission TOUS autorisée conserve le placeholder
 *   jusqu'au choix du soignant.
 *
 * Roles :
 *   ETAB/ADMIN : voient la commission Jolene (payeur)
 *   SOIGNANT   : ne voit JAMAIS la commission (§5.5)
 */

export type DecompositionFinanciereRole = 'ETAB' | 'SOIGNANT' | 'ADMIN';

interface DecompositionFinanciereProps {
  mission: any;
  etablissement?: any;
  role?: DecompositionFinanciereRole;
}

function fmt(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function DecompositionFinanciere({ mission, etablissement, role = 'ETAB' }: DecompositionFinanciereProps) {
  const m = mission;
  const etablissementContexte = etablissement ?? m.etablissements ?? null;
  const typeContratApplique = (m.type_contrat_applique ?? null) as 'LIBERAL' | 'SALARIE' | null;
  const professionRequise = (m.profession_requise ?? '') as string;
  const typeEtablissement = (etablissementContexte?.type ?? null) as string | null;
  const estSecteurPublic = etablissementContexte?.est_secteur_public === true;
  const doitResoudreParMatrice = !typeContratApplique && Boolean(professionRequise && typeEtablissement);
  const {
    mode: modeExercice,
    error: modeExerciceError,
  } = useModeExerciceMission(
    doitResoudreParMatrice ? professionRequise : '',
    doitResoudreParMatrice ? typeEtablissement : null,
    estSecteurPublic,
  );
  const resolutionMatriceEnAttente = doitResoudreParMatrice
    && !estSecteurPublic
    && !modeExercice
    && !modeExerciceError;
  const typeContrat = typeContratApplique ?? (
    (doitResoudreParMatrice || estSecteurPublic) && !resolutionMatriceEnAttente
      ? resoudreTypeContratFinancier({
          typeContratApplique,
          typeContratRecherche: m.type_contrat_recherche,
          modeExercice,
          estSecteurPublic,
        })
      : null
  );
  const isEtabOrAdmin = role === 'ETAB' || role === 'ADMIN';
  const statutMission = (m.statut ?? null) as string | null;

  const duree = m.duree_heures ?? 0;
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;
  const heuresNormales = Math.max(0, duree - (m.heures_nuit || 0) - (m.heures_dimanche || 0) - (m.heures_ferie || 0));
  const brutBase = tauxEffectif * duree;
  const totalMajorations = (m.montant_majoration_nuit || 0) + (m.montant_majoration_dimanche || 0) + (m.montant_majoration_ferie || 0);
  const totalBrut = m.total_brut ?? (brutBase + totalMajorations);
  const ifm = m.montant_ifm || 0;
  const icp = m.montant_icp || 0;
  const superBrut = totalBrut + ifm + icp;
  const cotisationsEstimees = superBrut * 0.22;
  const netSalarie = m.net_a_payer ?? m.net_estime ?? (superBrut * 0.78);
  const commissionTtc = m.montant_commission_ttc || 0;
  const commissionHt = m.montant_commission_ht || 0;
  const tauxCommission = Number(m.taux_commission_fige ?? m.taux_commission ?? 15);

  // Statuts pour lesquels la mission n'est PAS rémunérée.
  // Aucune facture honoraires, aucune commission Jolene, aucun paiement
  // soignant ne doit être déclenché (gardes backend en place :
  // generate-invoice §695, fn_declarer_paiement_soignant, stripe-connect-pay-mission §97,
  // fn_auto_facturation_mensuelle). Voir docs/logique-paiements-v1.md §7.
  const statutsNonRemuneres = ['ABSENCE', 'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE'] as const;
  if (statutsNonRemuneres.includes(statutMission as any)) {
    const libelle = (() => {
      switch (statutMission) {
        case 'ABSENCE': return {
          titre: 'Mission non honorée — Absence du soignant',
          detail: "Le soignant ne s'est pas présenté. Aucune rémunération n'est due pour cette mission.",
        };
        case 'ANNULEE_PAR_ETABLISSEMENT': return {
          titre: "Mission annulée par l'établissement",
          detail: "La mission a été annulée. Aucune rémunération n'est due.",
        };
        case 'ANNULEE_PAR_SOIGNANT': return {
          titre: 'Mission annulée par le soignant',
          detail: "La mission a été annulée par le soignant. Aucune rémunération n'est due.",
        };
        case 'EXPIREE': return {
          titre: 'Mission expirée',
          detail: "La mission n'a pas trouvé de soignant. Aucune rémunération n'est due.",
        };
        default: return { titre: 'Mission non honorée', detail: "Aucune rémunération n'est due." };
      }
    })();

    return (
      <div className="bg-muted/30 border border-border rounded-2xl p-5">
        <h3 className="text-lg font-bold text-foreground mb-3">💰 Décomposition financière</h3>
        <div className="flex items-start gap-3">
          <Ban className="h-5 w-5 text-muted-foreground shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">{libelle.titre}</p>
            <p className="text-xs text-muted-foreground mt-1">{libelle.detail}</p>
            {isEtabOrAdmin && commissionTtc > 0 && (
              <p className="text-[11px] text-muted-foreground/80 italic mt-2">
                ℹ️ La commission Jolene ({tauxCommission}%) ne sera pas facturée pour cette mission.
              </p>
            )}
          </div>
        </div>
      </div>
    );
  }

  // La première résolution RPC part dans un effet : éviter d'afficher pendant
  // ce bref délai le wording générique « salarié ou libéral », qui serait faux
  // pour les cellules BLOQUE / NON_PROPOSE de la matrice.
  if (!typeContrat && resolutionMatriceEnAttente) {
    return (
      <div className="bg-muted/30 border border-border rounded-2xl p-5" aria-live="polite">
        <h3 className="text-lg font-bold text-foreground mb-3">💰 Décomposition financière</h3>
        <div className="flex items-start gap-3 text-sm text-muted-foreground">
          <Info className="h-4 w-4 mt-0.5 shrink-0" />
          <p>Vérification du mode d'exercice de la mission…</p>
        </div>
      </div>
    );
  }

  // Placeholder : contrat réellement ouvert aux deux régimes et pas encore
  // choisi, ou contexte établissement indisponible.
  // Côté SOIGNANT, on affiche quand même le net estimé (déjà calculé sur la
  // mission et déjà montré en liste, cf. CarteMissionSoignant) : le soignant
  // doit voir ce qu'il gagne AVANT de décider, comme en liste (standard Uber).
  if (!typeContrat) {
    const netEstime = (m.net_estime ?? m.net_a_payer ?? null) as number | null;
    const fmtEntier = (v: number) =>
      new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);

    if (role === 'SOIGNANT' && netEstime != null && netEstime > 0) {
      return (
        <div className="bg-muted/30 border border-border rounded-2xl p-5">
          <h3 className="text-lg font-bold text-foreground mb-3">💰 Décomposition financière</h3>
          <p className="text-3xl font-bold text-primary leading-tight">
            ~{fmtEntier(netEstime)}{' '}
            <span className="text-base font-semibold text-foreground">net estimé</span>
          </p>
          <p className="text-xs text-muted-foreground mt-1.5">
            Montant estimé — figé à l'acceptation, selon le contrat retenu (salarié ou libéral).
          </p>
          <p className="text-xs text-muted-foreground border-t border-border pt-2 mt-3">
            Taux horaire : <span className="font-medium text-foreground">{tauxEffectif?.toFixed(2)} €/h</span> · Durée : <span className="font-medium text-foreground">{duree.toFixed(1)} h</span>
          </p>
        </div>
      );
    }

    return (
      <div className="bg-muted/30 border border-border rounded-2xl p-5">
        <h3 className="text-lg font-bold text-foreground mb-3">💰 Décomposition financière</h3>
        <div className="flex items-start gap-3 text-sm text-muted-foreground">
          <Info className="h-4 w-4 mt-0.5 shrink-0" />
          <div>
            <p>Type de contrat à définir à l'acceptation de la mission.</p>
            <p className="mt-1 text-xs">Taux horaire : <span className="font-medium text-foreground">{tauxEffectif?.toFixed(2)} €/h</span> · Durée : <span className="font-medium text-foreground">{duree.toFixed(1)} h</span></p>
          </div>
        </div>
      </div>
    );
  }

  // §7.1 Lot 7a — deux lectures du même fait selon le rôle : pour l'ÉTAB (et
  // l'admin), le taux demandé a été raboté → warning légitime. Pour la SOIGNANTE,
  // le taux affiché est celui réellement payé → c'est de la conformité, pas un
  // problème (« ⚠️ plafonné » lui faisait croire qu'elle perdait quelque chose).
  const rappelPlafondRist = m.rist_plafond_applique && (role === 'SOIGNANT' ? (
    <div className="bg-success/10 border-l-4 border-success p-3 rounded-r-lg">
      <p className="text-xs font-semibold text-success flex items-center gap-1">✓ Taux conforme Loi Rist</p>
      <p className="text-xs text-success/80 mt-1">
        Taux appliqué : {m.taux_rist_plafonne?.toFixed(2)} €/h — conforme au plafond réglementaire (décret 2023-920).
      </p>
    </div>
  ) : (
    <div className="bg-warning/10 border-l-4 border-warning p-3 rounded-r-lg">
      <p className="text-xs font-semibold text-warning flex items-center gap-1"><AlertTriangle className="h-3.5 w-3.5" /> PLAFOND LOI RIST APPLIQUÉ</p>
      <p className="text-xs text-warning/80 mt-1">
        Taux demandé : {m.taux_horaire_base?.toFixed(2)} €/h → Plafonné : {m.taux_rist_plafonne?.toFixed(2)} €/h
      </p>
      <p className="text-[10px] text-warning/60 mt-0.5">(Décret 2023-920)</p>
    </div>
  ));

  const detailHeures = (
    <div className="border-t border-border pt-3">
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Heures</p>
      <div className="flex justify-between">
        <span className="text-muted-foreground">Heures totales</span>
        <span className="font-medium">{duree.toFixed(1)}h</span>
      </div>
      {heuresNormales !== duree && (
        <div className="flex justify-between mt-1">
          <span className="text-muted-foreground pl-3">dont normales</span>
          <span className="font-medium">{heuresNormales.toFixed(1)}h</span>
        </div>
      )}
      {(m.heures_nuit || 0) > 0 && (
        <div className="flex justify-between mt-1">
          <span className="text-muted-foreground pl-3">🌙 nuit</span>
          <span className="font-medium">{m.heures_nuit?.toFixed(1)}h</span>
        </div>
      )}
      {(m.heures_dimanche || 0) > 0 && (
        <div className="flex justify-between mt-1">
          <span className="text-muted-foreground pl-3">☀️ dimanche</span>
          <span className="font-medium">{m.heures_dimanche?.toFixed(1)}h</span>
        </div>
      )}
      {(m.heures_ferie || 0) > 0 && (
        <div className="flex justify-between mt-1">
          <span className="text-muted-foreground pl-3">🎌 jour férié</span>
          <span className="font-medium">{m.heures_ferie?.toFixed(1)}h</span>
        </div>
      )}
    </div>
  );

  // ─────────────────────────────────────────────
  // Branche LIBERAL — brut honoraires = ce que touche le soignant.
  // Pas d'IFM/ICP/cotisations (géré en libéral par le soignant lui-même
  // via URSSAF libérale et sa caisse de retraite CARPIMKO/CIPAV).
  // ─────────────────────────────────────────────
  if (typeContrat === 'LIBERAL') {
    return (
      <div className="bg-gradient-to-br from-emerald-500/5 to-primary/5 border border-emerald-500/20 rounded-2xl p-5 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-bold text-foreground">💰 Décomposition financière</h3>
          <span className="text-xs font-semibold bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400 px-2 py-1 rounded-full">
            Contrat libéral
          </span>
        </div>

        <div className="space-y-3 text-sm">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Taux horaire</span>
            <span className="font-medium text-foreground">{tauxEffectif?.toFixed(2)} €/h</span>
          </div>

          {rappelPlafondRist}
          {detailHeures}

          <div className="border-t border-border pt-3 space-y-2">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Calcul</p>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Brut de base ({duree.toFixed(1)}h × {tauxEffectif?.toFixed(2)}€)</span>
              <span className="font-medium">{fmt(brutBase)}</span>
            </div>
            {totalMajorations > 0 && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">Majorations</span>
                <span className="font-medium text-primary">+{fmt(totalMajorations)}</span>
              </div>
            )}
          </div>

          <div className="border-t-2 border-emerald-500/30 pt-3">
            <div className="flex justify-between items-center">
              <span className="font-bold text-foreground">Brut honoraires soignant</span>
              <span className="text-2xl font-bold text-emerald-600 dark:text-emerald-400">{fmt(totalBrut)}</span>
            </div>
            <p className="text-[11px] text-muted-foreground mt-1">
              Montant à verser au soignant (100 % du brut honoraires, aucune retenue par Jolene)
            </p>
          </div>

          {/* Commission Jolene — uniquement côté étab/admin (logique-paiements-v1 §5.5) */}
          {isEtabOrAdmin && commissionTtc > 0 && (
            <div className="border-t border-border pt-3">
              <div className="flex justify-between items-center">
                <span className="text-sm font-semibold text-foreground">Commission Jolene</span>
                <span className="font-semibold text-foreground">{fmt(commissionTtc)} TTC</span>
              </div>
              <p className="text-[11px] text-muted-foreground mt-1">
                {fmt(commissionHt)} HT + TVA 20 %
              </p>
              <p className="text-[11px] text-muted-foreground mt-1">
                <span className="font-medium">Calcul : </span>{tauxCommission}% × {fmt(totalBrut)} honoraires bruts (taux de commission applicable)
              </p>
              <p className="text-[11px] text-primary mt-2">
                ℹ️ Facturée séparément à l'établissement, sur facture Jolene distincte — à ne pas ajouter au virement honoraires soignant.
              </p>
            </div>
          )}
        </div>

        <p className="text-[10px] text-muted-foreground/60 italic mt-4">
          Contrat libéral : le soignant déclare ses revenus et cotise auprès de l'URSSAF libérale / CARPIMKO ou CIPAV.
        </p>
      </div>
    );
  }

  // ─────────────────────────────────────────────
  // Branche SALARIE (Modèle A CDD) — NET en évidence (= ce que l'étab vire
  // au soignant via virement SEPA). Détails comptables dans accordéon fermé
  // par défaut pour éviter que l'étab vire le super brut par erreur.
  // ─────────────────────────────────────────────
  const DecompoSalarie = () => {
    const [detailOuvert, setDetailOuvert] = useState(false);

    return (
      <div className="bg-gradient-to-br from-blue-500/5 to-primary/5 border border-blue-500/20 rounded-2xl p-5 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-bold text-foreground">💰 Décomposition financière</h3>
          <span className="text-xs font-semibold bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400 px-2 py-1 rounded-full">
            Contrat salarié (CDD)
          </span>
        </div>

        {/* NET en évidence (mise en garde surpaiement) */}
        <div className="bg-blue-500/10 border-2 border-blue-500/40 rounded-xl p-4 mb-4">
          <div className="flex justify-between items-center">
            <span className="font-bold text-foreground text-base">
              {role === 'SOIGNANT' ? 'Votre NET' : 'À verser au soignant'}
            </span>
            <span className="text-3xl font-bold text-blue-600 dark:text-blue-400">{fmt(netSalarie)}</span>
          </div>
          {isEtabOrAdmin && (
            <p className="text-xs text-muted-foreground mt-2">
              Virement SEPA direct au soignant. L'établissement déclare ensuite ses cotisations (salariales + patronales) à l'URSSAF.
            </p>
          )}
          {role === 'SOIGNANT' && (
            <p className="text-xs text-muted-foreground mt-2">
              Montant versé par l'établissement (virement SEPA). Bulletin de paie généré par Jolene.
            </p>
          )}
        </div>

        {rappelPlafondRist}

        {/* Accordéon détail comptable */}
        <Collapsible open={detailOuvert} onOpenChange={setDetailOuvert}>
          <CollapsibleTrigger className="w-full flex items-center justify-between text-sm py-2 text-muted-foreground hover:text-foreground transition-colors">
            <span className="font-medium">Détail comptable (brut, IFM, ICP, cotisations)</span>
            {detailOuvert ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
          </CollapsibleTrigger>
          <CollapsibleContent className="text-sm">
            <div className="pt-2 space-y-3">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Taux horaire</span>
                <span className="font-medium text-foreground">{tauxEffectif?.toFixed(2)} €/h</span>
              </div>

              {detailHeures}

              <div className="border-t border-border pt-3 space-y-2">
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Calcul</p>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Brut de base ({duree.toFixed(1)}h × {tauxEffectif?.toFixed(2)}€)</span>
                  <span className="font-medium">{fmt(brutBase)}</span>
                </div>
                {totalMajorations > 0 && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Majorations</span>
                    <span className="font-medium text-primary">+{fmt(totalMajorations)}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Total brut</span>
                  <span className="font-bold">{fmt(totalBrut)}</span>
                </div>
                {ifm > 0 && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">IFM (10%)</span>
                    <span className="font-medium text-primary">+{fmt(ifm)}</span>
                  </div>
                )}
                {icp > 0 && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">ICP (10%)</span>
                    <span className="font-medium text-primary">+{fmt(icp)}</span>
                  </div>
                )}
                {(ifm > 0 || icp > 0) && (
                  <div className="flex justify-between border-t border-border pt-2">
                    <span className="text-muted-foreground">Super brut (avant cotisations)</span>
                    <span className="font-bold">{fmt(superBrut)}</span>
                  </div>
                )}
                <div className="flex justify-between text-destructive/80">
                  <span className="flex items-center gap-1">
                    Cotisations salariales estimées (~22%)
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Info className="h-3 w-3 text-muted-foreground cursor-help" />
                        </TooltipTrigger>
                        <TooltipContent className="max-w-xs text-xs">
                          Estimation à titre indicatif. Le détail exact figure sur le bulletin de paie généré par Jolene.
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  </span>
                  <span className="font-medium">-{fmt(cotisationsEstimees)}</span>
                </div>
                <div className="flex justify-between border-t-2 border-blue-500/30 pt-2">
                  <span className="font-bold text-foreground">= NET</span>
                  <span className="font-bold text-blue-600 dark:text-blue-400">{fmt(netSalarie)}</span>
                </div>
              </div>

              {isEtabOrAdmin && (
                <p className="text-[10px] text-muted-foreground/80 italic border-t border-border pt-2 mt-2">
                  Pour référence URSSAF. L'établissement déclare ses cotisations directement à l'URSSAF (DSN mensuelle). Jolene n'intervient pas dans le paiement URSSAF.
                </p>
              )}
            </div>
          </CollapsibleContent>
        </Collapsible>

        {/* Commission Jolene — uniquement côté étab/admin (logique-paiements-v1 §5.5) */}
        {isEtabOrAdmin && commissionTtc > 0 && (
          <div className="border-t border-border pt-3 mt-3">
            <div className="flex justify-between items-center">
              <span className="text-sm font-semibold text-foreground">Commission Jolene</span>
              <span className="font-semibold text-foreground">{fmt(commissionTtc)} TTC</span>
            </div>
            <p className="text-[11px] text-muted-foreground mt-1">
              {fmt(commissionHt)} HT + TVA 20 %
            </p>
            <p className="text-[11px] text-muted-foreground mt-1">
              <span className="font-medium">Calcul : </span>{tauxCommission}% × {fmt(superBrut)} brut total (base + IFM + ICP)
            </p>
            <p className="text-[11px] text-primary mt-2">
              ℹ️ Facturée séparément à l'établissement, sur facture Jolene distincte — ne réduit pas la rémunération du soignant.
            </p>
          </div>
        )}

        <p className="text-[10px] text-muted-foreground/60 italic mt-4">
          Bulletin de paie généré par Jolene (service prestation). Employeur URSSAF : {m.etablissements?.nom ? `« ${m.etablissements.nom} »` : "l'établissement"}.
        </p>
      </div>
    );
  };

  return <DecompoSalarie />;
}
