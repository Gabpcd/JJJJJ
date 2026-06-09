import React, { useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { LucideIcon, BarChart3, Users, Shield, CreditCard, LogOut, HeartPulse, ShieldCheck, Mail, Code2, Building2, CalendarDays, Flame, ClipboardList, MessageCircle, Menu, X, Home, Coins, AlertTriangle, FileCheck, Zap, TrendingUp, ChevronDown, FileStack, Scale, Star, FileSignature, Activity, Flag } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { FooterLegal } from '@/components/FooterLegal';
import { ThemeToggle } from '@/components/ThemeToggle';
import { useScrollDirection } from '@/hooks/useScrollDirection';
import { cn } from '@/lib/utils';

/* ── Types ── */
interface NavItem { icone: LucideIcon; label: string; route: string; }
interface NavGroup { icone: LucideIcon; label: string; items: NavItem[]; }
type SidebarEntry = NavItem | NavGroup;

function isGroup(e: SidebarEntry): e is NavGroup { return 'items' in e; }

/* ── Sidebar groupée (même pattern que soignant/etab) ── */
const NAV_ADMIN_GROUPED: SidebarEntry[] = [
  { icone: BarChart3, label: 'Dashboard', route: '/admin' },
  {
    icone: Users, label: 'Utilisateurs', items: [
      { icone: Users, label: 'Tous les utilisateurs', route: '/admin/utilisateurs' },
      { icone: Shield, label: 'Modération', route: '/admin/moderation' },
      { icone: Flag, label: 'Signalements', route: '/admin/signalements' },
      { icone: ShieldCheck, label: 'Vérif. établissements', route: '/admin/verification-etablissements' },
      { icone: FileCheck, label: 'Heures externes (3200h)', route: '/admin/heures-externes' },
      { icone: MessageCircle, label: 'Réclamations', route: '/admin/reclamations' },
      { icone: Star, label: 'Réclamations score', route: '/admin/reclamations-score' },
      { icone: ShieldCheck, label: 'Triage des scores', route: '/admin/scores' },
      { icone: Building2, label: 'Groupes santé', route: '/admin/groupes' },
    ],
  },
  {
    icone: ClipboardList, label: 'Missions', items: [
      { icone: ClipboardList, label: 'Toutes les missions', route: '/admin/missions' },
      { icone: Flame, label: 'Pool urgence', route: '/admin/pool-urgence' },
      { icone: CalendarDays, label: 'Calendrier', route: '/admin/calendrier' },
      { icone: CalendarDays, label: 'Planning global', route: '/admin/planning-global' },
      { icone: AlertTriangle, label: 'Alertes pointage', route: '/admin/alertes-pointage' },
    ],
  },
  {
    icone: Scale, label: 'Litiges & contrats', items: [
      { icone: Scale, label: 'Litiges', route: '/admin/litiges' },
      { icone: FileSignature, label: 'Contrats', route: '/admin/contrats' },
      { icone: FileStack, label: 'Templates contrats', route: '/admin/templates-contrats' },
    ],
  },
  {
    icone: Coins, label: 'Finances', items: [
      { icone: Coins, label: 'Vue d\'ensemble', route: '/admin/finances' },
      { icone: CreditCard, label: 'Facturation', route: '/admin/facturation' },
      { icone: AlertTriangle, label: 'Impayées', route: '/admin/impayees' },
      { icone: FileCheck, label: 'Mandats facturation', route: '/admin/mandats-facturation' },
      { icone: Zap, label: 'Affacturage', route: '/admin/affacturage' },
      { icone: FileStack, label: 'Chorus Pro', route: '/admin/chorus-pro' },
      { icone: TrendingUp, label: 'Cohort & Economics', route: '/admin/cohort' },
      { icone: Coins, label: 'Taux commission', route: '/admin/taux-commission' },
    ],
  },
  { icone: MessageCircle, label: 'Messagerie', route: '/admin/messagerie' },
  {
    icone: ShieldCheck, label: 'Conformité & Technique', items: [
      { icone: ShieldCheck, label: 'Conformité', route: '/admin/conformite' },
      { icone: Shield, label: 'Audit Logs', route: '/admin/audit' },
      { icone: Shield, label: 'Audit RLS', route: '/admin/audit-rls' },
      { icone: FileCheck, label: 'DPIA', route: '/admin/dpia' },
      { icone: Shield, label: 'Outils RGPD', route: '/admin/rgpd-tools' },
      { icone: Zap, label: 'Externalisations', route: '/admin/externalisations-actions' },
      { icone: Activity, label: 'Statut système', route: '/admin/status' },
      { icone: Mail, label: 'Emails', route: '/admin/emails' },
      { icone: Code2, label: 'API', route: '/admin/api' },
      { icone: HeartPulse, label: 'Healthcheck', route: '/admin/healthcheck' },
      { icone: Code2, label: 'Démo', route: '/admin/demo' },
    ],
  },
];

/* ── Mobile bottom bar (5 items) ── */
const NAV_ADMIN_MOBILE_MAIN: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/admin' },
  { icone: Users, label: 'Utilisateurs', route: '/admin/utilisateurs' },
  { icone: ClipboardList, label: 'Missions', route: '/admin/missions' },
  { icone: MessageCircle, label: 'Messages', route: '/admin/messagerie' },
];

/* ── All flat items for mobile "Plus" overlay ── */
function flattenEntries(entries: SidebarEntry[]): NavItem[] {
  const flat: NavItem[] = [];
  for (const e of entries) {
    if (isGroup(e)) {
      for (const item of e.items) flat.push(item);
    } else {
      flat.push(e);
    }
  }
  return flat;
}

/* ── Collapsible sidebar group ── */
function SidebarGroup({
  group,
  isActive,
  navigate,
}: {
  group: NavGroup;
  isActive: (route: string) => boolean;
  navigate: (route: string) => void;
}) {
  const hasActiveChild = group.items.some(i => isActive(i.route));
  const [open, setOpen] = useState(hasActiveChild);

  return (
    <div>
      <button
        onClick={() => setOpen(!open)}
        className={`sidebar-item w-full text-left justify-between ${hasActiveChild ? 'text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
      >
        <div className="flex items-center gap-3">
          <group.icone className="h-5 w-5" />
          <span>{group.label}</span>
        </div>
        <ChevronDown className={`h-4 w-4 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <div className="ml-4 pl-3 border-l border-sidebar-border space-y-0.5 mt-0.5 mb-1">
          {group.items.map(item => {
            const actif = isActive(item.route);
            return (
              <button
                key={item.route}
                onClick={() => navigate(item.route)}
                className={`sidebar-item w-full text-left text-sm ${actif ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/60 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
              >
                <item.icone className="h-4 w-4" />
                <span>{item.label}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function LayoutAdmin({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion } = useAuth();
  const [menuOuvert, setMenuOuvert] = useState(false);
  // Sprint 8.5-A PR 1 — Header mobile se cache au scroll down, réapparaît au scroll up
  const scrollDirection = useScrollDirection();

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  const isActive = (route: string) =>
    route === '/admin' ? location.pathname === '/admin' : location.pathname.startsWith(route);

  const allFlatItems = flattenEntries(NAV_ADMIN_GROUPED);
  const mobileExtraItems = allFlatItems.filter(
    item => !NAV_ADMIN_MOBILE_MAIN.some(m => m.route === item.route)
  );

  return (
    <div className="min-h-[100dvh] bg-background flex">
      {/* ── Sidebar desktop (grouped) ── */}
      <aside className="hidden md:flex fixed left-0 top-0 bottom-0 w-[240px] bg-sidebar flex-col z-40">
        <div className="p-5 flex items-center justify-between border-b border-sidebar-border">
          <div className="flex items-center gap-2">
            <HeartPulse className="h-6 w-6 text-sidebar-primary" />
            <span className="text-lg font-bold text-sidebar-foreground">Admin</span>
          </div>
          <ThemeToggle className="text-sidebar-foreground hover:bg-sidebar-accent" />
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
          {NAV_ADMIN_GROUPED.map((entry, i) =>
            isGroup(entry) ? (
              <SidebarGroup key={i} group={entry} isActive={isActive} navigate={navigate} />
            ) : (
              <button
                key={entry.route}
                onClick={() => navigate(entry.route)}
                className={`sidebar-item w-full text-left ${isActive(entry.route) ? 'bg-sidebar-accent text-sidebar-primary' : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground'}`}
              >
                <entry.icone className="h-5 w-5" />
                <span>{entry.label}</span>
              </button>
            )
          )}
        </nav>
        <div className="p-3 border-t border-sidebar-border">
          <button onClick={handleDeconnexion} className="sidebar-item w-full text-left text-sidebar-foreground/50 hover:text-destructive hover:bg-sidebar-accent">
            <LogOut className="h-5 w-5" /><span>Déconnexion</span>
          </button>
        </div>
      </aside>

      {/* ── Mobile: top header with logout (auto-hide on scroll down)
           Sprint 9-D : glassmorphism subtle (bg-card/85 + backdrop-blur) ── */}
      <header
        className={cn(
          'fixed top-0 left-0 right-0 h-14 flex md:hidden items-center justify-between px-4 z-50',
          'bg-card/85 backdrop-blur-xl supports-[backdrop-filter]:bg-card/70 border-b border-jolene-rose-200/40',
          'transition-transform duration-200 motion-reduce:transition-none',
          scrollDirection === 'down' ? '-translate-y-full' : 'translate-y-0',
        )}
      >
        <div className="flex items-center gap-2">
          <HeartPulse className="h-5 w-5 text-primary" />
          <span className="font-bold text-foreground">Admin</span>
        </div>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <button onClick={handleDeconnexion} className="p-2 text-muted-foreground hover:text-destructive transition-colors" title="Déconnexion">
            <LogOut className="h-5 w-5" />
          </button>
        </div>
      </header>

      {/* ── Mobile bottom nav (Sprint 9-D : glassmorphism subtle) ── */}
      <nav
        className="fixed bottom-0 left-0 right-0 flex md:hidden z-50 bg-card/85 backdrop-blur-xl supports-[backdrop-filter]:bg-card/70 border-t border-jolene-rose-200/40 shadow-lg"
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
        <button
          onClick={() => setMenuOuvert(!menuOuvert)}
          className={`flex-1 flex flex-col items-center justify-center gap-0.5 transition-colors ${menuOuvert ? 'text-primary' : 'text-muted-foreground'}`}
          style={{ minWidth: 44, minHeight: 44 }}
        >
          {menuOuvert ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
          <span className="text-[10px] leading-tight">Plus</span>
        </button>
      </nav>

      {/* ── Mobile "Plus" overlay ── */}
      {menuOuvert && (
        <div className="fixed inset-0 z-40 md:hidden" onClick={() => setMenuOuvert(false)}>
          <div className="absolute inset-0 bg-foreground/40" />
          <div
            className="absolute bottom-20 left-4 right-4 bg-card rounded-2xl shadow-xl border border-border p-3 grid grid-cols-3 gap-2 max-h-[60vh] overflow-y-auto"
            style={{ marginBottom: 'env(safe-area-inset-bottom)' }}
            onClick={(e) => e.stopPropagation()}
          >
            {mobileExtraItems.map((item) => {
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
          </div>
        </div>
      )}

      {/* ── Content ── */}
      <main
        id="main-content"
        tabIndex={-1}
        className="flex-1 md:ml-[240px] mt-14 md:mt-0 overflow-x-hidden"
      >
        <div className="max-w-7xl mx-auto px-4 py-6 pb-24 md:pb-6">
          {children}
        </div>
        <FooterLegal />
      </main>
    </div>
  );
}
