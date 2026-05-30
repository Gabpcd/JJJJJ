import { ReactNode } from 'react';
import { ChevronRight, LucideIcon } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export interface LigneReglage {
  icone: LucideIcon;
  label: string;
  /** Destination de navigation (ou onClick). */
  route?: string;
  onClick?: () => void;
  /** Texte/valeur affiché à droite avant le chevron (optionnel). */
  valeur?: string;
  /** Badge numérique (ex: notifs). */
  badge?: number;
  /** Couleur d'accent de l'icône (rouge pour déconnexion, etc.). */
  variante?: 'default' | 'danger';
  /** Masque le chevron (ex: action terminale comme Déconnexion). */
  sansChevron?: boolean;
}

export interface SectionReglages {
  titre?: string;
  lignes: LigneReglage[];
}

/**
 * Liste de réglages façon iOS Settings : sections groupées, rows pleine
 * largeur avec icône + label + chevron. Donne une sensation d'app native
 * (pas des cartes web). Utilisée par les pages "Mon compte" des 3 interfaces.
 */
export function ListeReglages({ sections }: { sections: SectionReglages[] }) {
  const navigate = useNavigate();

  const handle = (l: LigneReglage) => {
    if (l.onClick) l.onClick();
    else if (l.route) navigate(l.route);
  };

  return (
    <div className="space-y-6">
      {sections.map((section, si) => (
        <section key={si}>
          {section.titre && (
            <h2 className="px-4 mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              {section.titre}
            </h2>
          )}
          <div className="overflow-hidden rounded-2xl border border-border bg-card divide-y divide-border">
            {section.lignes.map((l, li) => {
              const danger = l.variante === 'danger';
              const Icone = l.icone;
              return (
                <button
                  key={li}
                  type="button"
                  onClick={() => handle(l)}
                  className="w-full flex items-center gap-3 px-4 py-3.5 text-left transition-colors active:bg-muted/60 hover:bg-muted/40"
                >
                  <span
                    className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
                      danger ? 'bg-destructive/10 text-destructive' : 'bg-primary/10 text-primary'
                    }`}
                  >
                    <Icone className="h-[18px] w-[18px]" />
                  </span>
                  <span className={`flex-1 text-[15px] font-medium ${danger ? 'text-destructive' : 'text-foreground'}`}>
                    {l.label}
                  </span>
                  {typeof l.badge === 'number' && l.badge > 0 && (
                    <span className="min-w-[20px] h-5 px-1.5 flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
                      {l.badge > 99 ? '99+' : l.badge}
                    </span>
                  )}
                  {l.valeur && <span className="text-sm text-muted-foreground">{l.valeur}</span>}
                  {!l.sansChevron && <ChevronRight className="h-4 w-4 text-muted-foreground/50 shrink-0" />}
                </button>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}

/** En-tête de page "Mon compte" : avatar + nom + sous-titre. */
export function EnteteCompte({
  avatar,
  titre,
  sousTitre,
  badge,
}: {
  avatar?: ReactNode;
  titre: string;
  sousTitre?: string;
  badge?: ReactNode;
}) {
  return (
    <div className="flex items-center gap-4 px-1 mb-6">
      {avatar}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2 flex-wrap">
          <h1 className="text-xl font-bold text-foreground truncate">{titre}</h1>
          {badge}
        </div>
        {sousTitre && <p className="text-sm text-muted-foreground truncate">{sousTitre}</p>}
      </div>
    </div>
  );
}
