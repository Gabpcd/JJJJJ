import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, User, FileText, Sliders, Calendar, Shield, Bell, Search } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { usePageTitle } from '@/hooks/usePageTitle';

type SectionKey = 'compte' | 'identite' | 'preferences' | 'dispos' | 'rgpd' | 'avance';

const SECTIONS: Array<{ key: SectionKey; titre: string; icon: typeof User; description: string; cta?: { label: string; path: string } }> = [
  {
    key: 'compte',
    titre: 'Mon compte',
    icon: User,
    description: 'Email, téléphone, changement de mot de passe.',
  },
  {
    key: 'identite',
    titre: 'Identité et documents',
    icon: FileText,
    description: 'Vos données identité, RPPS, CNI, RIB, attestations et DPAE.',
    cta: { label: 'Aller à mon profil', path: '/soignant/profil' },
  },
  {
    key: 'preferences',
    titre: 'Préférences mission',
    icon: Sliders,
    description: 'Professions, rayon, taux, pool urgence, SMS et consentement GPS.',
    cta: { label: 'Éditer mes préférences', path: '/soignant/profil?tab=preferences' },
  },
  {
    key: 'dispos',
    titre: 'Disponibilités et calendrier',
    icon: Calendar,
    description: 'Planning, recherches sauvegardées et synchronisation calendrier.',
  },
  {
    key: 'rgpd',
    titre: 'Données personnelles (RGPD)',
    icon: Shield,
    description: 'Exporter mes données ou supprimer mon compte. Géré depuis la section confidentialité du profil.',
    cta: { label: 'Confidentialité (profil)', path: '/soignant/profil?tab=confidentialite' },
  },
  {
    key: 'avance',
    titre: 'Paramètres avancés',
    icon: Sliders,
    description: 'Mode sombre, langue de l\'interface (FR uniquement pour l\'instant).',
  },
];

/**
 * Page paramètres soignant unifiée (Sprint 5.5 PR 5).
 *
 * Fix P0-3 audit Sprint 5 : avant, les paramètres soignant étaient éparpillés
 * dans `/soignant/profil` (tabs préférences/confidentialité) + des sous-routes
 * `/soignant/parametres/notifications` etc. Aucune page parente.
 *
 * Cette page sert de hub unique avec navigation vers les sous-sections existantes.
 * Les composants de fond (ChangementMotDePasse, ConsentementPingGps) sont
 * ajoutés en PR 6 et PR 7.
 */
export default function PageParametresSoignant() {
  usePageTitle('Paramètres');
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const sectionInit = (searchParams.get('section') as SectionKey) || 'compte';
  const [selectionnee, setSelectionnee] = useState<SectionKey>(sectionInit);

  return (
    <LayoutApp role="SOIGNANT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Sliders className="h-6 w-6 text-primary" /> Paramètres
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Gérez votre compte, vos préférences et vos données personnelles depuis un seul endroit.
        </p>
      </div>

      {/* Navigation rapide vers les sous-pages existantes */}
      <div className="mb-6 grid grid-cols-1 sm:grid-cols-2 gap-3">
        <button
          onClick={() => navigate('/soignant/parametres/notifications')}
          className="card-base flex items-center gap-3 text-left hover:border-primary transition-colors"
        >
          <Bell className="h-5 w-5 text-primary shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">Notifications</p>
            <p className="text-xs text-muted-foreground truncate">Email, SMS, push, in-app par événement</p>
          </div>
        </button>
        <button
          onClick={() => navigate('/soignant/parametres/recherches-sauvegardees')}
          className="card-base flex items-center gap-3 text-left hover:border-primary transition-colors"
        >
          <Search className="h-5 w-5 text-primary shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">Recherches sauvegardées</p>
            <p className="text-xs text-muted-foreground truncate">Filtres et alertes missions</p>
          </div>
        </button>
      </div>

      {/* Sections principales */}
      <div className="flex gap-4 flex-col sm:flex-row">
        {/* Sidebar */}
        <nav className="sm:w-64 shrink-0">
          <ul className="space-y-1">
            {SECTIONS.map((s) => {
              const Icon = s.icon;
              const active = selectionnee === s.key;
              return (
                <li key={s.key}>
                  <button
                    onClick={() => setSelectionnee(s.key)}
                    className={`w-full text-left px-3 py-2 rounded-lg flex items-center gap-2 text-sm transition-colors ${
                      active
                        ? 'bg-primary/10 text-primary font-semibold'
                        : 'text-foreground hover:bg-muted'
                    }`}
                  >
                    <Icon className="h-4 w-4" />
                    {s.titre}
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>

        {/* Contenu */}
        <section className="flex-1 min-w-0">
          <SectionContent
            section={selectionnee}
            onNavigate={(path) => navigate(path)}
          />
        </section>
      </div>
    </LayoutApp>
  );
}

function SectionContent({ section, onNavigate }: { section: SectionKey; onNavigate: (path: string) => void }) {
  const meta = SECTIONS.find((s) => s.key === section);
  if (!meta) return null;
  const Icon = meta.icon;

  return (
    <div className="card-base space-y-3">
      <div className="flex items-center gap-2">
        <Icon className="h-5 w-5 text-primary" />
        <h2 className="text-lg font-bold text-foreground">{meta.titre}</h2>
      </div>
      <p className="text-sm text-muted-foreground">{meta.description}</p>

      {section === 'compte' && <PlaceholderCompte />}
      {section === 'preferences' && (
        <PlaceholderPreferences onNavigate={() => onNavigate('/soignant/profil?tab=preferences')} />
      )}
      {section === 'identite' && (
        <PlaceholderIdentite onNavigate={() => onNavigate('/soignant/profil')} />
      )}
      {section === 'dispos' && <PlaceholderDispos onNavigate={onNavigate} />}
      {section === 'rgpd' && (
        <PlaceholderRgpd onNavigate={() => onNavigate('/soignant/profil?tab=confidentialite')} />
      )}
      {section === 'avance' && <PlaceholderAvance />}
    </div>
  );
}

function PlaceholderCompte() {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>
        La gestion de votre adresse e-mail, numéro de téléphone et mot de passe est centralisée ici.
      </p>
      <div className="rounded-lg border border-dashed border-border p-4 text-center">
        <p className="text-foreground font-medium mb-1">Changement de mot de passe</p>
        <p className="text-xs text-muted-foreground">
          Le formulaire dédié est disponible (Sprint 5.5 PR 6) dans cette section.
        </p>
      </div>
    </div>
  );
}

function PlaceholderPreferences({ onNavigate }: { onNavigate: () => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>Configurez vos professions, votre rayon de déplacement, vos types de contrat acceptés, votre taux minimum, et activez ou non le pool urgence et le suivi GPS (opt-in RGPD).</p>
      <button onClick={onNavigate} className="btn-secondary text-sm">
        Éditer mes préférences
      </button>
    </div>
  );
}

function PlaceholderIdentite({ onNavigate }: { onNavigate: () => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>Vos pièces justificatives (CNI, RPPS, RIB), attestations, DPAE et données identité sont centralisées dans votre profil.</p>
      <button onClick={onNavigate} className="btn-secondary text-sm">
        Aller à mon profil
      </button>
    </div>
  );
}

function PlaceholderDispos({ onNavigate }: { onNavigate: (path: string) => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>Synchronisez votre calendrier externe et configurez vos disponibilités.</p>
      <div className="flex flex-wrap gap-2">
        <button onClick={() => onNavigate('/soignant/planning')} className="btn-secondary text-sm">
          Mon planning
        </button>
        <button onClick={() => onNavigate('/soignant/parametres/recherches-sauvegardees')} className="btn-secondary text-sm">
          Recherches sauvegardées
        </button>
      </div>
    </div>
  );
}

function PlaceholderRgpd({ onNavigate }: { onNavigate: () => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>
        Vous pouvez à tout moment exporter vos données personnelles (JSON ou CSV) ou supprimer définitivement votre compte. Ces actions sont protégées par confirmation et audit RGPD.
      </p>
      <button onClick={onNavigate} className="btn-secondary text-sm">
        Confidentialité (profil)
      </button>
    </div>
  );
}

function PlaceholderAvance() {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>
        Mode sombre : géré automatiquement selon les préférences système, et activable via l'icône en haut de page.
      </p>
      <p>Langue de l'interface : Français (FR) uniquement pour l'instant.</p>
    </div>
  );
}
