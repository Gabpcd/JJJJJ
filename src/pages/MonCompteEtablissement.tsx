import { useEffect, useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Building2 } from 'lucide-react';
import {
  CreditCard, FileStack, FileText, FileSpreadsheet, BarChart3, Scale,
  Flame, Users, Gift, Settings, LogOut, ClipboardCheck,
  User, TrendingUp, Star, Ban, Landmark, MessageSquare, Code2, CalendarDays,
} from 'lucide-react';

export default function MonCompteEtablissement() {
  usePageTitle('Mon établissement');
  const { user, deconnexion } = useAuth();
  const [etab, setEtab] = useState<{ nom: string; logo_url: string | null; type: string | null } | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase.from('etablissements')
      .select('nom, logo_url, type')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => { if (data) setEtab(data as any); });
  }, [user]);

  const sections: SectionReglages[] = [
    {
      titre: 'Activité',
      lignes: [
        { icone: User, label: 'Profil de l\'établissement', route: '/etablissement/profil' },
        { icone: ClipboardCheck, label: 'Présences à valider', route: '/etablissement/presences' },
        { icone: FileText, label: 'Contrats', route: '/etablissement/contrats' },
        { icone: CalendarDays, label: 'Planning', route: '/etablissement/planning' },
        { icone: Flame, label: 'Pool urgence', route: '/etablissement/pool-urgence' },
      ],
    },
    {
      titre: 'Qualité & litiges',
      lignes: [
        { icone: Star, label: 'Évaluations à faire', route: '/etablissement/evaluations-a-faire' },
        { icone: Scale, label: 'Litiges & contestations', route: '/etablissement/litiges' },
        { icone: MessageSquare, label: 'Mes réclamations', route: '/etablissement/mes-reclamations' },
      ],
    },
    {
      titre: 'Analyse',
      lignes: [
        { icone: BarChart3, label: 'Tableau RH', route: '/etablissement/rh' },
        { icone: TrendingUp, label: 'Analytics', route: '/etablissement/analytics' },
        { icone: Landmark, label: 'Score établissement', route: '/etablissement/score' },
      ],
    },
    {
      titre: 'Finances',
      lignes: [
        // « Facturation » et « Obligations financières » pointaient la même route.
        // Dédoublonné : 1 entrée « Facturation » (la page a déjà tout).
        { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
        { icone: FileSpreadsheet, label: 'Export paie', route: '/etablissement/export-paie' },
        { icone: FileStack, label: 'Chorus Pro', route: '/etablissement/chorus-config' },
      ],
    },
    {
      titre: 'Soignants & équipe',
      lignes: [
        { icone: Users, label: 'Annuaire des soignants', route: '/etablissement/soignants' },
        { icone: Ban, label: 'Soignants exclus', route: '/etablissement/exclusions' },
        { icone: Users, label: 'Mon équipe', route: '/etablissement/equipe' },
        { icone: Building2, label: 'Mon groupe', route: '/etablissement/mon-groupe' },
        { icone: Gift, label: 'Parrainage', route: '/etablissement/parrainage' },
      ],
    },
    {
      titre: 'Paramètres',
      lignes: [
        { icone: Settings, label: 'Paramètres', route: '/etablissement/parametres' },
        { icone: Code2, label: 'API', route: '/etablissement/api' },
        { icone: LogOut, label: 'Se déconnecter', onClick: () => deconnexion(), variante: 'danger' as const, sansChevron: true },
      ],
    },
  ];

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <EnteteCompte
        avatar={
          <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <Building2 className="h-7 w-7" />
          </span>
        }
        titre={etab?.nom || 'Mon établissement'}
        sousTitre={etab?.type || undefined}
      />
      <ListeReglages sections={sections} />
    </LayoutApp>
  );
}
