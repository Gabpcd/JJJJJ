import type { ComponentPropsWithoutRef } from 'react';
import { cn } from '@/lib/utils';

interface LogoJoleneProps extends Omit<ComponentPropsWithoutRef<'span'>, 'children'> {
  afficherNom?: boolean;
  decoratif?: boolean;
  imageClassName?: string;
  nomClassName?: string;
}

/**
 * Identité visuelle Jolene.
 *
 * Toute surface de marque doit utiliser ce composant afin que l'application
 * web et les conteneurs natifs partagent la même icône canonique.
 */
export function LogoJolene({
  afficherNom = true,
  decoratif = false,
  className,
  imageClassName,
  nomClassName,
  ...props
}: LogoJoleneProps) {
  return (
    <span
      className={cn('inline-flex items-center gap-2', className)}
      role={!afficherNom && !decoratif ? 'img' : undefined}
      aria-label={!afficherNom && !decoratif ? 'Jolene' : undefined}
      aria-hidden={decoratif || undefined}
      {...props}
    >
      <img
        src="/logo-jolene-carre.png"
        alt=""
        width={1024}
        height={1024}
        draggable={false}
        aria-hidden="true"
        className={cn(
          'h-7 w-7 shrink-0 rounded-[22%] object-cover',
          imageClassName,
        )}
      />
      {afficherNom && (
        <span className={cn('font-bold text-primary', nomClassName)}>Jolene</span>
      )}
    </span>
  );
}
