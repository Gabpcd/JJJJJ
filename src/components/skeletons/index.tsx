/**
 * Skeletons contextuels Sprint 8 PR 1.
 *
 * Conventions :
 * - role="status" + aria-busy via le composant <Skeleton> base.
 * - shimmer par défaut (animate-shimmer), fallback animate-pulse si reduced-motion.
 * - Couleurs neutres aujourd'hui — Sprint 9 ré-habillera en Y2K Gen Z.
 */
import { Skeleton } from "@/components/ui/skeleton";

/* ============================================================
 * SOIGNANT — recherche & candidatures
 * ============================================================ */

export function CarteMissionSkeleton() {
  return (
    <div className="card-base p-4 space-y-3" aria-label="Chargement carte mission">
      <div className="flex items-center justify-between gap-3">
        <Skeleton className="h-5 w-2/3" />
        <Skeleton className="h-5 w-16 rounded-full" />
      </div>
      <Skeleton className="h-4 w-1/2" />
      <div className="flex gap-2">
        <Skeleton className="h-6 w-20 rounded-full" />
        <Skeleton className="h-6 w-24 rounded-full" />
      </div>
      <div className="flex items-center justify-between pt-2">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-9 w-28 rounded-lg" />
      </div>
    </div>
  );
}

export function ListeCarteMissionSkeleton({ count = 3 }: { count?: number }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: count }).map((_, i) => (
        <CarteMissionSkeleton key={i} />
      ))}
    </div>
  );
}

export function CandidatureSkeleton() {
  return (
    <div className="card-base p-4 space-y-3" aria-label="Chargement candidature">
      <div className="flex items-center justify-between">
        <Skeleton className="h-4 w-1/2" />
        <Skeleton className="h-5 w-20 rounded-full" />
      </div>
      <Skeleton className="h-3 w-1/3" />
      <div className="flex gap-2 pt-1">
        <Skeleton className="h-8 w-24 rounded-lg" />
        <Skeleton className="h-8 w-20 rounded-lg" />
      </div>
    </div>
  );
}

export function ListeCandidatureSkeleton({ count = 4 }: { count?: number }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: count }).map((_, i) => (
        <CandidatureSkeleton key={i} />
      ))}
    </div>
  );
}

/* ============================================================
 * SOIGNANT — profil & dashboard
 * ============================================================ */

export function ProfilSoignantSkeleton() {
  return (
    <div className="space-y-6" aria-label="Chargement profil soignant">
      <div className="flex items-center gap-4">
        <Skeleton className="h-20 w-20 rounded-full" />
        <div className="space-y-2 flex-1">
          <Skeleton className="h-5 w-1/3" />
          <Skeleton className="h-4 w-1/4" />
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-24 rounded-xl" />
      </div>
      <div className="space-y-2">
        <Skeleton className="h-4 w-1/4" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-2/3" />
      </div>
    </div>
  );
}

export function DashboardKpiSkeleton({ kpis = 4 }: { kpis?: number }) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3" aria-label="Chargement KPIs">
      {Array.from({ length: kpis }).map((_, i) => (
        <div key={i} className="card-base p-4 flex items-center gap-3">
          <Skeleton className="h-12 w-12 rounded-xl" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-5 w-20" />
            <Skeleton className="h-3 w-16" />
          </div>
        </div>
      ))}
    </div>
  );
}

/* ============================================================
 * PAIEMENTS & FACTURATION
 * ============================================================ */

export function TableauPaiementSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="card-base p-4 space-y-3" aria-label="Chargement tableau paiements">
      <div className="hidden md:flex gap-4 border-b border-border pb-2">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-4 w-40" />
        <Skeleton className="h-4 w-20" />
        <Skeleton className="h-4 w-24 ml-auto" />
      </div>
      {Array.from({ length: rows }).map((_, i) => (
        <div
          key={i}
          className="flex flex-col md:flex-row md:items-center gap-2 md:gap-4 border-b border-border/40 pb-3 last:border-b-0"
        >
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-4 w-20" />
          <Skeleton className="h-8 w-24 rounded-lg md:ml-auto" />
        </div>
      ))}
    </div>
  );
}

/* ============================================================
 * SCORE & ÉVALUATIONS
 * ============================================================ */

export function ScoreSkeleton() {
  return (
    <div className="space-y-4" aria-label="Chargement score">
      <div className="card-base p-6 flex items-center gap-6">
        <Skeleton className="h-24 w-24 rounded-full" />
        <div className="flex-1 space-y-2">
          <Skeleton className="h-6 w-1/3" />
          <Skeleton className="h-4 w-1/2" />
          <Skeleton className="h-2 w-full rounded-full" />
        </div>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="card-base p-4 space-y-2">
            <Skeleton className="h-4 w-1/2" />
            <Skeleton className="h-6 w-1/3" />
            <Skeleton className="h-3 w-2/3" />
          </div>
        ))}
      </div>
    </div>
  );
}

/* ============================================================
 * MESSAGERIE
 * ============================================================ */

export function MessagerieSkeleton({ count = 5 }: { count?: number }) {
  return (
    <div className="space-y-2" aria-label="Chargement messagerie">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="card-base p-3 flex items-center gap-3">
          <Skeleton className="h-10 w-10 rounded-full" />
          <div className="flex-1 space-y-2">
            <div className="flex items-center justify-between">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-3 w-12" />
            </div>
            <Skeleton className="h-3 w-2/3" />
          </div>
        </div>
      ))}
    </div>
  );
}

/* ============================================================
 * ADMIN
 * ============================================================ */

export function AdminTableauSkeleton({
  rows = 8,
  cols = 5,
}: {
  rows?: number;
  cols?: number;
}) {
  return (
    <div className="card-base p-4 space-y-3" aria-label="Chargement tableau admin">
      <div className="flex gap-4 border-b border-border pb-2">
        {Array.from({ length: cols }).map((_, i) => (
          <Skeleton key={i} className="h-4 flex-1" />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex gap-4 py-2 border-b border-border/40 last:border-b-0">
          {Array.from({ length: cols }).map((_, j) => (
            <Skeleton key={j} className="h-4 flex-1" />
          ))}
        </div>
      ))}
    </div>
  );
}

/* ============================================================
 * CONTRATS — preview PDF
 * ============================================================ */

export function ContratPdfSkeleton() {
  return (
    <div
      className="card-base aspect-[1/1.4] w-full max-w-2xl mx-auto p-6 space-y-3"
      aria-label="Chargement contrat PDF"
    >
      <div className="flex justify-between items-start mb-4">
        <Skeleton className="h-8 w-32" />
        <Skeleton className="h-8 w-24" />
      </div>
      <Skeleton className="h-5 w-2/3 mx-auto" />
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-5/6" />
      <div className="py-3" />
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-2/3" />
      <Skeleton className="h-3 w-3/4" />
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-1/2" />
    </div>
  );
}

/* ============================================================
 * PAGE GÉNÉRIQUE
 * ============================================================ */

export function PageContenuSkeleton() {
  return (
    <div className="space-y-4" aria-label="Chargement contenu">
      <div className="space-y-2">
        <Skeleton className="h-7 w-1/3" />
        <Skeleton className="h-4 w-1/2" />
      </div>
      <div className="space-y-3">
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-4/5" />
      </div>
    </div>
  );
}
