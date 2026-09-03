import { useEffect, useLayoutEffect, useRef } from 'react';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { User, CreditCard, Settings2, Bell, ShieldCheck, ChevronRight } from 'lucide-react';
import { ProfilEtablissementContent } from './ProfilEtablissement';
import { MonGroupeContent } from './MonGroupe';
import { NotificationsContent } from './PageNotifications';
import { APIContent } from './APIEtablissement';
import { ExclusionsContent } from './ExclusionsEtablissement';
import { TolerancePointageGps } from '@/components/etablissement/TolerancePointageGps';

// Lot 12 : 5 sections nommées — Profil / Facturation / Opérations /
// Notifications / Sécurité & RGPD. Les blocs de ProfilEtablissementContent
// sont redistribués via sa prop `sections`.
const TABS = ['profil', 'facturation', 'operations', 'notifications', 'securite'] as const;
type Tab = typeof TABS[number];

// Alias de deep-links historiques (?tab=) — les vieux liens ne cassent jamais.
// `contrats` n'a jamais existé comme onglet (lien FormulaireMission) : il
// atterrit sur la section facturation qui porte le contrat de service.
const ALIAS_TABS: Record<string, Tab> = {
  config: 'operations',
  groupe: 'operations',
  exclusions: 'operations',
  contrats: 'facturation',
  notifications: 'notifications',
};

const ONGLETS: Array<{ value: Tab; label: string; icone: typeof User }> = [
  { value: 'profil', label: 'Profil', icone: User },
  { value: 'facturation', label: 'Facturation', icone: CreditCard },
  { value: 'operations', label: 'Opérations', icone: Settings2 },
  { value: 'notifications', label: 'Notifications', icone: Bell },
  { value: 'securite', label: 'Sécurité & RGPD', icone: ShieldCheck },
];

export default function Parametres() {
  usePageTitle('Paramètres');
  const location = useLocation();
  const [searchParams, setSearchParams] = useSearchParams();
  const ongletsScrollerRef = useRef<HTMLDivElement>(null);
  const tabParam = searchParams.get('tab');
  // Appliquer le mapping d'alias AVANT de sélectionner l'onglet.
  const tabResolu = tabParam ? (ALIAS_TABS[tabParam] ?? tabParam) : null;
  const currentTab: Tab = TABS.includes(tabResolu as Tab) ? (tabResolu as Tab) : 'profil';

  // Les liens du hub compte peuvent cibler directement une section interne
  // (ex. Sécurité & RGPD → suppression du compte). React Router ne réalise pas
  // toujours le défilement d’ancre après le montage différé d’un onglet Radix.
  useEffect(() => {
    if (!location.hash) return;
    const id = decodeURIComponent(location.hash.slice(1));
    const frame = window.requestAnimationFrame(() => {
      document.getElementById(id)?.scrollIntoView({ block: 'start' });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [currentTab, location.hash]);

  // Les accès depuis le menu mobile ouvrent directement un onglet via ?tab=.
  // Quand l'onglet ciblé est à droite (notamment Sécurité & RGPD), il doit être
  // visible immédiatement : laisser l'état actif hors écran prive l'utilisateur
  // de tout repère de navigation.
  useLayoutEffect(() => {
    let annule = false;
    const aligner = () => {
      if (annule) return;
      const scroller = ongletsScrollerRef.current;
      const actif = scroller?.querySelector<HTMLElement>('[role="tab"][data-state="active"]');
      if (!scroller || !actif) return;

      const marge = 8;
      const cadre = scroller.getBoundingClientRect();
      const onglet = actif.getBoundingClientRect();
      if (onglet.left < cadre.left + marge) {
        scroller.scrollLeft -= cadre.left + marge - onglet.left;
      } else if (onglet.right > cadre.right - marge) {
        scroller.scrollLeft += onglet.right - cadre.right + marge;
      }
    };

    const frame = window.requestAnimationFrame(aligner);
    // Les libellés peuvent changer de largeur lorsque la police finit de se
    // charger. Réaligner à ce moment évite un onglet initialement visible puis
    // repoussé hors champ sur WebKit.
    void document.fonts?.ready.then(aligner);
    const observer = new ResizeObserver(aligner);
    if (ongletsScrollerRef.current) observer.observe(ongletsScrollerRef.current);

    return () => {
      annule = true;
      window.cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [currentTab]);

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <h1 className="mb-5 text-xl font-bold text-foreground">Paramètres de l’établissement</h1>
      <Tabs
        value={currentTab}
        onValueChange={(v) => setSearchParams({ tab: v }, { replace: true })}
        className="w-full"
      >
        <div ref={ongletsScrollerRef} className="-mx-1 mb-6 px-1 sm:overflow-x-auto">
        <TabsList className="grid h-auto w-full grid-cols-5 sm:flex sm:w-max">
          {ONGLETS.map(({ value, label, icone: Icone }) => (
            <TabsTrigger
              key={value}
              value={value}
              className="flex min-w-0 flex-col gap-0.5 whitespace-normal px-1 py-2 text-center text-[9px] leading-tight sm:flex-row sm:gap-1.5 sm:whitespace-nowrap sm:px-3 sm:text-sm"
            >
              <Icone className="h-3.5 w-3.5 sm:h-4 sm:w-4" aria-hidden="true" />
              <span>{label}</span>
            </TabsTrigger>
          ))}
        </TabsList>
        </div>

        <TabsContent value="profil" className="mt-0">
          <ProfilEtablissementContent sections={['profil']} />
        </TabsContent>

        <TabsContent value="facturation" className="mt-0">
          <ProfilEtablissementContent sections={['facturation']} />
        </TabsContent>

        <TabsContent value="operations" className="mt-0 space-y-8">
          <ProfilEtablissementContent sections={['geoloc']} />
          <TolerancePointageGps />
          <MonGroupeContent headingLevel="h2" />
          <ExclusionsContent />
        </TabsContent>

        <TabsContent value="notifications" className="mt-0 space-y-6">
          <NotificationsContent headingLevel="h2" />
          <Link
            to="/etablissement/parametres/notifications"
            className="max-w-2xl flex items-center justify-between gap-2 card-base text-sm text-foreground hover:bg-muted/50 transition"
          >
            <span className="flex items-center gap-2">
              <Bell className="h-4 w-4 text-primary" aria-hidden="true" />
              Gérer mes préférences de canaux (email, push, SMS)
            </span>
            <ChevronRight className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
          </Link>
        </TabsContent>

        <TabsContent value="securite" className="mt-0 space-y-8">
          <ProfilEtablissementContent sections={['securite']} />
          <APIContent />
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}
