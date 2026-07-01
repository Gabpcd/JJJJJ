import React, { useState, useMemo, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { LucideIcon, Gift, BarChart3, Users, Shield, CreditCard, LogOut, HeartPulse, ShieldCheck, Mail, Code2, Building2, CalendarDays, Flame, ClipboardList, MessageCircle, Menu, X, Home, Coins, AlertTriangle, FileCheck, Zap, TrendingUp, ChevronDown, FileStack, Scale, Star, FileSignature, Activity, Flag, Rocket, UserPlus, Megaphone, Settings, Search, Trash2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { ThemeToggle } from '@/components/ThemeToggle';
import { RechercheGlobaleAdmin } from '@/components/admin/RechercheGlobaleAdmin';
import { GardeMfaAdmin } from '@/components/admin/GardeMfaAdmin';
import { useScrollDirection } from '@/hooks/useScrollDirection';

import { useAccesAdmin } from '@/hooks/useAccesAdmin';
import { cn } from '@/lib/utils';

/* ── Types ── */
// `acces` = périmètre RBAC historique (clé stockée dans equipe_admin.acces_groupes,
// gérée sur /admin/fondateur/equipe). La structure visuelle de la sidebar est
// découplée de ces périmètres : regrouper des pages ne change pas les droits.
interface NavItem { icone: LucideIcon; label: string; route: string; acces: string; }
interface NavGroup { icone: LucideIcon; label: string; items: NavItem[]; }
type SidebarEntry = NavItem | NavGroup;
type LegalItem = Pick<NavItem, 'icone' | 'label' | 'route'>;

function isGroup(e: SidebarEntry): e is NavGroup { return 'items' in e; }

/* ── Périmètres RBAC historiques (ne pas renommer sans migrer equipe_admin) ── */
const ACCES = {
  DASHBOARD: 'Dashboard',
  UTILISATEURS: 'Utilisateurs',
  MISSIONS: 'Missions',
  LITIGES: 'Litiges & contrats',
  FINANCES: 'Finances',
  MESSAGERIE: 'Messagerie',
  FONDATEUR: 'Fondateur',
  TECHNIQUE: 'Conformité & Technique',
} as const;

/* ── Sidebar 5 groupes (Session D) : Pilotage, Utilisateurs, Opérations, Finances, Système ── */
const NAV_ADMIN_GROUPED: SidebarEntry[] = [
  {
    icone: BarChart3, label: 'Pilotage', items: [
      { icone: Home, label: 'Dashboard', route: '/admin', acces: ACCES.DASHBOARD },
      { icone: Rocket, label: 'Cockpit fondateur', route: '/admin/fondateur', acces: ACCES.FONDATEUR },
      { icone: Megaphone, label: 'Acquisition', route: '/admin/fondateur/acquisition', acces: ACCES.FONDATEUR },
      { icone: MessageCircle, label: 'Sales / Sourcing', route: '/admin/fondateur/sales', acces: ACCES.FONDATEUR },
      { icone: UserPlus, label: 'Équipe', route: '/admin/fondateur/equipe', acces: ACCES.FONDATEUR },
      { icone: TrendingUp, label: 'Cohortes & economics', route: '/admin/cohort', acces: ACCES.FONDATEUR },
      { icone: Rocket, label: 'Levée & documents', route: '/admin/fondateur/levee', acces: ACCES.FONDATEUR },
    ],
  },
  {
    icone: Users, label: 'Utilisateurs', items: [
      { icone: Users, label: 'Tous les utilisateurs', route: '/admin/utilisateurs', acces: ACCES.UTILISATEURS },
      { icone: Shield, label: 'Modération', route: '/admin/moderation', acces: ACCES.UTILISATEURS },
      { icone: Flag, label: 'Signalements', route: '/admin/signalements', acces: ACCES.UTILISATEURS },
      { icone: ShieldCheck, label: 'Vérif. établissements', route: '/admin/verification-etablissements', acces: ACCES.UTILISATEURS },
      { icone: FileCheck, label: 'Heures externes (3200h)', route: '/admin/heures-externes', acces: ACCES.UTILISATEURS },
      { icone: MessageCircle, label: 'Réclamations & scores', route: '/admin/reclamations', acces: ACCES.UTILISATEURS },
      { icone: Building2, label: 'Groupes santé', route: '/admin/groupes', acces: ACCES.UTILISATEURS },
    ],
  },
  {
    icone: ClipboardList, label: 'Opérations', items: [
      { icone: ClipboardList, label: 'Toutes les missions', route: '/admin/missions', acces: ACCES.MISSIONS },
      { icone: Flame, label: 'Pool urgence', route: '/admin/pool-urgence', acces: ACCES.MISSIONS },
      { icone: CalendarDays, label: 'Calendrier', route: '/admin/calendrier', acces: ACCES.MISSIONS },
      { icone: CalendarDays, label: 'Planning global', route: '/admin/planning-global', acces: ACCES.MISSIONS },
      { icone: AlertTriangle, label: 'Alertes pointage', route: '/admin/alertes-pointage', acces: ACCES.MISSIONS },
      { icone: Scale, label: 'Litiges', route: '/admin/litiges', acces: ACCES.LITIGES },
      { icone: FileSignature, label: 'Contrats', route: '/admin/contrats', acces: ACCES.LITIGES },
      { icone: FileStack, label: 'Templates contrats', route: '/admin/templates-contrats', acces: ACCES.LITIGES },
      { icone: MessageCircle, label: 'Messagerie', route: '/admin/messagerie', acces: ACCES.MESSAGERIE },
    ],
  },
  {
    icone: Coins, label: 'Finances', items: [
      { icone: Coins, label: 'Vue d\'ensemble', route: '/admin/finances', acces: ACCES.FINANCES },
      { icone: CreditCard, label: 'Facturation', route: '/admin/facturation', acces: ACCES.FINANCES },
      { icone: AlertTriangle, label: 'Impayées', route: '/admin/impayees', acces: ACCES.FINANCES },
      { icone: FileCheck, label: 'Mandats facturation', route: '/admin/mandats-facturation', acces: ACCES.FINANCES },
      { icone: Zap, label: 'Affacturage', route: '/admin/affacturage', acces: ACCES.FINANCES },
      { icone: FileStack, label: 'Chorus Pro', route: '/admin/chorus-pro', acces: ACCES.FINANCES },
      { icone: Coins, label: 'Taux commission', route: '/admin/taux-commission', acces: ACCES.FINANCES },
      { icone: Gift, label: 'Paliers BFA', route: '/admin/bfa', acces: ACCES.FINANCES },
    ],
  },
  {
    icone: Settings, label: 'Système', items: [
      { icone: Settings, label: 'Configuration', route: '/admin/config', acces: ACCES.TECHNIQUE },
      { icone: ShieldCheck, label: 'Conformité', route: '/admin/conformite', acces: ACCES.TECHNIQUE },
      { icone: Shield, label: 'Audit logs', route: '/admin/audit', acces: ACCES.TECHNIQUE },
      { icone: Shield, label: 'Audit RLS', route: '/admin/audit-rls', acces: ACCES.TECHNIQUE },
      { icone: FileCheck, label: 'DPIA', route: '/admin/dpia', acces: ACCES.TECHNIQUE },
      { icone: Shield, label: 'Outils RGPD', route: '/admin/rgpd-tools', acces: ACCES.TECHNIQUE },
      { icone: Zap, label: 'Externalisations', route: '/admin/externalisations-actions', acces: ACCES.TECHNIQUE },
      { icone: Activity, label: 'Statut système', route: '/admin/status', acces: ACCES.TECHNIQUE },
      { icone: Mail, label: 'Emails', route: '/admin/emails', acces: ACCES.TECHNIQUE },
      { icone: Code2, label: 'API', route: '/admin/api', acces: ACCES.TECHNIQUE },
      { icone: HeartPulse, label: 'Healthcheck', route: '/admin/healthcheck', acces: ACCES.TECHNIQUE },
      { icone: Code2, label: 'Démo', route: '/admin/demo', acces: ACCES.TECHNIQUE },
    ],
  },
];

/* ── Mobile bottom bar (4 items + Plus) ── */
const NAV_ADMIN_MOBILE_MAIN: NavItem[] = [
  { icone: Home, label: 'Accueil', route: '/admin', acces: ACCES.DASHBOARD },
  { icone: Users, label: 'Utilisateurs', route: '/admin/utilisateurs', acces: ACCES.UTILISATEURS },
  { icone: ClipboardList, label: 'Missions', route: '/admin/missions', acces: ACCES.MISSIONS },
  { icone: MessageCircle, label: 'Messages', route: '/admin/messagerie', acces: ACCES.MESSAGERIE },
];

const NAV_LEGAL: LegalItem[] = [
  { icone: ShieldCheck, label: 'Confidentialité', route: '/confidentialite' },
  { icone: Scale, label: 'CGU', route: '/cgu' },
  { icone: FileStack, label: 'Mentions légales', route: '/mentions-legales' },
  { icone: Trash2, label: 'Suppression compte', route: '/supprimer-mon-compte' },
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
  const [rechercheOuverte, setRechercheOuverte] = useState(false);
  const scrollDirection = useScrollDirection();
  const { accesTotal, aAcces } = useAccesAdmin();

  // ⌘K / Ctrl+K → recherche globale
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setRechercheOuverte(o => !o);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  const isActive = (route: string) =>
    route === '/admin' ? location.pathname === '/admin' : location.pathname.startsWith(route);

  // RBAC : filtre item par item selon les périmètres autorisés (backend-driven).
  // Les périmètres restent les 8 clés historiques d'equipe_admin ; un groupe
  // visuel sans aucun item accessible disparaît entièrement.
  const navFiltered = useMemo(() => {
    if (accesTotal) return NAV_ADMIN_GROUPED;
    return NAV_ADMIN_GROUPED
      .map(entry => (isGroup(entry) ? { ...entry, items: entry.items.filter(i => aAcces(i.acces)) } : entry))
      .filter(entry => (isGroup(entry) ? entry.items.length > 0 : aAcces(entry.acces)));
  }, [accesTotal, aAcces]);

  const allFlatItems = flattenEntries(navFiltered);
  const mobileMainItems = useMemo(
    () => (accesTotal ? NAV_ADMIN_MOBILE_MAIN : NAV_ADMIN_MOBILE_MAIN.filter(m => aAcces(m.acces))),
    [accesTotal, aAcces],
  );
  const mobileExtraItems = allFlatItems.filter(
    item => !mobileMainItems.some(m => m.route === item.route)
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
        <div className="px-3 pt-3">
          <button
            onClick={() => setRechercheOuverte(true)}
            className="w-full flex items-center gap-2 rounded-lg border border-sidebar-border bg-sidebar-accent/40 px-3 py-2 text-sm text-sidebar-foreground/60 hover:text-sidebar-foreground hover:bg-sidebar-accent transition-colors"
          >
            <Search className="h-4 w-4" />
            <span className="flex-1 text-left">Rechercher…</span>
            <kbd className="text-[10px] font-mono border border-sidebar-border rounded px-1.5 py-0.5">⌘K</kbd>
          </button>
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
          {navFiltered.map((entry, i) =>
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
          <div className="mb-2 grid grid-cols-2 gap-1">
            {NAV_LEGAL.map((item) => (
              <button
                key={item.route}
                onClick={() => navigate(item.route)}
                className="flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-[11px] text-sidebar-foreground/50 hover:bg-sidebar-accent hover:text-sidebar-foreground transition-colors"
              >
                <item.icone className="h-3.5 w-3.5" />
                <span className="truncate">{item.label}</span>
              </button>
            ))}
          </div>
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
          <button
            onClick={() => setRechercheOuverte(true)}
            className="p-2 text-muted-foreground hover:text-foreground transition-colors"
            title="Rechercher"
            aria-label="Rechercher"
          >
            <Search className="h-5 w-5" />
          </button>
          <ThemeToggle />
          <button onClick={handleDeconnexion} className="p-2 text-muted-foreground hover:text-destructive transition-colors" title="Déconnexion">
            <LogOut className="h-5 w-5" />
          </button>
        </div>
      </header>

      {/* ── Recherche globale (⌘K) ── */}
      <RechercheGlobaleAdmin
        open={rechercheOuverte}
        onOpenChange={setRechercheOuverte}
        pages={allFlatItems}
      />

      {/* ── Mobile bottom nav (Sprint 9-D : glassmorphism subtle) ── */}
      <nav
        className="fixed bottom-0 left-0 right-0 flex md:hidden z-50 bg-card/85 backdrop-blur-xl supports-[backdrop-filter]:bg-card/70 border-t border-jolene-rose-200/40 shadow-lg"
        style={{ height: 'calc(4rem + env(safe-area-inset-bottom))', paddingBottom: 'env(safe-area-inset-bottom)' }}
        role="navigation"
        aria-label="Navigation mobile admin"
      >
        {mobileMainItems.map((item) => {
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
            {NAV_LEGAL.map((item) => {
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
          {/* 2FA admin par email imposée à TOUTES les pages admin (un seul point
              d'ancrage). GardeMfaAdmin existait mais n'était branché nulle part
              → la double vérification n'était pas réellement appliquée. */}
          <GardeMfaAdmin>{children}</GardeMfaAdmin>
        </div>
        {/* Footer légal retiré des écrans authentifiés (Lot 6b.1). */}
      </main>
    </div>
  );
}
