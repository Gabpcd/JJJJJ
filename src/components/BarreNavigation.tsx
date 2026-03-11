import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { LucideIcon, Home, Search, FileText, CalendarDays, User, PlusCircle, List, ClipboardCheck, Settings, HeartPulse, LogOut } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { UserRole } from '@/lib/types';

interface NavItem { icone: LucideIcon; label: string; route: string; }

const NAV_SOIGNANT: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/soignant/tableau-de-bord' },
  { icone: Search, label: 'Missions', route: '/soignant/missions' },
  { icone: CalendarDays, label: 'Planning', route: '/soignant/planning' },
  { icone: FileText, label: 'Documents', route: '/soignant/documents' },
  { icone: User, label: 'Profil', route: '/soignant/profil' },
];

const NAV_ETABLISSEMENT: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/etablissement/tableau-de-bord' },
  { icone: PlusCircle, label: 'Publier', route: '/etablissement/missions/creer' },
  { icone: List, label: 'Missions', route: '/etablissement/missions' },
  { icone: ClipboardCheck, label: 'Présences', route: '/etablissement/presences' },
  { icone: Settings, label: 'Profil', route: '/etablissement/profil' },
];

const NAV_GROUPE: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/groupe/tableau-de-bord' },
  { icone: List, label: 'Établissements', route: '/groupe/etablissements' },
  { icone: Settings, label: 'Paramètres', route: '/groupe/parametres' },
];

function getNavItems(role: UserRole): NavItem[] {
  switch (role) {
    case 'SOIGNANT': return NAV_SOIGNANT;
    case 'ETABLISSEMENT': return NAV_ETABLISSEMENT;
    case 'ADMIN_GROUPE': return NAV_GROUPE;
  }
}

export function BarreNavigation({ role }: { role: UserRole }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion } = useAuth();
  const items = getNavItems(role);

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  return (
    <>
      <nav className="bottom-nav md:hidden">
        {items.map((item) => {
          const actif = location.pathname === item.route;
          return (
            <button key={item.route} onClick={() => navigate(item.route)} className={`bottom-nav-item ${actif ? 'bottom-nav-item-active' : ''}`}>
              <item.icone className="h-5 w-5" />
              <span className="bottom-nav-label">{item.label}</span>
            </button>
          );
        })}
      </nav>

      <aside className="hidden md:flex fixed left-0 top-0 bottom-0 w-[260px] bg-sidebar flex-col z-40">
        <div className="p-6 flex items-center gap-2">
          <HeartPulse className="h-7 w-7 text-sidebar-primary" />
          <span className="text-xl font-bold text-sidebar-foreground">Soin Direct</span>
        </div>
        <nav className="flex-1 px-3 space-y-1">
          {items.map((item) => {
            const actif = location.pathname === item.route;
            return (
              <button key={item.route} onClick={() => navigate(item.route)} className={`sidebar-item w-full text-left ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}>
                <item.icone className="h-5 w-5" /><span>{item.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="p-3 border-t border-sidebar-border">
          <button onClick={handleDeconnexion} className="sidebar-item w-full text-left text-sidebar-foreground/50 hover:text-destructive hover:bg-sidebar-accent">
            <LogOut className="h-5 w-5" /><span>Déconnexion</span>
          </button>
        </div>
      </aside>
    </>
  );
}
