import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { LogOut, Menu, Search, X } from 'lucide-react';
import { RechercheGlobaleAdmin } from '@/components/admin/RechercheGlobaleAdmin';
import { ThemeToggle } from '@/components/ThemeToggle';
import { AdminInterfaceProvider } from '@/contexts/AdminInterfaceContext';
import { LogoJolene } from '@/components/LogoJolene';
import { useAuth } from '@/contexts/AuthContext';
import { useAccesAdmin } from '@/hooks/useAccesAdmin';
import { useScrollDirection } from '@/hooks/useScrollDirection';
import {
  ADMIN_LEGAL_ITEMS,
  ADMIN_MOBILE_PRIMARY_GROUP_IDS,
  ADMIN_NAV_GROUPS,
  flattenAdminNavigation,
  type AdminNavGroup,
} from '@/lib/adminNavigation';
import { cn } from '@/lib/utils';
import { BadgeNotification } from '@/components/PanneauNotifications';

function lienActif(pathname: string, route: string): boolean {
  return pathname === route || pathname.startsWith(`${route}/`);
}

function AdminSectionLinks({
  group,
  activeRoute,
  mobile = false,
  onNavigate,
}: {
  group: AdminNavGroup;
  activeRoute?: string;
  mobile?: boolean;
  onNavigate?: () => void;
}) {
  const navigationRef = useRef<HTMLElement>(null);
  const activeLinkRef = useRef<HTMLAnchorElement>(null);

  useLayoutEffect(() => {
    const navigation = navigationRef.current;
    const activeLink = activeLinkRef.current;
    if (!navigation || !activeLink || navigation.scrollWidth <= navigation.clientWidth) return;
    const navigationRect = navigation.getBoundingClientRect();
    const activeLinkRect = activeLink.getBoundingClientRect();
    const centeredLeft = navigation.scrollLeft
      + activeLinkRect.left
      - navigationRect.left
      - (navigation.clientWidth - activeLinkRect.width) / 2;
    navigation.scrollTo({
      left: Math.min(
        Math.max(0, centeredLeft),
        navigation.scrollWidth - navigation.clientWidth,
      ),
      behavior: 'auto',
    });
  }, [activeRoute, group.id]);

  if (group.items.length <= 1) return null;

  return (
    <nav
      ref={navigationRef}
      aria-label={`Pages de la rubrique ${group.label}`}
      className={cn(
        'flex gap-1 overflow-x-auto scrollbar-none',
        mobile ? 'border-b border-border bg-background px-3 py-2' : 'min-w-0 flex-1',
      )}
    >
      {group.items.map((item) => {
        const active = item.route === activeRoute;
        return (
          <Link
            ref={active ? activeLinkRef : undefined}
            key={item.route}
            to={item.route}
            onClick={onNavigate}
            aria-current={active ? 'page' : undefined}
            className={cn(
              'inline-flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-colors',
              mobile ? 'min-h-11' : 'min-h-9',
              'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2',
              active
                ? 'bg-foreground text-background'
                : 'text-muted-foreground hover:bg-muted hover:text-foreground',
            )}
          >
            <item.icone className="h-3.5 w-3.5" aria-hidden="true" />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function LayoutAdmin({ children }: { children: ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { deconnexion } = useAuth();
  const { accesTotal, aAcces } = useAccesAdmin();
  const scrollDirection = useScrollDirection();
  const [rechercheOuverte, setRechercheOuverte] = useState(false);
  const [menuMobileOuvert, setMenuMobileOuvert] = useState(false);
  const menuMobileRef = useRef<HTMLDivElement>(null);
  const menuMobileTriggerRef = useRef<HTMLButtonElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const previousHtmlOverflowX = document.documentElement.style.overflowX;
    const previousBodyOverflowX = document.body.style.overflowX;
    document.documentElement.style.overflowX = 'clip';
    document.body.style.overflowX = 'clip';
    return () => {
      document.documentElement.style.overflowX = previousHtmlOverflowX;
      document.body.style.overflowX = previousBodyOverflowX;
    };
  }, []);

  useEffect(() => {
    const gererRaccourci = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setRechercheOuverte((open) => !open);
      }
    };
    window.addEventListener('keydown', gererRaccourci);
    return () => window.removeEventListener('keydown', gererRaccourci);
  }, []);

  useEffect(() => {
    if (!menuMobileOuvert) return;
    previousFocusRef.current = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : menuMobileTriggerRef.current;
    const frame = window.requestAnimationFrame(() => {
      menuMobileRef.current?.querySelector<HTMLElement>('a, button:not([disabled])')?.focus();
    });
    const gererClavier = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        setMenuMobileOuvert(false);
        return;
      }
      if (event.key !== 'Tab') return;
      const menu = menuMobileRef.current;
      if (!menu) return;
      const focusables = Array.from(menu.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ));
      if (focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (!menu.contains(document.activeElement)) {
        event.preventDefault();
        first.focus();
      } else if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', gererClavier);
    return () => {
      window.cancelAnimationFrame(frame);
      document.removeEventListener('keydown', gererClavier);
      previousFocusRef.current?.focus();
    };
  }, [menuMobileOuvert]);

  const groups = useMemo(() => ADMIN_NAV_GROUPS
    .map((group) => ({
      ...group,
      items: accesTotal ? group.items : group.items.filter((item) => aAcces(item.acces)),
    }))
    .filter((group) => group.items.length > 0), [aAcces, accesTotal]);

  const allItems = useMemo(() => flattenAdminNavigation(groups), [groups]);
  const searchableItems = useMemo(() => [...allItems, ...ADMIN_LEGAL_ITEMS], [allItems]);
  const pathname = location.pathname.startsWith('/admin/presences/mission/')
    ? '/admin/missions'
    : location.pathname;
  const activeRoute = allItems
    .filter((item) => lienActif(pathname, item.route))
    .sort((a, b) => b.route.length - a.route.length)[0]?.route;
  const activeItem = allItems.find((item) => item.route === activeRoute);
  const activeGroup = groups.find((group) => group.items.some((item) => item.route === activeRoute))
    ?? groups[0];
  const mobilePrimaryGroups = groups.filter((group) => ADMIN_MOBILE_PRIMARY_GROUP_IDS.has(group.id));
  const mobileExtraGroups = groups.filter((group) => !ADMIN_MOBILE_PRIMARY_GROUP_IDS.has(group.id));
  const menuMobileActif = mobileExtraGroups.some((group) => group.id === activeGroup?.id);
  const afficheSousNavigation = activeGroup?.id !== 'acquisition';

  const handleDeconnexion = async () => {
    await deconnexion();
    navigate('/');
  };

  return (
    <AdminInterfaceProvider>
      <div className="admin-shell flex min-h-[100dvh] w-full min-w-0 max-w-full overflow-x-hidden bg-muted/20">
        <aside className="fixed inset-y-0 left-0 z-40 hidden w-[216px] flex-col border-r border-border bg-card md:flex">
          <div className="flex h-16 items-center justify-between border-b border-border px-4">
            <Link to="/admin" className="flex items-center gap-2 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <LogoJolene
                  afficherNom={false}
                  decoratif
                  imageClassName="h-5 w-5"
                />
              </span>
              <span>
                <span className="block text-sm font-semibold leading-tight text-foreground">Jolene</span>
                <span className="block text-[11px] leading-tight text-muted-foreground">Administration</span>
              </span>
            </Link>
            <div className="flex items-center gap-1">
              <BadgeNotification />
              <ThemeToggle className="text-muted-foreground hover:bg-muted" />
            </div>
          </div>

          <div className="px-3 pt-3">
            <button
              type="button"
              onClick={() => setRechercheOuverte(true)}
              className="flex min-h-10 w-full items-center gap-2 rounded-lg border border-border bg-background px-3 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            >
              <Search className="h-4 w-4" aria-hidden="true" />
              <span className="flex-1 text-left">Rechercher</span>
              <kbd className="rounded border border-border px-1.5 py-0.5 font-mono text-[10px]">⌘K</kbd>
            </button>
          </div>

          <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4" aria-label="Espaces de travail admin">
            {groups.map((group) => {
              const active = group.id === activeGroup?.id;
              const route = group.items[0].route;
              return (
                <Link
                  key={group.id}
                  to={route}
                  aria-current={route === activeRoute ? 'page' : undefined}
                  className={cn(
                    'group flex min-h-11 items-center gap-3 rounded-lg px-3 py-2 transition-colors',
                    active
                      ? 'bg-primary/10 text-primary'
                      : 'text-muted-foreground hover:bg-muted hover:text-foreground',
                  )}
                >
                  <group.icone className="h-[18px] w-[18px] shrink-0" aria-hidden="true" />
                  <span className="min-w-0 truncate text-sm font-medium">{group.label}</span>
                </Link>
              );
            })}
          </nav>

          <div className="border-t border-border p-3">
            <details className="mb-1 text-xs text-muted-foreground">
              <summary className="cursor-pointer rounded-lg px-3 py-2 hover:bg-muted hover:text-foreground">Aide et mentions légales</summary>
              <div className="mt-1 space-y-0.5 pl-2">
                {ADMIN_LEGAL_ITEMS.map((item) => (
                  <Link key={item.route} to={item.route} className="flex min-h-8 items-center gap-2 rounded-md px-2 hover:bg-muted hover:text-foreground">
                    <item.icone className="h-3.5 w-3.5" aria-hidden="true" /> {item.label}
                  </Link>
                ))}
              </div>
            </details>
            <button
              type="button"
              onClick={handleDeconnexion}
              className="flex min-h-10 w-full items-center gap-2 rounded-lg px-3 text-sm text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
            >
              <LogOut className="h-4 w-4" aria-hidden="true" /> Déconnexion
            </button>
          </div>
        </aside>

        <header
          className={cn(
            'fixed inset-x-0 top-0 z-50 flex h-14 items-center justify-between border-b border-border bg-card/95 px-4 backdrop-blur md:hidden',
            'transition-transform duration-200 motion-reduce:transition-none',
            scrollDirection === 'down' ? '-translate-y-full' : 'translate-y-0',
          )}
        >
          <div className="min-w-0">
            <p className="truncate text-[10px] font-medium uppercase tracking-wide text-muted-foreground">{activeGroup?.label ?? 'Administration'}</p>
            <p className="truncate text-sm font-semibold text-foreground">{activeItem?.label ?? 'Jolene'}</p>
          </div>
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => setRechercheOuverte(true)}
              className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground"
              aria-label="Rechercher"
            >
              <Search className="h-5 w-5" aria-hidden="true" />
            </button>
            <BadgeNotification />
            <ThemeToggle />
            <button
              type="button"
              onClick={handleDeconnexion}
              className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-lg text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
              aria-label="Se déconnecter"
            >
              <LogOut className="h-5 w-5" aria-hidden="true" />
            </button>
          </div>
        </header>

        <RechercheGlobaleAdmin open={rechercheOuverte} onOpenChange={setRechercheOuverte} pages={searchableItems} />

        <nav
          className="fixed inset-x-0 bottom-0 z-50 flex border-t border-border bg-card/95 backdrop-blur md:hidden"
          style={{ height: 'calc(4rem + env(safe-area-inset-bottom))', paddingBottom: 'env(safe-area-inset-bottom)' }}
          aria-label="Navigation mobile admin"
        >
          {mobilePrimaryGroups.map((group) => {
            const active = group.id === activeGroup?.id;
            return (
              <Link
                key={group.id}
                to={group.items[0].route}
                aria-current={group.items[0].route === activeRoute ? 'page' : undefined}
                onClick={() => setMenuMobileOuvert(false)}
                className={cn(
                  'flex min-h-11 min-w-11 flex-1 flex-col items-center justify-center gap-0.5 text-[10px] transition-colors',
                  active ? 'text-primary' : 'text-muted-foreground',
                )}
              >
                <group.icone className="h-5 w-5" aria-hidden="true" />
                <span>{group.label}</span>
              </Link>
            );
          })}
          {mobileExtraGroups.length > 0 || ADMIN_LEGAL_ITEMS.length > 0 ? (
            <button
              ref={menuMobileTriggerRef}
              type="button"
              onClick={() => setMenuMobileOuvert((open) => !open)}
              aria-expanded={menuMobileOuvert}
              aria-controls="admin-mobile-menu"
              className={cn(
                'flex min-h-11 min-w-11 flex-1 flex-col items-center justify-center gap-0.5 text-[10px] transition-colors',
                menuMobileOuvert || menuMobileActif ? 'text-primary' : 'text-muted-foreground',
              )}
            >
              {menuMobileOuvert ? <X className="h-5 w-5" aria-hidden="true" /> : <Menu className="h-5 w-5" aria-hidden="true" />}
              <span>Plus</span>
            </button>
          ) : null}
        </nav>

        {menuMobileOuvert && (
          <div className="fixed inset-0 z-40 bg-foreground/30 md:hidden" onClick={() => setMenuMobileOuvert(false)}>
            <div
              id="admin-mobile-menu"
              ref={menuMobileRef}
              role="dialog"
              aria-modal="true"
              aria-label="Autres espaces admin"
              className="absolute inset-x-3 bottom-20 max-h-[min(70dvh,34rem)] overflow-y-auto rounded-xl border border-border bg-card p-3 shadow-xl"
              style={{ marginBottom: 'env(safe-area-inset-bottom)' }}
              onClick={(event) => event.stopPropagation()}
            >
              <p className="px-2 pb-2 text-xs font-medium text-muted-foreground">Autres espaces</p>
              <div className="space-y-1">
                {mobileExtraGroups.map((group) => (
                  <Link
                    key={group.id}
                    to={group.items[0].route}
                    onClick={() => setMenuMobileOuvert(false)}
                    className={cn(
                      'flex min-h-12 items-center gap-3 rounded-lg px-3 transition-colors',
                      group.id === activeGroup?.id ? 'bg-primary/10 text-primary' : 'text-foreground hover:bg-muted',
                    )}
                  >
                    <group.icone className="h-5 w-5" aria-hidden="true" />
                    <span>
                      <span className="block text-sm font-medium">{group.label}</span>
                      <span className="block text-xs text-muted-foreground">{group.description}</span>
                    </span>
                  </Link>
                ))}
              </div>
              <div className="mt-3 border-t border-border pt-3">
                <p className="px-2 pb-2 text-xs font-medium text-muted-foreground">Aide et compte</p>
                <div className="space-y-1">
                  {ADMIN_LEGAL_ITEMS.map((item) => (
                    <Link
                      key={item.route}
                      to={item.route}
                      onClick={() => setMenuMobileOuvert(false)}
                      className="flex min-h-11 items-center gap-3 rounded-lg px-3 text-sm text-foreground transition-colors hover:bg-muted"
                    >
                      <item.icone className="h-4 w-4" aria-hidden="true" />
                      <span>{item.label}</span>
                    </Link>
                  ))}
                </div>
              </div>
            </div>
          </div>
        )}

        <main id="main-content" tabIndex={-1} className="min-w-0 max-w-full flex-1 overflow-x-hidden [contain:inline-size] pt-14 md:ml-[216px] md:pt-0">
          {activeGroup && afficheSousNavigation && (
            <>
              <div className="hidden border-b border-border bg-card md:block">
                <div className="mx-auto flex min-h-16 max-w-[1440px] items-center gap-6 px-5 lg:px-8">
                  <div className="w-40 shrink-0">
                    <p className="text-sm font-semibold text-foreground">{activeGroup.label}</p>
                    <p className="truncate text-[11px] text-muted-foreground">{activeGroup.description}</p>
                  </div>
                  <AdminSectionLinks group={activeGroup} activeRoute={activeRoute} />
                </div>
              </div>
              <div className="md:hidden">
                <AdminSectionLinks group={activeGroup} activeRoute={activeRoute} mobile />
              </div>
            </>
          )}
          <div className="admin-content mx-auto w-full min-w-0 max-w-[1440px] px-4 py-5 pb-24 md:px-5 md:py-6 md:pb-8 lg:px-8">
            {children}
          </div>
        </main>
      </div>
    </AdminInterfaceProvider>
  );
}
