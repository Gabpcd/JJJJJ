import React, { useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BarChart3, Users, Shield, CreditCard, LogOut, HeartPulse, ShieldCheck, Mail, Code2, Building2, CalendarDays, Flame, ClipboardList, MessageCircle, Menu, X, Home, Coins } from 'lucide-react';
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
  { icone: MessageCircle, label: 'Messagerie', route: '/admin/messagerie' },
];

const NAV_ADMIN_MOBILE_MAIN = [
  { icone: Home, label: 'Accueil', route: '/admin' },
  { icone: Users, label: 'Utilisateurs', route: '/admin/utilisateurs' },
  { icone: ClipboardList, label: 'Missions', route: '/admin/missions' },
  { icone: MessageCircle, label: 'Messagerie', route: '/admin/messagerie' },
];

export function LayoutAdmin({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion } = useAuth();
  const [menuOuvert, setMenuOuvert] = useState(false);

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  const isActive = (route: string) =>
    route === '/admin' ? location.pathname === '/admin' : location.pathname.startsWith(route);

  return (
    <div className="min-h-screen bg-background flex">
      {/* Sidebar desktop */}
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
            const actif = isActive(item.route);
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

      {/* Mobile bottom nav — 5 tabs: 4 main + "Plus" */}
      <nav
        className="fixed bottom-0 left-0 right-0 flex md:hidden z-50 bg-card border-t border-border shadow-lg"
        style={{ height: 'calc(4rem + env(safe-area-inset-bottom))', paddingBottom: 'env(safe-area-inset-bottom)' }}
        role="navigation"
        aria-label="Navigation mobile admin"
      >
        {NAV_ADMIN_MOBILE_MAIN.map((item) => {
          const actif = isActive(item.route);
          return (
            <button
              key={item.route}
              onClick={() => { setMenuOuvert(false); navigate(item.route); }}
              className={`flex-1 flex flex-col items-center justify-center gap-0.5 transition-colors ${actif ? 'text-primary' : 'text-muted-foreground'}`}
              style={{ minWidth: 44, minHeight: 44 }}
            >
              <item.icone className="h-6 w-6" />
              <span className="text-[10px] leading-tight">{item.label}</span>
            </button>
          );
        })}
        {/* "Plus" button */}
        <button
          onClick={() => setMenuOuvert(!menuOuvert)}
          className={`flex-1 flex flex-col items-center justify-center gap-0.5 transition-colors ${menuOuvert ? 'text-primary' : 'text-muted-foreground'}`}
          style={{ minWidth: 44, minHeight: 44 }}
        >
          {menuOuvert ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
          <span className="text-[10px] leading-tight">Plus</span>
        </button>
      </nav>

      {/* "Plus" overlay menu */}
      {menuOuvert && (
        <div className="fixed inset-0 z-40 md:hidden" onClick={() => setMenuOuvert(false)}>
          <div className="absolute inset-0 bg-foreground/40" />
          <div
            className="absolute bottom-20 left-4 right-4 bg-card rounded-2xl shadow-xl border border-border p-3 grid grid-cols-3 gap-2"
            style={{ marginBottom: 'env(safe-area-inset-bottom)' }}
            onClick={(e) => e.stopPropagation()}
          >
            {NAV_ADMIN.filter(
              (item) => !NAV_ADMIN_MOBILE_MAIN.some((m) => m.route === item.route)
            ).map((item) => {
              const actif = isActive(item.route);
              return (
                <button
                  key={item.route}
                  onClick={() => { setMenuOuvert(false); navigate(item.route); }}
                  className={`flex flex-col items-center gap-1 p-3 rounded-xl transition-colors ${actif ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:bg-muted'}`}
                  style={{ minHeight: 44 }}
                >
                  <item.icone className="h-5 w-5" />
                  <span className="text-[10px] leading-tight text-center">{item.label}</span>
                </button>
              );
            })}
            <button
              onClick={() => { setMenuOuvert(false); handleDeconnexion(); }}
              className="flex flex-col items-center gap-1 p-3 rounded-xl text-destructive hover:bg-destructive/10 transition-colors"
              style={{ minHeight: 44 }}
            >
              <LogOut className="h-5 w-5" />
              <span className="text-[10px] leading-tight">Déconnexion</span>
            </button>
          </div>
        </div>
      )}

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
