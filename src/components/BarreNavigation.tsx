import React, { useState, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { LucideIcon, Home, Search, FileText, CalendarDays, User, PlusCircle, List, ClipboardCheck, Settings, HeartPulse, LogOut, MapPin, Banknote, Clock, CreditCard, FileSpreadsheet, Rocket, Bell, Ban, MapPinned, Crown, BarChart3, Calculator, Code2, Flame, Gift, MessageCircle, GraduationCap, ClipboardList, Building2, Users, Scale, ChevronDown, Activity, Briefcase, Zap, Shield, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { UserRole } from '@/lib/types';
import { PROFESSIONS_NON_LIBERAL } from '@/lib/constantes';
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
  { icone: Search, label: 'Missions', route: '/soignant/missions' },
  { icone: MapPin, label: 'Présences', route: '/soignant/presences' },
  { icone: FileText, label: 'Documents', route: '/soignant/documents' },
  { icone: User, label: 'Profil', route: '/soignant/profil' },
];

const NAV_ETABLISSEMENT_MOBILE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
  { icone: ClipboardList, label: 'Missions', route: '/etablissement/missions' },
  { icone: MessageCircle, label: 'Messages', route: '/etablissement/messagerie' },
  { icone: Users, label: 'Pool', route: '/etablissement/pool-urgence' },
  { icone: Building2, label: 'Profil', route: '/etablissement/profil' },
];

/* ── Desktop sidebars (grouped) ── */
function getSoignantSidebar(isLiberal: boolean, showLiberalPath: boolean): SidebarEntry[] {
  const entries: SidebarEntry[] = [
    { icone: Home, label: 'Accueil', route: '/soignant/tableau-de-bord' },
    {
      icone: Search, label: 'Missions', items: [
        { icone: Search, label: 'Missions disponibles', route: '/soignant/missions' },
        { icone: MapPinned, label: 'Recherche avancée', route: '/soignant/recherche-missions' },
        { icone: CalendarDays, label: 'Mon planning', route: '/soignant/planning' },
        { icone: RefreshCw, label: 'Sync Calendrier', route: '/soignant/calendrier-sync' },
        { icone: Clock, label: 'Historique', route: '/soignant/historique-missions' },
      ],
    },
    {
      icone: Activity, label: 'Mon activité', items: [
        { icone: MapPin, label: 'Présences', route: '/soignant/presences' },
        { icone: Banknote, label: 'Mes gains', route: '/soignant/mes-gains' },
        { icone: FileText, label: 'Contrats', route: '/soignant/contrats' },
        { icone: FileText, label: 'Documents', route: '/soignant/documents' },
        { icone: FileText, label: 'Attestation heures', route: '/soignant/attestation-heures' },
        { icone: Scale, label: 'Litiges', route: '/soignant/litiges' },
      ],
    },
    { icone: MessageCircle, label: 'Messagerie', route: '/soignant/messagerie' },
  ];

  // Carrière & Finances
  const carriereItems: NavItem[] = [];
  if (isLiberal) {
    carriereItems.push({ icone: Calculator, label: 'Mes charges', route: '/soignant/charges' });
  }
  carriereItems.push({ icone: CreditCard, label: 'Paiements Stripe', route: '/soignant/stripe-connect' });
  carriereItems.push({ icone: FileText, label: 'Factures honoraires', route: '/soignant/mes-factures-honoraires' });
  carriereItems.push({ icone: Zap, label: 'Paiement rapide', route: '/soignant/mes-avances' });
  carriereItems.push({ icone: FileText, label: 'Mandat facturation', route: '/soignant/mandat-facturation' });
  entries.push({ icone: Briefcase, label: 'Finances', items: carriereItems });

  // Évolution professionnelle
  const evolutionItems: NavItem[] = [];
  if (showLiberalPath) {
    evolutionItems.push({ icone: Rocket, label: 'Passer en libéral', route: '/soignant/passer-en-liberal' });
  }
  evolutionItems.push({ icone: GraduationCap, label: 'Parcours 3 200h', route: '/soignant/parcours-3200h' });
  evolutionItems.push({ icone: Shield, label: 'Prévoyance', route: '/soignant/prevoyance' });
  entries.push({ icone: GraduationCap, label: 'Évolution pro', items: evolutionItems });

  // Profil & Réglages
  entries.push({
    icone: User, label: 'Profil & Réglages', items: [
      { icone: User, label: 'Mon profil', route: '/soignant/profil' },
      { icone: Activity, label: 'Score fiabilité', route: '/soignant/fiabilite' },
      { icone: Shield, label: 'Conformité', route: '/soignant/conformite' },
      { icone: Bell, label: 'Notifications', route: '/soignant/notifications' },
      { icone: Gift, label: 'Parrainage', route: '/soignant/parrainage' },
      { icone: Flame, label: 'Urgences & exclusions', route: '/soignant/exclusions' },
    ],
  });

  return entries;
}

function getEtablissementSidebar(): SidebarEntry[] {
  return [
    { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
    {
      icone: ClipboardList, label: 'Missions', items: [
        { icone: PlusCircle, label: 'Publier une mission', route: '/etablissement/missions/creer' },
        { icone: List, label: 'Liste des missions', route: '/etablissement/missions' },
        { icone: Flame, label: 'Pool urgence', route: '/etablissement/pool-urgence' },
      ],
    },
    {
      icone: ClipboardCheck, label: 'Gestion', items: [
        { icone: ClipboardCheck, label: 'Présences', route: '/etablissement/presences' },
        { icone: FileText, label: 'Contrats', route: '/etablissement/contrats' },
        { icone: Scale, label: 'Litiges', route: '/etablissement/litiges' },
        { icone: FileSpreadsheet, label: 'Export Paie', route: '/etablissement/export-paie' },
        { icone: BarChart3, label: 'Tableau RH', route: '/etablissement/rh' },
        { icone: Activity, label: 'Analytics', route: '/etablissement/analytics' },
        { icone: Clock, label: 'Shifts', route: '/etablissement/shifts' },
      ],
    },
    {
      icone: Banknote, label: 'Finances', items: [
        { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
        { icone: FileText, label: 'Obligations', route: '/etablissement/obligations' },
        { icone: Shield, label: 'Assurance', route: '/etablissement/assurance' },
        { icone: FileText, label: 'Contrat plateforme', route: '/etablissement/contrat-plateforme' },
        { icone: Building2, label: 'Chorus Pro', route: '/etablissement/chorus-config' },
      ],
    },
    { icone: MessageCircle, label: 'Messagerie', route: '/etablissement/messagerie' },
    {
      icone: Settings, label: 'Paramètres', items: [
        { icone: Building2, label: 'Profil établissement', route: '/etablissement/profil' },
        { icone: Settings, label: 'Mon groupe', route: '/etablissement/mon-groupe' },
        { icone: Code2, label: 'API', route: '/etablissement/api' },
        { icone: Ban, label: 'Exclusions', route: '/etablissement/exclusions' },
        { icone: Bell, label: 'Notifications', route: '/etablissement/notifications' },
      ],
    },
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
function SidebarGroup({ group, location, navigate, openGroups, toggleGroup, messagesNonLus, contratNonValide }: {
  group: NavGroup;
  location: ReturnType<typeof useLocation>;
  navigate: ReturnType<typeof useNavigate>;
  openGroups: Set<string>;
  toggleGroup: (label: string) => void;
  messagesNonLus: number;
  contratNonValide: boolean;
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
            const isContrat = item.route === '/etablissement/contrat-plateforme';
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
                {isContrat && contratNonValide && (
                  <span className="h-5 min-w-[20px] flex items-center justify-center rounded-full bg-warning text-warning-foreground text-[11px] font-bold px-1">!</span>
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
  const [isLiberal, setIsLiberal] = useState(false);
  const [showLiberalPath, setShowLiberalPath] = useState(false);
  const [userInfo, setUserInfo] = useState<{ prenom?: string; nom?: string; avatarUrl?: string } | null>(null);
  const [contratNonValide, setContratNonValide] = useState(false);
  const { count: messagesNonLus } = useMessagesNonLus();
  const [openGroups, setOpenGroups] = useState<Set<string>>(new Set());

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
      supabase.from('soignants').select('profession, heures_cumulees, statut_liberal, prenom, nom, avatar_url').eq('id', user.id).single()
        .then(({ data }) => {
          if (!data) return;
          setUserInfo({ prenom: data.prenom, nom: data.nom, avatarUrl: (data as any).avatar_url });
          if (data.statut_liberal === 'ACTIF') setIsLiberal(true);
          if (!PROFESSIONS_NON_LIBERAL.includes(data.profession) && (data.heures_cumulees || 0) >= 800 && data.statut_liberal !== 'ACTIF') {
            setShowLiberalPath(true);
          }
        });
    } else if (role === 'ADMIN_ETABLISSEMENT') {
      supabase.from('etablissements').select('nom, logo_url, contrat_valide').eq('id', user.id).single()
        .then(({ data }) => {
          if (data) {
            setUserInfo({ prenom: data.nom, nom: '', avatarUrl: (data as any).logo_url });
            setContratNonValide(!(data as any).contrat_valide);
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
      {/* ── Mobile bottom tab bar ── */}
      <nav className="fixed bottom-0 left-0 right-0 flex md:hidden z-50 bg-card dark:bg-accent-foreground/5 shadow-lg no-print" style={{ height: 'calc(4rem + env(safe-area-inset-bottom))', paddingBottom: 'env(safe-area-inset-bottom)', borderTop: '2px solid', borderImage: 'linear-gradient(90deg, hsl(330 85% 60%), hsl(270 60% 50%), hsl(215 80% 55%)) 1' }} role="navigation" aria-label="Navigation mobile">
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
        <div className="p-6 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <HeartPulse className="h-7 w-7 text-primary" />
            <span className="text-xl font-bold text-primary">Jolene</span>
          </div>
          <BadgeNotification />
          <ThemeToggle className="text-sidebar-foreground hover:bg-sidebar-accent" />
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
                  contratNonValide={contratNonValide}
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
        <div className="p-3 border-t border-sidebar-border space-y-2">
          {userInfo && (
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
          )}
          <button onClick={handleDeconnexion} aria-label="Se déconnecter" className="sidebar-item w-full text-left text-sidebar-foreground/50 hover:text-destructive hover:bg-sidebar-accent">
            <LogOut className="h-5 w-5" /><span>Déconnexion</span>
          </button>
        </div>
      </aside>
    </>
  );
}
