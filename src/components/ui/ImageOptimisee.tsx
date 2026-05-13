/**
 * Composant `<ImageOptimisee />` Sprint 8 PR 7 (chantier 8.4).
 *
 * - Lazy loading natif (loading="lazy") par défaut
 * - WebP first avec fallback automatique (via <picture>)
 * - srcset responsive pour densité écran
 * - aspect-ratio CSS pour éviter Cumulative Layout Shift
 * - decoding="async" pour ne pas bloquer le rendu
 *
 * Usage :
 *   <ImageOptimisee
 *     src="/images/illustration.png"
 *     srcWebp="/images/illustration.webp"
 *     alt="Description significative"
 *     width={400}
 *     height={300}
 *   />
 *
 * Pour image purement décorative : alt="" (RGAA AA).
 */
import { ImgHTMLAttributes } from 'react';
import { cn } from '@/lib/utils';

type Props = Omit<ImgHTMLAttributes<HTMLImageElement>, 'loading' | 'decoding'> & {
  /** Source PNG/JPG fallback (obligatoire) */
  src: string;
  /** Source WebP optimisée (facultatif mais recommandé) */
  srcWebp?: string;
  /** srcSet responsive PNG/JPG */
  srcSet?: string;
  /** srcSet WebP responsive */
  srcSetWebp?: string;
  /** Texte alternatif. Obligatoire (chaîne vide acceptée pour décoratif). */
  alt: string;
  /** Largeur intrinsèque (px) — important pour aspect-ratio */
  width: number;
  /** Hauteur intrinsèque (px) — important pour aspect-ratio */
  height: number;
  /** Sizes attribute pour srcSet */
  sizes?: string;
  /** Force loading eager (above-the-fold) sinon lazy par défaut */
  prioritaire?: boolean;
};

export function ImageOptimisee({
  src,
  srcWebp,
  srcSet,
  srcSetWebp,
  alt,
  width,
  height,
  sizes,
  prioritaire = false,
  className,
  ...rest
}: Props) {
  const loading = prioritaire ? 'eager' : 'lazy';
  const fetchPriority = prioritaire ? 'high' : 'auto';

  const img = (
    <img
      src={src}
      srcSet={srcSet}
      alt={alt}
      width={width}
      height={height}
      sizes={sizes}
      loading={loading}
      decoding="async"
      // @ts-expect-error: fetchpriority pas encore dans les types React DOM
      fetchpriority={fetchPriority}
      className={cn('max-w-full h-auto', className)}
      style={{ aspectRatio: `${width} / ${height}` }}
      {...rest}
    />
  );

  if (!srcWebp && !srcSetWebp) {
    return img;
  }

  return (
    <picture>
      <source type="image/webp" srcSet={srcSetWebp ?? srcWebp} sizes={sizes} />
      {img}
    </picture>
  );
}

export default ImageOptimisee;
