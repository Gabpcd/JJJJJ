import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ListeReglages, EnteteCompte, type SectionReglages } from '@/components/ui/ListeReglages';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { estEligibleLiberal } from '@/lib/regles-installation-liberal';
import { ChangementMotDePasse } from '@/components/soignant/ChangementMotDePasse';
import { SectionPaiements } from '@/components/profil-soignant/SectionPaiements';
import { ModalContacterJolene } from '@/components/ModalContacterJolene';
import { BuildStamp } from '@/components/BuildStamp';
import { useTheme } from '@/hooks/useTheme';
import {
  User, ShieldCheck, LogOut,
  Mail, Phone, KeyRound, FileText, Scale, Trash2,
  CreditCard, Gift, Rocket, Umbrella, GraduationCap, Bell,
  Search, Ban, BookOpen, Moon, Sun,
} from 'lucide-react';

export default function MonCompteSoignant() {
  usePageTitle('Mon compte');
  const { user, deconnexion } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const navigate = useNavigate();
  const [profil, setProfil] = useState<{
    prenom: string; nom: string; avatar_url: string | null;
    type_exercice: string | null; rpps_verifie: boolean; numero_rpps: string | null;
    profession: string | null; statut_liberal: string | null;
    mandat_facturation_signe: boolean | null; mandat_facturation_signe_le: string | null;
    est_compte_test: boolean;
  } | null>(null);
  const [contactOpen, setContactOpen] = useState(false);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('prenom, nom, avatar_url, type_exercice, rpps_verifie, numero_rpps, profession, statut_liberal, mandat_facturation_signe, mandat_facturation_signe_le, est_compte_test')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => { if (data) setProfil(data as any); });
  }, [user]);

  const estLiberal =
    profil?.type_exercice === 'LIBERAL' ||
    profil?.type_exercice === 'MIXTE' ||
    profil?.statut_liberal === 'ACTIF';

  // Profession éligible au libéral (pour Passer en libéral + Attestation 3200h)
  const eligibleLiberal = !!(profil?.profession && estEligibleLiberal(profil.profession));

  // Menu = ton COMPTE (qui tu es, combien tu gagnes, ta réputation, tes réglages).
  // Tout le reste = contextuel (dashboard, fiche mission, flow inscription).
  const sections: SectionReglages[] = [
    {
      titre: '',
      lignes: [
        { icone: User, label: 'Mon profil', route: '/soignant/profil' },
      ],
    },
    // Config paiement/facturation = CONFIG → Compte (source unique). « Charges sociales »
    // retirée d'ici : c'est de l'INFO → elle vit dans Revenus (entrée nommée).
    ...[{
      titre: 'Paiements & facturation',
      lignes: [
        ...(estLiberal ? [
          { icone: CreditCard, label: 'Compte de paiement (Stripe)', route: '/soignant/stripe-connect' },
          { icone: FileText, label: 'Mandat de facturation', route: '/soignant/mandat-facturation' },
        ] : []),
        {
          icone: CreditCard,
          label: 'Coordonnées bancaires',
          onClick: () => document.getElementById('paiements')?.scrollIntoView({ behavior: 'smooth', block: 'start' }),
          sansChevron: true,
        },
      ],
    }],
    // « Ma réputation » retiré : hub dissous, le score simple vit désormais sur le Profil.
    {
      // Section « Développement » renommée « Documents & protection ».
      titre: 'Documents & protection',
      lignes: [
        ...(eligibleLiberal && !estLiberal
          ? [{ icone: Rocket, label: 'Passer en libéral', route: '/soignant/passer-en-liberal' }] : []),
        ...(estLiberal || eligibleLiberal
          ? [{ icone: GraduationCap, label: 'Attestation d\'heures', route: '/soignant/attestation-heures' }] : []),
        { icone: Umbrella, label: 'Prévoyance', route: '/soignant/prevoyance' },
      ],
    },
    // Écrans prospectifs (recherche/dispo) remontés depuis l'ancien « Tous les
    // paramètres » ; Exclusions à part (négatif ≠ prospectif).
    {
      titre: 'Recherche & disponibilité',
      lignes: [
        { icone: Search, label: 'Recherches sauvegardées', route: '/soignant/parametres/recherches-sauvegardees' },
        { icone: Ban, label: 'Établissements exclus', route: '/soignant/exclusions' },
      ],
    },
    {
      titre: '',
      lignes: [
        { icone: Gift, label: 'Parrainage', route: '/soignant/parrainage' },
      ],
    },
    {
      titre: 'Suivi',
      lignes: [
        { icone: Scale, label: 'Litiges & contestations', route: '/soignant/litiges' },
      ],
    },
    {
      titre: 'Réglages',
      lignes: [
        { icone: Bell, label: 'Notifications', route: '/soignant/parametres/notifications' },
        // Toggle thème rapatrié ici depuis le header mobile (Lot 6b.1 — header épuré).
        {
          icone: theme === 'dark' ? Sun : Moon,
          label: theme === 'dark' ? 'Passer en thème clair' : 'Passer en thème sombre',
          onClick: toggleTheme,
          sansChevron: true,
        },
      ],
    },
    {
      titre: 'Aide & légal',
      lignes: [
        // Le FAB « ? » global a été retiré (Lot 6a.4 — il masquait des CTA
        // critiques) : l'aide et le contact vivent ici, leur place naturelle.
        { icone: BookOpen, label: 'Centre d\'aide', route: '/aide' },
        { icone: Mail, label: 'Contacter Jolene', onClick: () => setContactOpen(true), sansChevron: true },
        { icone: ShieldCheck, label: 'Confidentialité', route: '/confidentialite' },
        { icone: Scale, label: 'Conditions générales', route: '/cgu' },
        { icone: FileText, label: 'Mentions légales', route: '/mentions-legales' },
        { icone: Trash2, label: 'Supprimer mon compte', route: '/soignant/profil?tab=confidentialite#suppression-compte' },
      ],
    },
    {
      titre: '',
      lignes: [
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

      <section id="paiements" tabIndex={-1} className="mt-8 scroll-mt-20" aria-labelledby="titre-paiements">
        <h2 id="titre-paiements" className="px-4 mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          Paiements & coordonnées bancaires
        </h2>
        <SectionPaiements
          userId={user!.id}
          typeExercice={profil?.type_exercice ?? null}
          mandatFacturationSigne={profil?.mandat_facturation_signe ?? null}
          mandatFacturationSigneLe={profil?.mandat_facturation_signe_le ?? null}
          estCompteTest={profil?.est_compte_test ?? false}
        />
      </section>

      {/* Session G3 — réglages de compte foldés depuis l'ancienne page
          /soignant/parametres (devenue une redirection vers ce hub). */}
      <div className="mt-8 space-y-6">
        <section>
          <h2 className="px-4 mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Connexion & sécurité
          </h2>
          <div className="rounded-2xl border border-border bg-card p-4 space-y-4">
            <div className="space-y-2">
              <div className="grid grid-cols-[1.25rem_minmax(0,1fr)] items-start gap-2 text-sm">
                <Mail className="mt-0.5 h-4 w-4 text-muted-foreground" aria-hidden="true" />
                <div className="min-w-0">
                  <span className="block text-muted-foreground">E-mail</span>
                  <span className="block break-all font-mono text-foreground">{user?.email || '—'}</span>
                </div>
              </div>
              <div className="grid grid-cols-[1.25rem_minmax(0,1fr)] items-start gap-2 text-sm">
                <Phone className="mt-3.5 h-4 w-4 text-muted-foreground" aria-hidden="true" />
                <div className="min-w-0">
                  <span className="block text-muted-foreground">Téléphone</span>
                  <button
                    onClick={() => navigate('/soignant/profil')}
                    className="inline-flex min-h-11 items-center text-left text-primary hover:underline"
                  >
                    Modifier depuis le profil
                  </button>
                </div>
              </div>
            </div>

            <div className="border-t border-border pt-4">
              <h3 className="text-sm font-semibold text-foreground mb-3 flex items-center gap-2">
                <KeyRound className="h-4 w-4 text-primary" />
                Changer mon mot de passe
              </h3>
              <ChangementMotDePasse />
            </div>
          </div>
        </section>
      </div>

      <BuildStamp />
      <ModalContacterJolene open={contactOpen} onClose={() => setContactOpen(false)} source="compte-soignant" />
    </LayoutApp>
  );
}
