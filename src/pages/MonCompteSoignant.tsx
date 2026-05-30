import { useEffect, useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { estEligibleLiberal } from '@/lib/regles-installation-liberal';
import {
  User, FileText, Banknote, CreditCard, FileSignature, Zap, ShieldCheck,
  Scale, Gift, Rocket, Settings, LogOut, GraduationCap, Receipt, HeartHandshake,
  Landmark, FileCheck2,
} from 'lucide-react';

export default function MonCompteSoignant() {
  usePageTitle('Mon compte');
  const { user, deconnexion } = useAuth();
  const [profil, setProfil] = useState<{
    prenom: string; nom: string; avatar_url: string | null;
    type_exercice: string | null; rpps_verifie: boolean; numero_rpps: string | null;
    profession: string | null; statut_liberal: string | null;
  } | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('prenom, nom, avatar_url, type_exercice, rpps_verifie, numero_rpps, profession, statut_liberal')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => { if (data) setProfil(data as any); });
  }, [user]);

  const estLiberal =
    profil?.type_exercice === 'LIBERAL' ||
    profil?.type_exercice === 'MIXTE' ||
    profil?.statut_liberal === 'ACTIF';

  // Profession éligible au libéral (pour Passer en libéral + Attestation 3200h)
  const eligibleLiberal = !!(profil?.profession && estEligibleLiberal(profil.profession));

  // Section Paiements : adaptée au statut (libéral = outils complets, salarié = gains seuls)
  const lignesPaiements = estLiberal
    ? [
        { icone: Banknote, label: 'Mes gains', route: '/soignant/mes-gains' },
        { icone: Receipt, label: 'Factures d\'honoraires', route: '/soignant/mes-factures-honoraires' },
        { icone: CreditCard, label: 'Stripe Connect', route: '/soignant/stripe-connect' },
        { icone: FileSignature, label: 'Mandat de facturation', route: '/soignant/mandat-facturation' },
        { icone: Zap, label: 'Avances (paiement rapide)', route: '/soignant/mes-avances' },
        { icone: Landmark, label: 'Charges sociales (URSSAF)', route: '/soignant/charges' },
      ]
    : [
        { icone: Banknote, label: 'Mes gains', route: '/soignant/mes-gains' },
        { icone: Receipt, label: 'Bulletins de paie', route: '/soignant/bulletins-paie' },
      ];

  const sections: SectionReglages[] = [
    {
      titre: 'Profil & activité',
      lignes: [
        { icone: User, label: 'Mon profil', route: '/soignant/profil' },
        { icone: FileText, label: 'Mes documents', route: '/soignant/mes-documents' },
        { icone: ShieldCheck, label: 'Mon score de fiabilité', route: '/soignant/score' },
        { icone: Scale, label: 'Litiges & contestations', route: '/soignant/litiges' },
      ],
    },
    {
      titre: 'Paiements',
      lignes: lignesPaiements,
    },
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
        { icone: HeartHandshake, label: 'Premium', route: '/soignant/premium' },
      ],
    },
    {
      lignes: [
        { icone: Settings, label: 'Paramètres', route: '/soignant/parametres' },
        { icone: LogOut, label: 'Se déconnecter', onClick: () => deconnexion(), variante: 'danger' as const, sansChevron: true },
      ],
    },
  ];

  return (
    <LayoutApp role="SOIGNANT">
      <EnteteCompte
        avatar={<Mascotte etat="happy" taille="md" className="shrink-0" />}
        titre={profil ? `${profil.prenom} ${profil.nom}` : 'Mon compte'}
        sousTitre={profil?.profession || undefined}
        badge={
          profil?.rpps_verifie ? (
            <BadgeRPPS rppsVerifie={profil.rpps_verifie} rpps={profil.numero_rpps} profession={profil.profession} />
          ) : undefined
        }
      />
      <ListeReglages sections={sections} />
    </LayoutApp>
  );
}
