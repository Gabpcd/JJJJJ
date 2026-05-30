import { useEffect, useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Building2 } from 'lucide-react';
import {
  CreditCard, FileStack, FileText, FileSpreadsheet, BarChart3, Clock, Scale,
  Flame, Users, Gift, Settings, LogOut, HeartHandshake, ClipboardCheck,
} from 'lucide-react';

export default function MonCompteEtablissement() {
  usePageTitle('Mon compte');
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
      titre: 'Gestion',
      lignes: [
        { icone: ClipboardCheck, label: 'Présences à valider', route: '/etablissement/presences' },
        { icone: FileText, label: 'Contrats', route: '/etablissement/contrats' },
        { icone: Scale, label: 'Litiges & contestations', route: '/etablissement/litiges' },
        { icone: Clock, label: 'Shifts', route: '/etablissement/shifts' },
        { icone: BarChart3, label: 'Tableau RH & analytics', route: '/etablissement/rh' },
        { icone: Flame, label: 'Pool urgence', route: '/etablissement/pool-urgence' },
      ],
    },
    {
      titre: 'Finances',
      lignes: [
        { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
        { icone: FileSpreadsheet, label: 'Export paie', route: '/etablissement/export-paie' },
        { icone: FileStack, label: 'Chorus Pro', route: '/etablissement/chorus-config' },
      ],
    },
    {
      titre: 'Soignants',
      lignes: [
        { icone: Users, label: 'Annuaire des soignants', route: '/etablissement/soignants' },
        { icone: Gift, label: 'Parrainage', route: '/etablissement/parrainage' },
        { icone: HeartHandshake, label: 'Premium', route: '/etablissement/premium' },
      ],
    },
    {
      lignes: [
        { icone: Settings, label: 'Paramètres', route: '/etablissement/parametres' },
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
