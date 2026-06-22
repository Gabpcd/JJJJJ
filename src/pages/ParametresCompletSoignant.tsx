import { useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { estEligibleLiberal } from '@/lib/regles-installation-liberal';
import { supabase } from '@/integrations/supabase/client';
import { useEffect, useState } from 'react';
import {
  Bell, Search, Ban, Gift, GraduationCap, Rocket, FileCheck2,
  CreditCard, FileSignature, Landmark, Code2,
} from 'lucide-react';

export default function ParametresCompletSoignant() {
  usePageTitle('Paramètres');
  const { user } = useAuth();
  const [profil, setProfil] = useState<{
    profession: string | null; statut_liberal: string | null; type_exercice: string | null;
  } | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('profession, statut_liberal, type_exercice')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => { if (data) setProfil(data as any); });
  }, [user]);

  const estLiberal =
    profil?.type_exercice === 'LIBERAL' ||
    profil?.type_exercice === 'MIXTE' ||
    profil?.statut_liberal === 'ACTIF';
  const eligibleLiberal = !!(profil?.profession && estEligibleLiberal(profil.profession));

  const sections: SectionReglages[] = [
    {
      titre: 'Notifications & recherches',
      lignes: [
        { icone: Bell, label: 'Notifications', route: '/soignant/parametres/notifications' },
        { icone: Search, label: 'Recherches sauvegardées', route: '/soignant/parametres/recherches-sauvegardees' },
        { icone: Ban, label: 'Établissements exclus', route: '/soignant/exclusions' },
      ],
    },
    ...(estLiberal ? [{
      titre: 'Paiement libéral',
      lignes: [
        { icone: CreditCard, label: 'Stripe Connect', route: '/soignant/stripe-connect' },
        { icone: FileSignature, label: 'Mandat de facturation', route: '/soignant/mandat-facturation' },
        { icone: Landmark, label: 'Charges sociales (URSSAF)', route: '/soignant/charges' },
      ],
    }] : []),
    {
      titre: 'Développement',
      lignes: [
        ...(eligibleLiberal && !estLiberal
          ? [{ icone: Rocket, label: 'Passer en libéral', route: '/soignant/passer-en-liberal' }]
          : []),
        ...(eligibleLiberal
          ? [{ icone: FileCheck2, label: 'Attestation d\'heures (3200h)', route: '/soignant/attestation-heures' }]
          : []),
        { icone: GraduationCap, label: 'Prévoyance', route: '/soignant/prevoyance' },
        { icone: Gift, label: 'Parrainage', route: '/soignant/parrainage' },
      ],
    },
  ];

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-4">Paramètres</h1>
      <ListeReglages sections={sections} />
    </LayoutApp>
  );
}
