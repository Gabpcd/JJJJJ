import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BarChart3, Users, Shield, CreditCard, LogOut, HeartPulse, ShieldCheck, Mail, Code2, Building2, CalendarDays, Flame, ClipboardList, MessageCircle } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { FooterLegal } from '@/components/FooterLegal';
import { ThemeToggle } from '@/components/ThemeToggle';

const NAV_ADMIN = [
  { icone: BarChart3, label: 'Dashboard', route: '/admin' },
  { icone: Users, label: 'Utilisateurs', route: '/admin/utilisateurs' },
  { icone: Shield, label: 'Modération', route: '/admin/moderation' },
  { icone: CreditCard, label: 'Facturation', route: '/admin/facturation' },
  { icone: ClipboardList, label: 'Missions', route: '/admin/missions' },
  { icone: ShieldCheck, label: 'Conformité', route: '/admin/conformite' },
  { icone: Mail, label: 'Emails', route: '/admin/emails' },
  { icone: Code2, label: 'API', route: '/admin/api' },
  { icone: Building2, label: 'Groupes', route: '/admin/groupes' },
  { icone: CalendarDays, label: 'Calendrier', route: '/admin/calendrier' },
  { icone: Flame, label: 'Pool urgence', route: '/admin/pool-urgence' },
];

export function LayoutAdmin({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion } = useAuth();

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  return (
    <div className="min-h-screen bg-background flex">
      {/* Sidebar */}
      <aside className="hidden md:flex fixed left-0 top-0 bottom-0 w-[240px] bg-sidebar flex-col z-40">
        <div className="p-5 flex items-center justify-between border-b border-sidebar-border">
          <div className="flex items-center gap-2">
            <HeartPulse className="h-6 w-6 text-sidebar-primary" />
            <span className="text-lg font-bold text-sidebar-foreground">Admin</span>
          </div>
          <ThemeToggle className="text-sidebar-foreground hover:bg-sidebar-accent" />
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1">
          {NAV_ADMIN.map((item) => {
            const actif = item.route === '/admin'
              ? location.pathname === '/admin'
              : location.pathname.startsWith(item.route);
            return (
              <button
                key={item.route}
                onClick={() => navigate(item.route)}
                className={`sidebar-item w-full text-left ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
              >
                <item.icone className="h-5 w-5" />
                <span>{item.label}</span>
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

      {/* Mobile bottom nav */}
      <nav className="bottom-nav md:hidden">
        {NAV_ADMIN.map((item) => {
          const actif = item.route === '/admin'
            ? location.pathname === '/admin'
            : location.pathname.startsWith(item.route);
          return (
            <button key={item.route} onClick={() => navigate(item.route)} className={`bottom-nav-item ${actif ? 'bottom-nav-item-active' : ''}`}>
              <item.icone className="h-5 w-5" />
              <span className="bottom-nav-label">{item.label}</span>
            </button>
          );
        })}
      </nav>

      {/* Content */}
      <main className="flex-1 md:ml-[240px]">
        <div className="max-w-7xl mx-auto px-4 py-6 pb-24 md:pb-6">
          {children}
        </div>
        <FooterLegal />
      </main>
    </div>
  );
}
