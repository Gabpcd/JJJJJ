import { useEffect, useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Building2 } from 'lucide-react';
import {
  CreditCard, Scale, Settings, LogOut, User, Star, ShieldCheck, FileText, Trash2,
  BookOpen, Mail,
} from 'lucide-react';
import { ModalContacterJolene } from '@/components/ModalContacterJolene';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { BuildStamp } from '@/components/BuildStamp';
import { useTheme } from '@/hooks/useTheme';
import { Moon, Sun } from 'lucide-react';

export default function MonCompteEtablissement() {
  usePageTitle('Mon établissement');
  const { user, deconnexion } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const [etab, setEtab] = useState<{ nom: string; logo_url: string | null; type: string | null } | null>(null);
  const [contactOpen, setContactOpen] = useState(false);

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
        { icone: User, label: 'Mon établissement', route: '/etablissement/parametres?tab=profil' },
        { icone: CreditCard, label: 'Facturation', route: '/etablissement/facturation' },
        { icone: Star, label: 'Qualité', route: '/etablissement/litiges' },
        { icone: Settings, label: 'Paramètres', route: '/etablissement/parametres?tab=config' },
        // Toggle thème rapatrié ici depuis le header mobile (Lot 6b.1 — header épuré).
        {
          icone: theme === 'dark' ? Sun : Moon,
          label: theme === 'dark' ? 'Passer en thème clair' : 'Passer en thème sombre',
          onClick: toggleTheme,
          sansChevron: true,
        },
        { icone: LogOut, label: 'Se déconnecter', onClick: () => deconnexion(), variante: 'danger' as const, sansChevron: true },
      ],
    },
    {
      // Le FAB « ? » global a été retiré (Lot 6a.4) : aide + contact vivent ici.
      titre: 'Aide & légal',
      lignes: [
        { icone: BookOpen, label: 'Centre d\'aide', route: '/aide' },
        { icone: Mail, label: 'Contacter Jolene', onClick: () => setContactOpen(true), sansChevron: true },
        { icone: ShieldCheck, label: 'Confidentialité', route: '/confidentialite' },
        { icone: Scale, label: 'CGU', route: '/cgu' },
        { icone: CreditCard, label: 'CGV', route: '/cgv' },
        { icone: FileText, label: 'Mentions légales', route: '/mentions-legales' },
        { icone: Trash2, label: 'Supprimer mon compte', route: '/supprimer-mon-compte' },
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
        sousTitre={etab?.type ? getLabelTypeEtablissement(etab.type) : undefined}
      />
      <ListeReglages sections={sections} />
      <BuildStamp />
      <ModalContacterJolene open={contactOpen} onClose={() => setContactOpen(false)} source="compte-etablissement" />
    </LayoutApp>
  );
}
