import { cn } from "@/lib/utils";

type SkeletonProps = React.HTMLAttributes<HTMLDivElement> & {
  variant?: "pulse" | "shimmer";
  size?: "sm" | "md" | "lg";
};

function Skeleton({ className, variant = "shimmer", size, ...props }: SkeletonProps) {
  const sizeClass =
    size === "sm" ? "h-3" : size === "lg" ? "h-6" : size === "md" ? "h-4" : "";
  const variantClass =
    variant === "shimmer"
      ? "bg-shimmer bg-shimmer-2x animate-shimmer"
      : "animate-pulse bg-muted";
  return (
    <div
      role="status"
      aria-busy="true"
      aria-live="polite"
      className={cn("rounded-md", variantClass, sizeClass, className)}
      {...props}
    />
  );
}

export { Skeleton };
