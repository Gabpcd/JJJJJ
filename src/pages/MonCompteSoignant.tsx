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
import {
  User, Banknote, ShieldCheck, Settings, LogOut,
  Mail, Phone, MapPin, KeyRound, FileText, Scale, Trash2,
} from 'lucide-react';

export default function MonCompteSoignant() {
  usePageTitle('Mon profil');
  const { user, deconnexion } = useAuth();
  const navigate = useNavigate();
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

  // Menu = ton COMPTE (qui tu es, combien tu gagnes, ta réputation, tes réglages).
  // Tout le reste = contextuel (dashboard, fiche mission, flow inscription).
  const sections: SectionReglages[] = [
    {
      titre: '',
      lignes: [
        { icone: User, label: 'Mon profil', route: '/soignant/profil' },
        { icone: Banknote, label: 'Revenus', route: '/soignant/mes-gains' },
        { icone: ShieldCheck, label: 'Ma réputation', route: '/soignant/reputation' },
        { icone: Settings, label: 'Paramètres', route: '/soignant/parametres-complet' },
        { icone: LogOut, label: 'Se déconnecter', onClick: () => deconnexion(), variante: 'danger' as const, sansChevron: true },
      ],
    },
    {
      titre: 'Légal',
      lignes: [
        { icone: ShieldCheck, label: 'Confidentialité', route: '/confidentialite' },
        { icone: Scale, label: 'Conditions générales', route: '/cgu' },
        { icone: FileText, label: 'Mentions légales', route: '/mentions-legales' },
        { icone: Trash2, label: 'Supprimer mon compte', route: '/supprimer-mon-compte' },
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
            Mon compte
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
            Suivi GPS pendant les missions
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
    </LayoutApp>
  );
}
