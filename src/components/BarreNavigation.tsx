import React, { useState, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { LucideIcon, Home, Search, FileText, CalendarDays, User, PlusCircle, List, ClipboardCheck, Settings, HeartPulse, LogOut, MapPin, Banknote, CreditCard, Rocket, Bell, Flame, MessageCircle, ClipboardList, Users, Scale, ChevronDown, Activity, Shield, Menu, X, Star, Gift, ShieldCheck, ArrowLeft, Sparkles } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { UserRole } from '@/lib/types';
import { estEligibleLiberal } from '@/lib/regles-installation-liberal';
import { supabase } from '@/integrations/supabase/client';
import { BadgeNotification } from '@/components/PanneauNotifications';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { ThemeToggle } from '@/components/ThemeToggle';
import { useMessagesNonLus } from '@/hooks/useMessagesNonLus';

interface NavItem { icone: LucideIcon; label: string; route: string; }
interface NavGroup { icone: LucideIcon; label: string; items: NavItem[]; }
type SidebarEntry = NavItem | NavGroup;

function isGroup(e: SidebarEntry): e is NavGroup { return 'items' in e; }

/* ── Mobile bottom bars (5 items max) ── */
const NAV_SOIGNANT_MOBILE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/soignant/tableau-de-bord' },
  // Session G1 : onglet « Missions » mobile → page canonique « Trouver une mission ».
  { icone: Search, label: 'Missions', route: '/soignant/recherche-missions' },
  // Boucle de vente : le matching (swipe Hinge-style) est le hook d'engagement →
  // remonté du menu vers la barre du bas. Le Planning passe dans Accueil + Menu.
  { icone: Sparkles, label: 'Matchs', route: '/soignant/mes-matches' },
  { icone: MessageCircle, label: 'Messages', route: '/soignant/messagerie' },
  // L'onglet ouvre le hub « Mon compte » (profil + documents + finances + réglages),
  // pas seulement le profil → libellé « Menu » + icône hamburger pour cohérence.
  { icone: Menu, label: 'Menu', route: '/soignant/mon-compte' },
];

const NAV_ETABLISSEMENT_MOBILE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
  { icone: ClipboardList, label: 'Missions', route: '/etablissement/missions' },
  // CTA central : publier une mission = l'action #1 de l'étab (revenu Jolene).
  // Présences passe dans le Menu (même traitement que Planning soignant).
  { icone: PlusCircle, label: 'Publier', route: '/etablissement/missions/creer' },
  { icone: MessageCircle, label: 'Messages', route: '/etablissement/messagerie' },
  { icone: Menu, label: 'Menu', route: '/etablissement/mon-compte' },
];

/* ── Desktop sidebars (grouped) ── */
function getSoignantSidebar(isLiberal: boolean, showLiberalPath: boolean): SidebarEntry[] {
  const entries: SidebarEntry[] = [
    { icone: Home, label: 'Accueil', route: '/soignant/tableau-de-bord' },
    {
      icone: Search, label: 'Missions', items: [
        // Session G1 : découverte consolidée — une seule entrée « Trouver une mission »
        // vers la page canonique (liste + filtres + toggle swipe + carte + alertes).
        { icone: Search, label: 'Trouver une mission', route: '/soignant/recherche-missions' },
        { icone: ClipboardList, label: 'Mes missions', route: '/soignant/missions?onglet=mes_missions' },
        { icone: Flame, label: 'Pool urgence', route: '/soignant/pool-urgence' },
        { icone: Star, label: 'Mes favoris', route: '/soignant/mes-favoris' },
        { icone: CalendarDays, label: 'Planning', route: '/soignant/planning' },
      ],
    },
    {
      icone: Activity, label: 'Activité', items: [
        { icone: MapPin, label: 'Présences', route: '/soignant/presences' },
        { icone: FileText, label: 'Documents', route: '/soignant/mes-documents' },
        { icone: ShieldCheck, label: 'Mon score', route: '/soignant/score' },
        { icone: Scale, label: 'Litiges & contestations', route: '/soignant/litiges' },
      ],
    },
    // Session G2 : entrées argent (gains / factures / bulletins / avances)
    // fusionnées dans le hub unique « Mes finances » → /soignant/mes-gains.
    // Pour le libéral, Stripe Connect + Mandat facturation restent à part
    // (hors hub : configuration de paiement, pas un historique financier).
    isLiberal
      ? {
          icone: Banknote, label: 'Finances', items: [
            { icone: Banknote, label: 'Mes finances', route: '/soignant/mes-gains' },
            { icone: CreditCard, label: 'Stripe Connect', route: '/soignant/stripe-connect' },
            { icone: FileText, label: 'Mandat facturation', route: '/soignant/mandat-facturation' },
          ],
        }
      : { icone: Banknote, label: 'Mes finances', route: '/soignant/mes-gains' },
    { icone: MessageCircle, label: 'Messagerie', route: '/soignant/messagerie' },
  ];

  if (showLiberalPath) {
    entries.push({ icone: Rocket, label: 'Passer en libéral', route: '/soignant/passer-en-liberal' });
  }

  entries.push({ icone: Gift, label: 'Parrainage', route: '/soignant/parrainage' });
  // Session G3 — hub compte unique. « Mon compte » = réglages/finances/documents
  // (page MonCompteSoignant), « Mon profil » = identité publique éditable.
  entries.push({ icone: Settings, label: 'Mon compte', route: '/soignant/mon-compte' });
  entries.push({ icone: User, label: 'Mon profil', route: '/soignant/profil' });

  return entries;
}

function getEtablissementSidebar(): SidebarEntry[] {
  return [
    { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
    { icone: PlusCircle, label: 'Publier une mission', route: '/etablissement/missions/creer' },
    { icone: ClipboardList, label: 'Missions', route: '/etablissement/missions' },
    {
      icone: Users, label: 'Soignants', items: [
        { icone: Users, label: 'Annuaire', route: '/etablissement/soignants' },
        { icone: Star, label: 'Mes favoris', route: '/etablissement/mes-favoris' },
        { icone: Flame, label: 'Pool urgence', route: '/etablissement/pool-urgence' },
      ],
    },
    {
      icone: ClipboardCheck, label: 'Gestion', items: [
        { icone: ClipboardCheck, label: 'Présences', route: '/etablissement/presences' },
        { icone: FileText, label: 'Contrats', route: '/etablissement/contrats' },
        { icone: Scale, label: 'Litiges', route: '/etablissement/litiges' },
      ],
    },
    { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
    { icone: MessageCircle, label: 'Messagerie', route: '/etablissement/messagerie' },
    { icone: Settings, label: 'Paramètres', route: '/etablissement/parametres' },
  ];
}

const NAV_GROUPE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/groupe/tableau-de-bord' },
  { icone: List, label: 'Établissements', route: '/groupe/etablissements' },
];

function getMobileNavItems(role: UserRole): NavItem[] {
  switch (role) {
    case 'SOIGNANT': return NAV_SOIGNANT_MOBILE;
    case 'ADMIN_ETABLISSEMENT': return NAV_ETABLISSEMENT_MOBILE;
    case 'ADMIN_GROUPE': return NAV_GROUPE;
    case 'ADMIN_PLATEFORME': return [];
    default: return [];
  }
}

/* ── Collapsible sidebar group ── */
function SidebarGroup({ group, location, navigate, openGroups, toggleGroup, messagesNonLus }: {
  group: NavGroup;
  location: ReturnType<typeof useLocation>;
  navigate: ReturnType<typeof useNavigate>;
  openGroups: Set<string>;
  toggleGroup: (label: string) => void;
  messagesNonLus: number;
}) {
  const isOpen = openGroups.has(group.label);
  const hasActiveChild = group.items.some(i => location.pathname === i.route);

  return (
    <div>
      <button
        onClick={() => toggleGroup(group.label)}
        className={`sidebar-item w-full text-left justify-between ${hasActiveChild ? 'text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
      >
        <div className="flex items-center gap-3">
          <group.icone className="h-5 w-5" />
          <span>{group.label}</span>
        </div>
        <ChevronDown className={`h-4 w-4 transition-transform duration-200 ${isOpen ? 'rotate-180' : ''}`} />
      </button>
      {isOpen && (
        <div className="ml-4 pl-4 border-l border-sidebar-border space-y-0.5 mt-0.5">
          {group.items.map(item => {
            const actif = location.pathname === item.route;
            const isMsg = item.label === 'Messagerie';
            return (
              <button
                key={item.route}
                onClick={() => navigate(item.route)}
                aria-current={actif ? 'page' : undefined}
                className={`sidebar-item w-full text-left text-sm py-2 ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/60 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
              >
                <item.icone className="h-4 w-4" />
                <span className="flex-1">{item.label}</span>
                {isMsg && messagesNonLus > 0 && (
                  <span className="h-5 min-w-[20px] flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold px-1">
                    {messagesNonLus > 9 ? '9+' : messagesNonLus}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function BarreNavigation({ role }: { role: UserRole }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion, user } = useAuth();

  // Routes "racine" (onglets de la bottom nav) : pas de bouton retour.
  // Toute autre route est une sous-page → on affiche un chevron retour.
  const bottomNavRoutes = getMobileNavItems(role).map((n) => n.route);
  const estRacine = bottomNavRoutes.includes(location.pathname);
  const afficherRetour = !estRacine;
  // Interfaces dotées d'un onglet "Mon compte" (bottom nav) → plus de hamburger
  // ni de bouton déconnexion dans le header (tout est dans Mon compte).
  const aMonCompte = role === 'SOIGNANT' || role === 'ADMIN_ETABLISSEMENT';
  const [isLiberal, setIsLiberal] = useState(false);
  const [showLiberalPath, setShowLiberalPath] = useState(false);
  const [userInfo, setUserInfo] = useState<{ prenom?: string; nom?: string; avatarUrl?: string } | null>(null);
  const { count: messagesNonLus } = useMessagesNonLus();
  const [openGroups, setOpenGroups] = useState<Set<string>>(new Set());
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  // Close mobile menu on route change
  useEffect(() => {
    setMobileMenuOpen(false);
  }, [location.pathname]);

  // Auto-open the group containing the active route
  useEffect(() => {
    const sidebar = role === 'SOIGNANT'
      ? getSoignantSidebar(isLiberal, showLiberalPath)
      : role === 'ADMIN_ETABLISSEMENT'
        ? getEtablissementSidebar()
        : [];

    for (const entry of sidebar) {
      if (isGroup(entry) && entry.items.some(i => location.pathname === i.route || location.pathname.startsWith(i.route + '/'))) {
        setOpenGroups(prev => {
          if (prev.has(entry.label)) return prev;
          return new Set([...prev, entry.label]);
        });
      }
    }
  }, [location.pathname, role, isLiberal, showLiberalPath]);

  const toggleGroup = (label: string) => {
    setOpenGroups(prev => {
      const next = new Set(prev);
      if (next.has(label)) next.delete(label); else next.add(label);
      return next;
    });
  };

  useEffect(() => {
    if (!user) return;
    if (role === 'SOIGNANT') {
      supabase.from('soignants').select('profession, heures_cumulees, statut_liberal, type_exercice, prenom, nom, avatar_url').eq('id', user.id).maybeSingle()
        .then(({ data }) => {
          if (!data) return;
          setUserInfo({ prenom: data.prenom, nom: data.nom, avatarUrl: (data as any).avatar_url });
          if (data.statut_liberal === 'ACTIF' || (data as any).type_exercice === 'LIBERAL' || (data as any).type_exercice === 'MIXTE') setIsLiberal(true);
          if (estEligibleLiberal(data.profession) && data.statut_liberal !== 'ACTIF') {
            setShowLiberalPath(true);
          }
        });
    } else if (role === 'ADMIN_ETABLISSEMENT') {
      supabase.from('etablissements').select('nom, logo_url').eq('id', user.id).single()
        .then(({ data }) => {
          if (data) {
            setUserInfo({ prenom: data.nom, nom: '', avatarUrl: (data as any).logo_url });
          }
        });
    }
  }, [role, user]);

  const mobileItems = getMobileNavItems(role);
  const sidebarEntries = role === 'SOIGNANT'
    ? getSoignantSidebar(isLiberal, showLiberalPath)
    : role === 'ADMIN_ETABLISSEMENT'
      ? getEtablissementSidebar()
      : NAV_GROUPE.map(i => i as SidebarEntry);

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  return (
    <>
      {/* ── Mobile top header (logo + notifs + logout) ── */}
      <header className="sticky top-0 left-0 right-0 flex md:hidden z-40 bg-card/95 backdrop-blur-sm border-b border-border px-4 items-center justify-between no-print" style={{ height: 'calc(3.5rem + env(safe-area-inset-top))', paddingTop: 'env(safe-area-inset-top)' }} role="banner">
        <div className="flex items-center gap-2">
          {afficherRetour ? (
            /* Sous-page → bouton retour (remplace logo/hamburger) */
            <button
              onClick={() => { if (window.history.length > 1) navigate(-1); else navigate(role === 'SOIGNANT' ? '/soignant/tableau-de-bord' : role === 'ADMIN_ETABLISSEMENT' ? '/etablissement/tableau-de-bord' : '/groupe/tableau-de-bord'); }}
              aria-label="Retour"
              className="flex items-center gap-1 p-2 -ml-2 rounded-lg text-foreground hover:bg-muted transition"
            >
              <ArrowLeft className="h-6 w-6" />
            </button>
          ) : (
            <>
              {/* Hamburger : conservé pour étab/admin ; masqué pour SOIGNANT
                  (remplacé par l'onglet "Mon compte" de la bottom nav). */}
              {!aMonCompte && (
                <button
                  onClick={() => setMobileMenuOpen(true)}
                  aria-label="Ouvrir le menu"
                  className="p-2 -ml-2 rounded-lg text-foreground hover:bg-muted transition"
                >
                  <Menu className="h-6 w-6" />
                </button>
              )}
            </>
          )}
          <button onClick={() => navigate(role === 'SOIGNANT' ? '/soignant/tableau-de-bord' : role === 'ADMIN_ETABLISSEMENT' ? '/etablissement/tableau-de-bord' : '/groupe/tableau-de-bord')} className="flex items-center gap-2" aria-label="Accueil">
            <HeartPulse className="h-6 w-6 text-primary" />
            <span className="text-lg font-bold text-primary">Jolene</span>
          </button>
        </div>
        <div className="flex items-center gap-1">
          <BadgeNotification />
          <ThemeToggle className="text-foreground hover:bg-muted" />
          {/* Déconnexion : masquée pour SOIGNANT (dans "Mon compte"). */}
          {!aMonCompte && (
            <button onClick={handleDeconnexion} aria-label="Se déconnecter" className="p-2 rounded-lg hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition">
              <LogOut className="h-5 w-5" />
            </button>
          )}
        </div>
      </header>

      {/* ── Mobile drawer (full sidebar on mobile) ── */}
      {mobileMenuOpen && (
        <>
          <div
            className="fixed inset-0 z-[60] bg-foreground/50 md:hidden no-print"
            onClick={() => setMobileMenuOpen(false)}
            aria-hidden="true"
          />
          <div
            className="fixed left-0 top-0 bottom-0 z-[61] w-[280px] max-w-[85vw] flex md:hidden flex-col no-print animate-in slide-in-from-left duration-200"
            style={{
              paddingTop: 'env(safe-area-inset-top)',
              background: 'linear-gradient(180deg, hsl(270 40% 97%) 0%, hsl(330 50% 96%) 100%)',
            }}
            role="navigation"
            aria-label="Menu principal"
          >
            <div className="p-4 flex items-center justify-between border-b border-sidebar-border">
              <div className="flex items-center gap-2">
                <HeartPulse className="h-6 w-6 text-primary" />
                <span className="text-lg font-bold text-primary">Jolene</span>
              </div>
              <button
                onClick={() => setMobileMenuOpen(false)}
                aria-label="Fermer le menu"
                className="p-2 rounded-lg text-foreground hover:bg-muted"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            <nav className="flex-1 px-3 py-3 space-y-0.5 overflow-y-auto" aria-label="Menu mobile">
              {sidebarEntries.map((entry) => {
                if (isGroup(entry)) {
                  return (
                    <SidebarGroup
                      key={entry.label}
                      group={entry}
                      location={location}
                      navigate={(p) => { navigate(p); setMobileMenuOpen(false); }}
                      openGroups={openGroups}
                      toggleGroup={toggleGroup}
                      messagesNonLus={messagesNonLus}
                    />
                  );
                }
                const item = entry;
                const actif = location.pathname === item.route;
                return (
                  <button
                    key={item.route}
                    onClick={() => { navigate(item.route); setMobileMenuOpen(false); }}
                    aria-current={actif ? 'page' : undefined}
                    className={`sidebar-item w-full text-left ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
                  >
                    <item.icone className="h-5 w-5" />
                    <span className="flex-1">{item.label}</span>
                  </button>
                );
              })}
            </nav>
            {userInfo && (
              <div className="p-3 border-t border-sidebar-border">
                <div className="flex items-center gap-2 px-3 py-2">
                  <AvatarDisplay
                    src={userInfo.avatarUrl}
                    prenom={userInfo.prenom}
                    nom={userInfo.nom}
                    size={32}
                    rounded={role === 'ADMIN_ETABLISSEMENT' ? 'lg' : 'full'}
                  />
                  <span className="text-sm font-medium text-sidebar-foreground truncate">
                    {userInfo.prenom} {userInfo.nom}
                  </span>
                </div>
              </div>
            )}
          </div>
        </>
      )}

      {/* ── Mobile bottom tab bar ── */}
      <nav
        className="fixed left-0 right-0 flex md:hidden z-50 no-print mobile-nav-bottom border-t border-border/80 bg-card/95 backdrop-blur-xl supports-[backdrop-filter]:bg-card/80 shadow-lg"
        style={{
          bottom: 'var(--viewport-offset-bottom, 0px)',
          height: 'calc(4rem + env(safe-area-inset-bottom))',
          paddingBottom: 'env(safe-area-inset-bottom)',
        }}
        role="navigation"
        aria-label="Navigation mobile"
      >
        {mobileItems.map((item) => {
          const actif = location.pathname === item.route;
          const isMsg = item.label === 'Messages';
          return (
            <button
              key={item.route}
              onClick={() => navigate(item.route)}
              aria-label={item.label}
              aria-current={actif ? 'page' : undefined}
              className={`flex-1 flex flex-col items-center justify-center gap-0.5 transition-colors duration-200 relative ${actif ? 'text-primary' : 'text-muted-foreground'}`}
              style={{ minWidth: 44, minHeight: 44 }}
            >
              <item.icone className="h-6 w-6" />
              {isMsg && messagesNonLus > 0 && (
                <span className="absolute top-1 right-1/2 translate-x-4 h-4 min-w-[16px] flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold px-1">
                  {messagesNonLus > 9 ? '9+' : messagesNonLus}
                </span>
              )}
              <span className="text-[11px] leading-tight">{item.label}</span>
            </button>
          );
        })}
      </nav>

      {/* ── Desktop sidebar ── */}
      <aside className="hidden md:flex fixed left-0 top-0 bottom-0 w-[260px] flex-col z-40 no-print" style={{ paddingTop: 'env(safe-area-inset-top)', background: 'linear-gradient(180deg, hsl(270 40% 97%) 0%, hsl(330 50% 96%) 100%)' }} role="navigation" aria-label="Sidebar">
        <div className="p-4 flex items-center justify-between gap-1">
          <div className="flex items-center gap-2 min-w-0">
            <HeartPulse className="h-7 w-7 text-primary flex-shrink-0" />
            <span className="text-xl font-bold text-primary truncate">Jolene</span>
          </div>
          <div className="flex items-center gap-1 flex-shrink-0">
            <BadgeNotification />
            <ThemeToggle className="text-sidebar-foreground hover:bg-sidebar-accent" />
            <button
              onClick={handleDeconnexion}
              aria-label="Se déconnecter"
              title="Se déconnecter"
              className="p-2 rounded-lg text-sidebar-foreground/60 hover:text-destructive hover:bg-destructive/10 transition"
            >
              <LogOut className="h-5 w-5" />
            </button>
          </div>
        </div>
        <nav className="flex-1 px-3 space-y-0.5 overflow-y-auto" aria-label="Menu principal">
          {sidebarEntries.map((entry) => {
            if (isGroup(entry)) {
              return (
                <SidebarGroup
                  key={entry.label}
                  group={entry}
                  location={location}
                  navigate={navigate}
                  openGroups={openGroups}
                  toggleGroup={toggleGroup}
                  messagesNonLus={messagesNonLus}
                />
              );
            }
            const item = entry;
            const actif = location.pathname === item.route;
            const isMsg = item.label === 'Messagerie';
            return (
              <button
                key={item.route}
                onClick={() => navigate(item.route)}
                aria-label={item.label}
                aria-current={actif ? 'page' : undefined}
                className={`sidebar-item w-full text-left ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
              >
                <item.icone className="h-5 w-5" />
                <span className="flex-1">{item.label}</span>
                {isMsg && messagesNonLus > 0 && (
                  <span className="h-5 min-w-[20px] flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold px-1">
                    {messagesNonLus > 9 ? '9+' : messagesNonLus}
                  </span>
                )}
              </button>
            );
          })}
        </nav>
        {userInfo && (
          <div className="p-3 border-t border-sidebar-border">
            <div className="flex items-center gap-2 px-3 py-2">
              <AvatarDisplay
                src={userInfo.avatarUrl}
                prenom={userInfo.prenom}
                nom={userInfo.nom}
                size={32}
                rounded={role === 'ADMIN_ETABLISSEMENT' ? 'lg' : 'full'}
              />
              <span className="text-sm font-medium text-sidebar-foreground truncate">
                {userInfo.prenom} {userInfo.nom}
              </span>
            </div>
          </div>
        )}
      </aside>
    </>
  );
}
