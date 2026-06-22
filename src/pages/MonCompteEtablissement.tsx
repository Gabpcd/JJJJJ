import { useEffect, useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Building2 } from 'lucide-react';
import {
  CreditCard, Scale, Settings, LogOut, User, Star,
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

  // Menu = ton COMPTE. Tout le reste est contextuel (barre du bas, dashboard,
  // fiche mission). Missions + Présences + Messages = bottom nav. Contrats /
  // annuaire / pool urgence = depuis la fiche mission ou la liste missions.
  const sections: SectionReglages[] = [
    {
      titre: '',
      lignes: [
        { icone: User, label: 'Mon établissement', route: '/etablissement/profil' },
        { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
        { icone: Star, label: 'Qualité', route: '/etablissement/evaluations-a-faire' },
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
