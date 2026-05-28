import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, User, FileText, Sliders, Calendar, Shield, Bell, Search, Mail, Phone, MapPin, Landmark, CheckCircle, AlertCircle, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChangementMotDePasse } from '@/components/soignant/ChangementMotDePasse';
import { ConsentementPingGps } from '@/components/soignant/ConsentementPingGps';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { toast } from 'sonner';

type SectionKey = 'compte' | 'banque' | 'identite' | 'preferences' | 'dispos' | 'rgpd' | 'avance';

const SECTIONS: Array<{ key: SectionKey; titre: string; icon: typeof User; description: string; cta?: { label: string; path: string } }> = [
  {
    key: 'compte',
    titre: 'Mon compte',
    icon: User,
    description: 'Email, téléphone, changement de mot de passe.',
  },
  {
    key: 'banque',
    titre: 'Coordonnées bancaires',
    icon: Landmark,
    description: 'Votre IBAN pour recevoir vos primes de parrainage par virement.',
  },
  {
    key: 'identite',
    titre: 'Identité et documents',
    icon: FileText,
    description: 'Vos données identité, RPPS, CNI, RIB, attestations et DPAE.',
    cta: { label: 'Aller à mon profil', path: '/soignant/profil' },
  },
  {
    key: 'preferences',
    titre: 'Préférences mission',
    icon: Sliders,
    description: 'Professions, rayon, taux, pool urgence, SMS et consentement GPS.',
    cta: { label: 'Éditer mes préférences', path: '/soignant/profil?tab=preferences' },
  },
  {
    key: 'dispos',
    titre: 'Disponibilités et calendrier',
    icon: Calendar,
    description: 'Planning, recherches sauvegardées et synchronisation calendrier.',
  },
  {
    key: 'rgpd',
    titre: 'Données personnelles (RGPD)',
    icon: Shield,
    description: 'Exporter mes données ou supprimer mon compte. Géré depuis la section confidentialité du profil.',
    cta: { label: 'Confidentialité (profil)', path: '/soignant/profil?tab=confidentialite' },
  },
  {
    key: 'avance',
    titre: 'Paramètres avancés',
    icon: Sliders,
    description: 'Mode sombre, langue de l\'interface (FR uniquement pour l\'instant).',
  },
];

/**
 * Page paramètres soignant unifiée (Sprint 5.5 PR 5).
 *
 * Fix P0-3 audit Sprint 5 : avant, les paramètres soignant étaient éparpillés
 * dans `/soignant/profil` (tabs préférences/confidentialité) + des sous-routes
 * `/soignant/parametres/notifications` etc. Aucune page parente.
 *
 * Cette page sert de hub unique avec navigation vers les sous-sections existantes.
 * Les composants de fond (ChangementMotDePasse, ConsentementPingGps) sont
 * ajoutés en PR 6 et PR 7.
 */
export default function PageParametresSoignant() {
  usePageTitle('Paramètres');
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const sectionInit = (searchParams.get('section') as SectionKey) || 'compte';
  const [selectionnee, setSelectionnee] = useState<SectionKey>(sectionInit);

  return (
    <LayoutApp role="SOIGNANT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Sliders className="h-6 w-6 text-primary" /> Paramètres
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Gérez votre compte, vos préférences et vos données personnelles depuis un seul endroit.
        </p>
      </div>

      {/* Navigation rapide vers les sous-pages existantes */}
      <div className="mb-6 grid grid-cols-1 sm:grid-cols-2 gap-3">
        <button
          onClick={() => navigate('/soignant/parametres/notifications')}
          className="card-base flex items-center gap-3 text-left hover:border-primary transition-colors"
        >
          <Bell className="h-5 w-5 text-primary shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">Notifications</p>
            <p className="text-xs text-muted-foreground truncate">Email, SMS, push, in-app par événement</p>
          </div>
        </button>
        <button
          onClick={() => navigate('/soignant/parametres/recherches-sauvegardees')}
          className="card-base flex items-center gap-3 text-left hover:border-primary transition-colors"
        >
          <Search className="h-5 w-5 text-primary shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">Recherches sauvegardées</p>
            <p className="text-xs text-muted-foreground truncate">Filtres et alertes missions</p>
          </div>
        </button>
      </div>

      {/* Sections principales */}
      <div className="flex gap-4 flex-col sm:flex-row">
        {/* Sidebar */}
        <nav className="sm:w-64 shrink-0">
          <ul className="space-y-1">
            {SECTIONS.map((s) => {
              const Icon = s.icon;
              const active = selectionnee === s.key;
              return (
                <li key={s.key}>
                  <button
                    onClick={() => setSelectionnee(s.key)}
                    className={`w-full text-left px-3 py-2 rounded-lg flex items-center gap-2 text-sm transition-colors ${
                      active
                        ? 'bg-primary/10 text-primary font-semibold'
                        : 'text-foreground hover:bg-muted'
                    }`}
                  >
                    <Icon className="h-4 w-4" />
                    {s.titre}
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>

        {/* Contenu */}
        <section className="flex-1 min-w-0">
          <SectionContent
            section={selectionnee}
            onNavigate={(path) => navigate(path)}
          />
        </section>
      </div>
    </LayoutApp>
  );
}

function SectionContent({ section, onNavigate }: { section: SectionKey; onNavigate: (path: string) => void }) {
  const meta = SECTIONS.find((s) => s.key === section);
  if (!meta) return null;
  const Icon = meta.icon;

  return (
    <div className="card-base space-y-3">
      <div className="flex items-center gap-2">
        <Icon className="h-5 w-5 text-primary" />
        <h2 className="text-lg font-bold text-foreground">{meta.titre}</h2>
      </div>
      <p className="text-sm text-muted-foreground">{meta.description}</p>

      {section === 'compte' && <PlaceholderCompte />}
      {section === 'banque' && <SectionBanque />}
      {section === 'preferences' && (
        <PlaceholderPreferences onNavigate={() => onNavigate('/soignant/profil?tab=preferences')} />
      )}
      {section === 'identite' && (
        <PlaceholderIdentite onNavigate={() => onNavigate('/soignant/profil')} />
      )}
      {section === 'dispos' && <PlaceholderDispos onNavigate={onNavigate} />}
      {section === 'rgpd' && (
        <PlaceholderRgpd onNavigate={() => onNavigate('/soignant/profil?tab=confidentialite')} />
      )}
      {section === 'avance' && <PlaceholderAvance />}
    </div>
  );
}

function PlaceholderCompte() {
  const { user } = useAuth();
  return (
    <div className="space-y-5">
      {/* Email + téléphone affichés en read-only avec lien vers profil pour édition */}
      <div className="space-y-2">
        <div className="flex items-center gap-2 text-sm">
          <Mail className="h-4 w-4 text-muted-foreground" />
          <span className="text-muted-foreground">E-mail :</span>
          <span className="text-foreground font-mono">{user?.email || '—'}</span>
        </div>
        <div className="flex items-center gap-2 text-sm">
          <Phone className="h-4 w-4 text-muted-foreground" />
          <span className="text-muted-foreground">Téléphone :</span>
          <span className="text-muted-foreground italic">éditable depuis le profil</span>
        </div>
      </div>

      <div className="border-t border-border pt-4">
        <h3 className="text-sm font-semibold text-foreground mb-3">Changer mon mot de passe</h3>
        <ChangementMotDePasse />
      </div>
    </div>
  );
}

function PlaceholderPreferences({ onNavigate }: { onNavigate: () => void }) {
  return (
    <div className="space-y-5 text-sm">
      <div className="space-y-3 text-muted-foreground">
        <p>Configurez vos professions, votre rayon de déplacement, vos types de contrat acceptés, votre taux minimum, et activez ou non le pool urgence.</p>
        <button onClick={onNavigate} className="btn-secondary text-sm">
          Éditer mes préférences pro
        </button>
      </div>

      <div className="border-t border-border pt-4">
        <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-2">
          <MapPin className="h-4 w-4 text-primary" />
          Suivi GPS pendant les missions
        </h3>
        <p className="text-xs text-muted-foreground mb-3">
          Option facultative Sprint 4.5 : si activée, votre position GPS est enregistrée toutes les minutes pendant la durée de vos missions, pour renforcer la fiabilité du pointage et faciliter la résolution de litiges. Données conservées 30 jours puis supprimées.
        </p>
        <div className="rounded-lg border border-border bg-background p-0 overflow-hidden">
          <ConsentementPingGps />
        </div>
      </div>
    </div>
  );
}

function PlaceholderIdentite({ onNavigate }: { onNavigate: () => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>Vos pièces justificatives (CNI, RPPS, RIB), attestations, DPAE et données identité sont centralisées dans votre profil.</p>
      <button onClick={onNavigate} className="btn-secondary text-sm">
        Aller à mon profil
      </button>
    </div>
  );
}

function PlaceholderDispos({ onNavigate }: { onNavigate: (path: string) => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>Synchronisez votre calendrier externe et configurez vos disponibilités.</p>
      <div className="flex flex-wrap gap-2">
        <button onClick={() => onNavigate('/soignant/planning')} className="btn-secondary text-sm">
          Mon planning
        </button>
        <button onClick={() => onNavigate('/soignant/parametres/recherches-sauvegardees')} className="btn-secondary text-sm">
          Recherches sauvegardées
        </button>
      </div>
    </div>
  );
}

function PlaceholderRgpd({ onNavigate }: { onNavigate: () => void }) {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>
        Vous pouvez à tout moment exporter vos données personnelles (JSON ou CSV) ou supprimer définitivement votre compte. Ces actions sont protégées par confirmation et audit RGPD.
      </p>
      <button onClick={onNavigate} className="btn-secondary text-sm">
        Confidentialité (profil)
      </button>
    </div>
  );
}

function validateIbanChecksum(iban: string): boolean {
  const cleaned = iban.toUpperCase().replace(/\s/g, '');
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$/.test(cleaned)) return false;
  const rearranged = cleaned.slice(4) + cleaned.slice(0, 4);
  let numeric = '';
  for (const c of rearranged) {
    numeric += c >= 'A' && c <= 'Z' ? (c.charCodeAt(0) - 55).toString() : c;
  }
  let remainder = 0;
  for (const c of numeric) {
    remainder = (remainder * 10 + parseInt(c)) % 97;
  }
  return remainder === 1;
}

function formatIbanDisplay(iban: string): string {
  return iban.replace(/(.{4})/g, '$1 ').trim();
}

function SectionBanque() {
  const [iban, setIban] = useState('');
  const [titulaire, setTitulaire] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [current, setCurrent] = useState<{ iban_renseigne: boolean; iban_last4: string | null; iban_titulaire: string | null } | null>(null);

  useEffect(() => {
    supabase.rpc('fn_consulter_mon_iban' as any).then(({ data }: any) => {
      if (data && !data.error) setCurrent(data);
      setLoading(false);
    });
  }, []);

  const ibanClean = iban.toUpperCase().replace(/\s/g, '');
  const ibanValid = ibanClean.length >= 14 && validateIbanChecksum(ibanClean);

  const submit = async () => {
    if (!ibanValid || !titulaire.trim()) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('fn_enregistrer_mon_iban' as any, {
      p_iban: ibanClean,
      p_titulaire: titulaire.trim(),
    });
    setSaving(false);
    const result = data as any;
    if (error) {
      toast.error(error.message);
      return;
    }
    if (result?.error) {
      toast.error(result.error);
      return;
    }
    toast.success(result?.message || 'IBAN enregistré');
    setCurrent({ iban_renseigne: true, iban_last4: result.iban_last4, iban_titulaire: result.titulaire });
    setIban('');
    setTitulaire('');
  };

  if (loading) {
    return <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin text-muted-foreground" /></div>;
  }

  return (
    <div className="space-y-5">
      {current?.iban_renseigne && (
        <div className="flex items-start gap-3 rounded-xl border border-primary/20 bg-primary/5 p-4">
          <CheckCircle className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">IBAN enregistré</p>
            <p className="text-sm text-muted-foreground font-mono mt-1">
              •••• •••• •••• •••• •••• {current.iban_last4}
            </p>
            {current.iban_titulaire && (
              <p className="text-xs text-muted-foreground mt-0.5">Titulaire : {current.iban_titulaire}</p>
            )}
          </div>
        </div>
      )}

      <div className="rounded-xl border border-border bg-background p-4 space-y-4">
        <div>
          <h3 className="text-sm font-semibold text-foreground mb-1">
            {current?.iban_renseigne ? 'Modifier mon IBAN' : 'Ajouter mon IBAN'}
          </h3>
          <p className="text-xs text-muted-foreground">
            Votre IBAN est utilisé exclusivement pour le versement de vos primes de parrainage.
            Il n'est jamais partagé avec l'établissement. Vous seul(e) pouvez le voir et le modifier.
          </p>
        </div>

        <div className="space-y-3">
          <div>
            <label htmlFor="iban-input" className="text-xs font-medium text-foreground block mb-1">IBAN</label>
            <input
              id="iban-input"
              type="text"
              value={iban}
              onChange={(e) => setIban(e.target.value.toUpperCase())}
              placeholder="FR76 3000 6000 0112 3456 7890 189"
              className="w-full rounded-lg border border-border bg-background px-3 py-2.5 text-base md:text-sm font-mono text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
              autoComplete="off"
              spellCheck={false}
            />
            {iban.length > 4 && !ibanValid && (
              <p className="text-xs text-destructive mt-1 flex items-center gap-1">
                <AlertCircle className="h-3 w-3" /> IBAN invalide — vérifiez votre saisie
              </p>
            )}
            {ibanValid && (
              <p className="text-xs text-primary mt-1 flex items-center gap-1">
                <CheckCircle className="h-3 w-3" /> {formatIbanDisplay(ibanClean)}
              </p>
            )}
          </div>

          <div>
            <label htmlFor="titulaire-input" className="text-xs font-medium text-foreground block mb-1">Nom du titulaire</label>
            <input
              id="titulaire-input"
              type="text"
              value={titulaire}
              onChange={(e) => setTitulaire(e.target.value)}
              placeholder="Prénom Nom"
              className="w-full rounded-lg border border-border bg-background px-3 py-2.5 text-base md:text-sm text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
              autoComplete="name"
            />
          </div>
        </div>

        <BoutonY2K
          variant="primary"
          onClick={submit}
          disabled={!ibanValid || !titulaire.trim() || saving}
          className="w-full"
        >
          {saving ? 'Enregistrement…' : current?.iban_renseigne ? 'Mettre à jour l\'IBAN' : 'Enregistrer l\'IBAN'}
        </BoutonY2K>
      </div>
    </div>
  );
}

function PlaceholderAvance() {
  return (
    <div className="space-y-3 text-sm text-muted-foreground">
      <p>
        Mode sombre : géré automatiquement selon les préférences système, et activable via l'icône en haut de page.
      </p>
      <p>Langue de l'interface : Français (FR) uniquement pour l'instant.</p>
    </div>
  );
}
