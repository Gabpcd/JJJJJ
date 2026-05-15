/**
 * Composant `<EmptyState />` standardisé Sprint 8 PR 2 + enrichi Sprint 8 ter-A BIS.
 *
 * Usage avec icône Lucide (compact circulaire) :
 *   <EmptyState
 *     icone={<Search />}
 *     titre="Aucune mission disponible"
 *     description="Élargissez vos critères pour voir plus de résultats."
 *     cta={{ label: "Modifier mes préférences", onClick: () => navigate(...) }}
 *     variant="info"
 *   />
 *
 * Usage avec illustration vectorielle (100×100, sans cercle) :
 *   <EmptyState
 *     illustration={<IllustrationBoussole />}
 *     titre="Publiez votre première mission"
 *     description="Trouvez un soignant qualifié en quelques heures."
 *     cta={{ label: "Créer une mission", onClick: () => navigate('/etablissement/missions/creer') }}
 *   />
 *
 * `illustration` a priorité sur `icone` si les deux sont fournis.
 *
 * Variants :
 * - `info` (défaut) : neutre, informatif
 * - `success` : positif (tout va bien, à jour)
 * - `warning` : action manquante (compléter profil, etc.)
 *
 * A11y : `role="status"` + `aria-live="polite"` pour annonce lecteur écran.
 */
import { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { Mascotte } from "@/components/mascotte/Mascotte";
import type { EtatMascotte } from "@/components/mascotte/Mascotte";

type Variant = "info" | "success" | "warning";

type Cta = {
  label: string;
  onClick: () => void;
  variant?: "primary" | "secondary";
};

/** Mapping variant → état mascotte par défaut. Cohérence émotionnelle Sprint 12-D. */
const VARIANT_TO_MASCOTTE_ETAT: Record<Variant, EtatMascotte> = {
  info: "empty",
  success: "happy",
  warning: "thinking",
};

type EmptyStateProps = {
  /** Icône Lucide ou autre ReactNode (rendu dans un cercle de couleur variant) */
  icone?: ReactNode;
  /** Illustration vectorielle 100×100 (rendue sans cercle, opacité 70%) — prioritaire sur `icone` */
  illustration?: ReactNode;
  /**
   * Mascotte Y2K Jolene. Sprint 12-D.
   * - `true` : Mascotte avec état auto déduit du variant
   * - `EtatMascotte` (string) : Mascotte avec état explicite
   * - `false` : pas de Mascotte
   * - non fourni : auto-rendu si ni `icone` ni `illustration`
   */
  mascotte?: boolean | EtatMascotte;
  /** Titre principal (clair, concis, sans ponctuation finale) */
  titre: string;
  /** Description complémentaire optionnelle */
  description?: string;
  /** CTA principal optionnel */
  cta?: Cta;
  /** CTA secondaire optionnel */
  ctaSecondaire?: Cta;
  /** Variant visuel selon contexte */
  variant?: Variant;
  /** Classes supplémentaires pour le wrapper */
  className?: string;
  /** Mode compact pour usage inline (peu de padding, pas d'icône large) */
  compact?: boolean;
};

const VARIANT_STYLES: Record<Variant, { wrapper: string; icon: string }> = {
  info: {
    wrapper: "bg-muted/30 border-border",
    icon: "text-muted-foreground bg-muted",
  },
  success: {
    wrapper: "bg-success/5 border-success/20",
    icon: "text-success bg-success/10",
  },
  warning: {
    wrapper: "bg-warning/5 border-warning/20",
    icon: "text-warning bg-warning/10",
  },
};

export function EmptyState({
  icone,
  illustration,
  mascotte,
  titre,
  description,
  cta,
  ctaSecondaire,
  variant = "info",
  className,
  compact = false,
}: EmptyStateProps) {
  const styles = VARIANT_STYLES[variant];

  // Détermination du visuel : priorité explicit mascotte > illustration > icone > auto-Mascotte.
  // L'auto-Mascotte s'active uniquement si aucun visuel n'est fourni (rétro-compat totale).
  const hasMascotteExplicit = mascotte !== undefined && mascotte !== false;
  const hasAutoMascotte = !icone && !illustration && mascotte !== false;
  const mascotteEtat: EtatMascotte | null = hasMascotteExplicit
    ? (typeof mascotte === "string" ? mascotte : VARIANT_TO_MASCOTTE_ETAT[variant])
    : hasAutoMascotte
      ? VARIANT_TO_MASCOTTE_ETAT[variant]
      : null;

  return (
    <div
      role="status"
      aria-live="polite"
      className={cn(
        "rounded-2xl border flex flex-col items-center justify-center text-center",
        styles.wrapper,
        compact ? "py-8 px-4" : "py-12 px-6 md:py-16",
        className,
      )}
    >
      {mascotteEtat ? (
        <Mascotte
          etat={mascotteEtat}
          taille={compact ? "sm" : "md"}
          className={compact ? "mb-3" : "mb-4"}
        />
      ) : illustration ? (
        <div
          aria-hidden="true"
          className={cn(
            "opacity-70",
            compact ? "mb-3 [&>svg]:h-16 [&>svg]:w-16" : "mb-4 [&>svg]:h-24 [&>svg]:w-24",
          )}
        >
          {illustration}
        </div>
      ) : icone ? (
        <div
          aria-hidden="true"
          className={cn(
            "rounded-full flex items-center justify-center",
            styles.icon,
            compact ? "h-10 w-10 mb-3 [&>svg]:h-5 [&>svg]:w-5" : "h-16 w-16 mb-4 [&>svg]:h-8 [&>svg]:w-8",
          )}
        >
          {icone}
        </div>
      ) : null}
      <h3
        className={cn(
          "font-semibold text-foreground",
          compact ? "text-base" : "text-lg",
        )}
      >
        {titre}
      </h3>
      {description && (
        <p
          className={cn(
            "text-muted-foreground max-w-sm",
            compact ? "text-xs mt-1" : "text-sm mt-2",
          )}
        >
          {description}
        </p>
      )}
      {(cta || ctaSecondaire) && (
        <div
          className={cn(
            "flex flex-col sm:flex-row gap-2",
            compact ? "mt-4" : "mt-6",
          )}
        >
          {cta && (
            <button
              type="button"
              onClick={cta.onClick}
              className={cn(
                "inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium transition-colors min-h-[44px]",
                (cta.variant ?? "primary") === "primary"
                  ? "bg-primary text-primary-foreground hover:bg-primary/90"
                  : "bg-muted text-foreground hover:bg-muted/80 border border-border",
              )}
            >
              {cta.label}
            </button>
          )}
          {ctaSecondaire && (
            <button
              type="button"
              onClick={ctaSecondaire.onClick}
              className={cn(
                "inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium transition-colors min-h-[44px]",
                (ctaSecondaire.variant ?? "secondary") === "secondary"
                  ? "bg-muted text-foreground hover:bg-muted/80 border border-border"
                  : "bg-primary text-primary-foreground hover:bg-primary/90",
              )}
            >
              {ctaSecondaire.label}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

// Re-export des illustrations pour usage centralisé via @/components/ui/EmptyState
export {
  IllustrationBoussole,
  IllustrationMegaphone,
  IllustrationDossier,
  IllustrationStylo,
  IllustrationCloche,
  IllustrationBouclier,
  IllustrationTirelire,
  IllustrationCalculatrice,
} from "./EmptyStateIllustrations";

export default EmptyState;
