import React from 'react';
import { LucideIcon } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

/* ── Inline SVG illustrations (line-art, teal stroke, 100×100) ── */

export function IllustrationBoussole() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <circle cx="50" cy="50" r="38" stroke="currentColor" strokeWidth="2" />
      <circle cx="50" cy="50" r="4" fill="currentColor" />
      <polygon points="50,18 54,46 50,50 46,46" fill="currentColor" opacity="0.8" />
      <polygon points="50,82 46,54 50,50 54,54" stroke="currentColor" strokeWidth="1.5" fill="none" />
      <line x1="50" y1="8" x2="50" y2="14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <line x1="50" y1="86" x2="50" y2="92" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <line x1="8" y1="50" x2="14" y2="50" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <line x1="86" y1="50" x2="92" y2="50" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

export function IllustrationMegaphone() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <path d="M25 40 L25 60 L35 60 L35 40 Z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
      <path d="M35 38 L70 22 L70 78 L35 62" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" fill="none" />
      <path d="M70 40 Q80 42 80 50 Q80 58 70 60" stroke="currentColor" strokeWidth="2" strokeLinecap="round" fill="none" />
      <path d="M74 32 Q88 38 88 50 Q88 62 74 68" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" opacity="0.5" />
      <path d="M30 60 L30 75 Q30 78 33 78 L37 78 Q40 78 40 75 L40 62" stroke="currentColor" strokeWidth="2" strokeLinecap="round" fill="none" />
    </svg>
  );
}

export function IllustrationDossier() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <path d="M20 30 L20 80 L80 80 L80 35 L55 35 L50 28 L20 28 Z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" fill="none" />
      <path d="M20 35 L80 35" stroke="currentColor" strokeWidth="1.5" />
      <path d="M40 55 L60 55" stroke="currentColor" strokeWidth="2" strokeLinecap="round" opacity="0.5" />
      <path d="M40 63 L55 63" stroke="currentColor" strokeWidth="2" strokeLinecap="round" opacity="0.3" />
      <path d="M15 75 L15 25 L45 25 L50 32" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" fill="none" opacity="0.3" />
    </svg>
  );
}

export function IllustrationStylo() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <path d="M65 15 L80 30 L35 75 L20 78 L23 63 Z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" fill="none" />
      <line x1="30" y1="56" x2="72" y2="22" stroke="currentColor" strokeWidth="1.5" opacity="0.3" />
      <path d="M20 78 L23 63" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <line x1="15" y1="85" x2="85" y2="85" stroke="currentColor" strokeWidth="2" strokeLinecap="round" opacity="0.3" />
    </svg>
  );
}

export function IllustrationCloche() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <path d="M35 42 Q35 25 50 25 Q65 25 65 42 L65 58 L72 65 L28 65 L35 58 Z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" fill="none" />
      <path d="M44 65 Q44 72 50 72 Q56 72 56 65" stroke="currentColor" strokeWidth="2" fill="none" />
      <line x1="50" y1="18" x2="50" y2="25" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <line x1="20" y1="20" x2="80" y2="80" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" opacity="0.6" />
    </svg>
  );
}

export function IllustrationBouclier() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <path d="M50 15 L78 28 L78 55 Q78 75 50 88 Q22 75 22 55 L22 28 Z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" fill="none" />
      <polyline points="38,52 47,61 62,42" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
    </svg>
  );
}

export function IllustrationTirelire() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <ellipse cx="50" cy="55" rx="28" ry="22" stroke="currentColor" strokeWidth="2" fill="none" />
      <path d="M40 35 L40 30 Q40 25 50 25 Q60 25 60 30 L60 35" stroke="currentColor" strokeWidth="2" fill="none" />
      <line x1="50" y1="25" x2="50" y2="35" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0.4" />
      <circle cx="40" cy="50" r="2" fill="currentColor" opacity="0.6" />
      <path d="M78 50 L85 45 L85 58 L78 55" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" fill="none" />
      <line x1="35" y1="77" x2="32" y2="85" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <line x1="65" y1="77" x2="68" y2="85" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

export function IllustrationCalculatrice() {
  return (
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-primary">
      <rect x="25" y="12" width="50" height="76" rx="4" stroke="currentColor" strokeWidth="2" fill="none" />
      <rect x="32" y="20" width="36" height="16" rx="2" stroke="currentColor" strokeWidth="1.5" fill="none" />
      <circle cx="38" cy="48" r="3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="50" cy="48" r="3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="62" cy="48" r="3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="38" cy="60" r="3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="50" cy="60" r="3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="62" cy="60" r="3" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="38" cy="72" r="3" stroke="currentColor" strokeWidth="1.5" />
      <rect x="47" y="69" width="18" height="6" rx="2" stroke="currentColor" strokeWidth="1.5" fill="none" />
    </svg>
  );
}

/* ── Component ── */

interface EtatVideProps {
  /** Lucide icon (legacy) OR inline SVG illustration */
  icone?: LucideIcon;
  illustration?: React.ReactNode;
  titre: string;
  sousTitre: string;
  boutonLabel?: string;
  boutonRoute?: string;
  boutonDisabled?: boolean;
}

export function EtatVide({ icone: Icone, illustration, titre, sousTitre, boutonLabel, boutonRoute, boutonDisabled }: EtatVideProps) {
  const navigate = useNavigate();

  return (
    <div className="flex flex-col items-center justify-center py-12 px-4 text-center">
      {illustration ? (
        <div className="mb-4 opacity-70">{illustration}</div>
      ) : Icone ? (
        <Icone className="h-16 w-16 text-primary/30 mb-4" />
      ) : null}
      <h3 className="text-lg font-semibold text-foreground mb-2">{titre}</h3>
      <p className="text-sm text-muted-foreground max-w-sm mb-6">{sousTitre}</p>
      {boutonLabel && boutonRoute && (
        <button
          onClick={() => navigate(boutonRoute)}
          disabled={boutonDisabled}
          className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {boutonLabel}
        </button>
      )}
    </div>
  );
}
