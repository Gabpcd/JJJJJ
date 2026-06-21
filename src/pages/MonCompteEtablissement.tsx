import { useEffect, useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Building2 } from 'lucide-react';
import {
  CreditCard, FileText, BarChart3, Scale, ClipboardCheck,
  Users, Gift, Settings, LogOut,
  User, TrendingUp, Star, Landmark,
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

  // Menu réduit au strict nécessaire. Présences + Missions + Messages = déjà
  // dans la bottom nav. Pool urgence = accessible depuis Missions. Parrainage +
  // API = rangés dans Paramètres. Planning = accessible depuis l'Accueil.
  const sections: SectionReglages[] = [
    {
      titre: 'Mon établissement',
      lignes: [
        { icone: User, label: 'Profil', route: '/etablissement/profil' },
        { icone: FileText, label: 'Contrats', route: '/etablissement/contrats' },
        { icone: ClipboardCheck, label: 'Présences à valider', route: '/etablissement/presences' },
        { icone: Users, label: 'Annuaire soignants', route: '/etablissement/soignants' },
        { icone: Users, label: 'Mon équipe', route: '/etablissement/equipe' },
      ],
    },
    {
      titre: 'Qualité',
      lignes: [
        { icone: Star, label: 'Évaluations à faire', route: '/etablissement/evaluations-a-faire' },
        { icone: Scale, label: 'Litiges & contestations', route: '/etablissement/litiges' },
        { icone: Landmark, label: 'Score établissement', route: '/etablissement/score' },
      ],
    },
    {
      titre: 'Finances & analyse',
      lignes: [
        { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
        { icone: BarChart3, label: 'Tableau RH', route: '/etablissement/rh' },
        { icone: TrendingUp, label: 'Analytics', route: '/etablissement/analytics' },
      ],
    },
    {
      titre: 'Paramètres',
      lignes: [
        { icone: Settings, label: 'Paramètres', route: '/etablissement/parametres' },
        { icone: Gift, label: 'Parrainage', route: '/etablissement/parrainage' },
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
