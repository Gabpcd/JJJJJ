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
import { ConsentementPingGps } from '@/components/soignant/ConsentementPingGps';
import { ModalContacterJolene } from '@/components/ModalContacterJolene';
import { useTheme } from '@/hooks/useTheme';
import {
  User, ShieldCheck, LogOut,
  Mail, Phone, MapPin, KeyRound, FileText, Scale, Trash2,
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
  } | null>(null);
  const [contactOpen, setContactOpen] = useState(false);

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
    ...(estLiberal ? [{
      titre: 'Paiements & facturation',
      lignes: [
        { icone: CreditCard, label: 'Compte de paiement (Stripe)', route: '/soignant/stripe-connect' },
        { icone: FileText, label: 'Mandat de facturation', route: '/soignant/mandat-facturation' },
      ],
    }] : []),
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
        { icone: Trash2, label: 'Supprimer mon compte', route: '/supprimer-mon-compte' },
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

      {/* Session G3 — réglages de compte foldés depuis l'ancienne page
          /soignant/parametres (devenue une redirection vers ce hub). */}
      <div className="mt-8 space-y-6">
        <section>
          <h2 className="px-4 mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Connexion & sécurité
          </h2>
          <div className="rounded-2xl border border-border bg-card p-4 space-y-4">
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-sm">
                <Mail className="h-4 w-4 text-muted-foreground" />
                <span className="text-muted-foreground">E-mail :</span>
                <span className="text-foreground font-mono break-all">{user?.email || '—'}</span>
              </div>
              <div className="flex items-center gap-2 text-sm">
                <Phone className="h-4 w-4 text-muted-foreground" />
                <span className="text-muted-foreground">Téléphone :</span>
                <button
                  onClick={() => navigate('/soignant/profil')}
                  className="text-primary hover:underline"
                >
                  éditable depuis le profil
                </button>
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

        <section>
          <h2 className="px-4 mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Confidentialité & données
          </h2>
          <div className="rounded-2xl border border-border bg-card p-4">
            <p className="text-xs text-muted-foreground mb-3 flex items-start gap-2">
              <MapPin className="h-4 w-4 text-primary shrink-0 mt-0.5" />
              <span>
                Option facultative : si activée, ta position GPS est enregistrée pendant la
                durée de tes missions, pour renforcer la fiabilité du pointage et faciliter la
                résolution de litiges. Données conservées 30 jours puis supprimées.
              </span>
            </p>
            <div className="rounded-lg border border-border bg-background overflow-hidden">
              <ConsentementPingGps />
            </div>
          </div>
        </section>
      </div>

      <ModalContacterJolene open={contactOpen} onClose={() => setContactOpen(false)} source="compte-soignant" />
    </LayoutApp>
  );
}
