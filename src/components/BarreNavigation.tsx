import React, { useState, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { LucideIcon, Home, Search, FileText, CalendarDays, User, PlusCircle, List, ClipboardCheck, Settings, HeartPulse, LogOut, MapPin, Banknote, Clock, CreditCard, FileSpreadsheet, Rocket, Bell, Ban, MapPinned, Crown, BarChart3, Calculator, Code2, Flame, Gift, MessageCircle, GraduationCap, ClipboardList, Building2, Users, Scale } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { UserRole } from '@/lib/types';
import { PROFESSIONS_NON_LIBERAL } from '@/lib/constantes';
import { supabase } from '@/integrations/supabase/client';
import { BadgeNotification } from '@/components/PanneauNotifications';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { ThemeToggle } from '@/components/ThemeToggle';
import { useMessagesNonLus } from '@/hooks/useMessagesNonLus';

interface NavItem { icone: LucideIcon; label: string; route: string; }

const NAV_SOIGNANT_MOBILE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/soignant/tableau-de-bord' },
  { icone: Search, label: 'Missions', route: '/soignant/missions' },
  { icone: MessageCircle, label: 'Messagerie', route: '/soignant/messagerie' },
  { icone: CalendarDays, label: 'Planning', route: '/soignant/planning' },
  { icone: User, label: 'Profil', route: '/soignant/profil' },
];

const NAV_ETABLISSEMENT_MOBILE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
  { icone: ClipboardList, label: 'Missions', route: '/etablissement/missions' },
  { icone: MessageCircle, label: 'Messagerie', route: '/etablissement/messagerie' },
  { icone: Users, label: 'Pool', route: '/etablissement/pool-urgence' },
  { icone: Building2, label: 'Profil', route: '/etablissement/profil' },
];

const NAV_SOIGNANT_BASE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/soignant/tableau-de-bord' },
  { icone: Search, label: 'Missions', route: '/soignant/missions' },
  { icone: MapPinned, label: 'Recherche', route: '/soignant/recherche-missions' },
  { icone: CalendarDays, label: 'Planning', route: '/soignant/planning' },
  { icone: FileText, label: 'Mes contrats', route: '/soignant/contrats' },
  { icone: MapPin, label: 'Présences', route: '/soignant/presences' },
  { icone: Banknote, label: 'Gains', route: '/soignant/mes-gains' },
  { icone: FileText, label: 'Documents', route: '/soignant/documents' },
  { icone: GraduationCap, label: 'Parcours libéral', route: '/soignant/parcours-3200h' },
  { icone: MessageCircle, label: 'Messagerie', route: '/soignant/messagerie' },
  { icone: Scale, label: 'Litiges', route: '/soignant/litiges' },
  { icone: CreditCard, label: 'Mon compte', route: '/soignant/stripe-connect' },
  { icone: Gift, label: 'Parrainage', route: '/soignant/parrainage' },
  { icone: Crown, label: 'Premium', route: '/soignant/premium' },
  { icone: Bell, label: 'Notifications', route: '/soignant/notifications' },
  { icone: User, label: 'Profil', route: '/soignant/profil' },
];

const NAV_ETABLISSEMENT: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
  { icone: PlusCircle, label: 'Publier', route: '/etablissement/missions/creer' },
  { icone: List, label: 'Missions', route: '/etablissement/missions' },
  { icone: Flame, label: 'Pool urgence 🚨', route: '/etablissement/pool-urgence' },
  { icone: FileText, label: 'Contrats', route: '/etablissement/contrats' },
  { icone: ClipboardCheck, label: 'Présences', route: '/etablissement/presences' },
  { icone: FileSpreadsheet, label: 'Export Paie', route: '/etablissement/export-paie' },
  { icone: BarChart3, label: 'Gestion RH', route: '/etablissement/rh' },
  { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
  { icone: FileText, label: 'Contrat plateforme', route: '/etablissement/contrat-plateforme' },
  { icone: Settings, label: 'Mon groupe', route: '/etablissement/mon-groupe' },
  { icone: Code2, label: 'API', route: '/etablissement/api' },
  { icone: MessageCircle, label: 'Messagerie', route: '/etablissement/messagerie' },
  { icone: Scale, label: 'Litiges', route: '/etablissement/litiges' },
  { icone: Ban, label: 'Exclusions', route: '/etablissement/exclusions' },
  { icone: Crown, label: 'Premium', route: '/etablissement/premium' },
  { icone: Bell, label: 'Notifications', route: '/etablissement/notifications' },
  { icone: User, label: 'Profil', route: '/etablissement/profil' },
];

const NAV_GROUPE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/groupe/tableau-de-bord' },
  { icone: List, label: 'Établissements', route: '/groupe/etablissements' },
  { icone: Settings, label: 'Paramètres', route: '/groupe/parametres' },
];

function getNavItems(role: UserRole, isLiberal?: boolean): NavItem[] {
  switch (role) {
    case 'SOIGNANT': {
      const items = [...NAV_SOIGNANT_BASE];
      if (isLiberal) {
        const gainsIdx = items.findIndex(i => i.label === 'Gains');
        items.splice(gainsIdx + 1, 0, { icone: Calculator, label: 'Mes charges', route: '/soignant/charges' });
      }
      return items;
    }
    case 'ADMIN_ETABLISSEMENT': return NAV_ETABLISSEMENT;
    case 'ADMIN_GROUPE': return NAV_GROUPE;
    case 'ADMIN_PLATEFORME': return [];
    default: return [];
  }
}

function getMobileNavItems(role: UserRole): NavItem[] {
  switch (role) {
    case 'SOIGNANT': return NAV_SOIGNANT_MOBILE;
    case 'ADMIN_ETABLISSEMENT': return NAV_ETABLISSEMENT_MOBILE;
    case 'ADMIN_GROUPE': return NAV_GROUPE;
    case 'ADMIN_PLATEFORME': return [];
    default: return [];
  }
}

export function BarreNavigation({ role }: { role: UserRole }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion, user } = useAuth();
  const [showLiberal, setShowLiberal] = useState(false);
  const [isLiberal, setIsLiberal] = useState(false);
  const [userInfo, setUserInfo] = useState<{ prenom?: string; nom?: string; avatarUrl?: string } | null>(null);
  const { count: messagesNonLus } = useMessagesNonLus();

  useEffect(() => {
    if (!user) return;
    if (role === 'SOIGNANT') {
      supabase.from('soignants').select('profession, heures_cumulees, statut_liberal, prenom, nom, avatar_url').eq('id', user.id).single()
        .then(({ data }) => {
          if (!data) return;
          setUserInfo({ prenom: data.prenom, nom: data.nom, avatarUrl: (data as any).avatar_url });
          if (data.statut_liberal === 'ACTIF') {
            setIsLiberal(true);
          }
          if (!PROFESSIONS_NON_LIBERAL.includes(data.profession) && (data.heures_cumulees || 0) >= 800 && data.statut_liberal !== 'ACTIF') {
            setShowLiberal(true);
          }
        });
    } else if (role === 'ADMIN_ETABLISSEMENT') {
      supabase.from('etablissements').select('nom, logo_url').eq('id', user.id).single()
        .then(({ data }) => {
          if (data) setUserInfo({ prenom: data.nom, nom: '', avatarUrl: (data as any).logo_url });
        });
    }
  }, [role, user]);

  const baseItems = getNavItems(role, isLiberal);
  let items = baseItems;
  if (role === 'SOIGNANT' && showLiberal) {
    const notifIdx = items.findIndex(i => i.label === 'Notifications');
    const liberalItem = { icone: Rocket, label: 'Passer en libéral', route: '/soignant/passer-en-liberal' };
    items = [...items.slice(0, notifIdx), liberalItem, ...items.slice(notifIdx)];
  }
  const mobileItems = getMobileNavItems(role);

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  return (
    <>
      {/* ── Mobile bottom tab bar ── */}
      <nav className="fixed bottom-0 left-0 right-0 flex md:hidden z-50 bg-card dark:bg-accent-foreground/5 border-t border-border shadow-lg no-print" style={{ height: 'calc(4rem + env(safe-area-inset-bottom))', paddingBottom: 'env(safe-area-inset-bottom)' }} role="navigation" aria-label="Navigation mobile">
        {mobileItems.map((item) => {
          const actif = location.pathname === item.route;
          const isMsg = item.label === 'Messagerie';
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
                <span className="absolute top-1 right-1/2 translate-x-4 h-4 min-w-[16px] flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[9px] font-bold px-1">
                  {messagesNonLus > 9 ? '9+' : messagesNonLus}
                </span>
              )}
              <span className="text-[10px] leading-tight">{item.label}</span>
            </button>
          );
        })}
      </nav>

      {/* ── Desktop sidebar ── */}
      <aside className="hidden md:flex fixed left-0 top-0 bottom-0 w-[260px] bg-sidebar flex-col z-40 no-print" style={{ paddingTop: 'env(safe-area-inset-top)' }} role="navigation" aria-label="Sidebar">
        <div className="p-6 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <HeartPulse className="h-7 w-7 text-sidebar-primary" />
            <span className="text-xl font-bold text-sidebar-foreground">Jolene</span>
          </div>
          <BadgeNotification />
          <ThemeToggle className="text-sidebar-foreground hover:bg-sidebar-accent" />
        </div>
        <nav className="flex-1 px-3 space-y-1 overflow-y-auto" aria-label="Menu principal">
          {items.map((item) => {
            const actif = location.pathname === item.route;
            const isMsgRoute = item.label === 'Messagerie';
            return (
              <button key={item.route} onClick={() => navigate(item.route)} aria-label={item.label} aria-current={actif ? 'page' : undefined} className={`sidebar-item w-full text-left ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}>
                <item.icone className="h-5 w-5" />
                <span className="flex-1">{item.label}</span>
                {isMsgRoute && messagesNonLus > 0 && (
                  <span className="h-5 min-w-[20px] flex items-center justify-center rounded-full bg-destructive text-white text-[10px] font-bold px-1">
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
