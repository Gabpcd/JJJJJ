import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import {
  ShieldCheck, Clock, Send, CheckCircle2, AlertTriangle, PauseCircle, XCircle, Zap,
  type LucideIcon,
} from 'lucide-react';

/**
 * Bloc « À venir » — cycle de paiement rapide ⚡ (escrow) côté soignant.
 * Cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md.
 *
 * Invariants respectés :
 *  - I2 : jamais « garanti » ; wording « Réservé » / « le montant de ta confirmation ».
 *  - I3 : seule la part soignant (honoraires_cents) est affichée.
 *  - I4 : icônes lucide, aucun emoji.
 *  - I5 : masqué entièrement si aucun paiement escrow (pas de récompense fantôme).
 *  - « Versé partiellement » NON affiché (gap backend §9.4) : REMBOURSE post-versement
 *    tombe en « Versé », pré-release en « Paiement annulé ».
 */

type EtatEscrow =
  | 'RESERVE' | 'ATTENTE_VALIDATION' | 'VERSEMENT_EN_COURS'
  | 'VERSE' | 'RETARDE' | 'LITIGE' | 'ANNULE';

interface LigneEscrow {
  mission_id: string;
  mission_intitule: string | null;
  etablissement_nom: string | null;
  honoraires_cents: number;
  etat: EtatEscrow;
  date_affichee: string | null;
  mission_date: string | null;
  a_litige: boolean;
}

const EUR = new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' });
const eur = (cents: number) => EUR.format((cents ?? 0) / 100);
const jour = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }) : null;

// Config par état : libellé, icône lucide, couleur sémantique, ligne d'explication.
const CONFIG: Record<EtatEscrow, {
  label: (l: LigneEscrow) => string;
  icon: LucideIcon;
  tone: 'info' | 'success' | 'warning' | 'neutral';
  aide: (l: LigneEscrow) => string;
  aVenir: boolean; // fait partie du bloc « À venir »
}> = {
  RESERVE: {
    label: () => 'Réservé', icon: ShieldCheck, tone: 'info', aVenir: true,
    aide: () => 'le montant de ta confirmation, mis de côté',
  },
  ATTENTE_VALIDATION: {
    label: () => 'En attente de validation des heures', icon: Clock, tone: 'info', aVenir: true,
    aide: () => "l'établissement valide tes heures (automatique sous 72 h)",
  },
  VERSEMENT_EN_COURS: {
    label: (l) => (jour(l.date_affichee) ? `Versement en cours — estimé le ${jour(l.date_affichee)}` : 'Versement en cours'),
    icon: Send, tone: 'info', aVenir: true,
    aide: () => 'ton virement est en route',
  },
  RETARDE: {
    label: () => 'Paiement retardé', icon: AlertTriangle, tone: 'warning', aVenir: true,
    aide: (l) => (jour(l.date_affichee) ? `nouvelle tentative le ${jour(l.date_affichee)}` : 'nous relançons le règlement'),
  },
  LITIGE: {
    label: () => 'Paiement en litige', icon: PauseCircle, tone: 'warning', aVenir: true,
    aide: () => 'voir le litige de la mission',
  },
  VERSE: {
    label: (l) => (jour(l.date_affichee) ? `Versé le ${jour(l.date_affichee)}` : 'Versé'),
    icon: CheckCircle2, tone: 'success', aVenir: false,
    aide: () => '',
  },
  ANNULE: {
    label: () => 'Paiement annulé', icon: XCircle, tone: 'neutral', aVenir: false,
    aide: () => 'contacte le support si besoin',
  },
};

const TONE_CLASSES: Record<string, string> = {
  info: 'text-jolene-mauve-600 bg-jolene-mauve-50',
  success: 'text-emerald-600 bg-emerald-50',
  warning: 'text-amber-600 bg-amber-50',
  neutral: 'text-muted-foreground bg-muted',
};

export default function PaiementsEscrowAVenir() {
  const [lignes, setLignes] = useState<LigneEscrow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let vivant = true;
    (async () => {
      const { data, error } = await supabase.rpc('fn_mes_paiements_escrow' as any);
      if (!vivant) return;
      if (!error && Array.isArray(data)) setLignes(data as unknown as LigneEscrow[]);
      setLoading(false);
    })();
    return () => { vivant = false; };
  }, []);

  // I5 : rien à montrer → composant absent.
  if (loading || lignes.length === 0) return null;

  const aVenir = lignes.filter((l) => CONFIG[l.etat]?.aVenir);
  const verses = lignes.filter((l) => l.etat === 'VERSE');

  const Ligne = ({ l }: { l: LigneEscrow }) => {
    const c = CONFIG[l.etat];
    if (!c) return null;
    const Icone = c.icon;
    const contenu = (
      <div className="flex items-center gap-3 p-3 rounded-2xl border border-border bg-card">
        <div className={`shrink-0 h-9 w-9 rounded-full grid place-items-center ${TONE_CLASSES[c.tone]}`}>
          <Icone className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-foreground truncate">{c.label(l)}</p>
          <p className="text-xs text-muted-foreground truncate">
            {l.etablissement_nom || l.mission_intitule || 'Mission'}
            {c.aide(l) ? ` · ${c.aide(l)}` : ''}
          </p>
        </div>
        <div className="shrink-0 text-sm font-semibold text-foreground tabular-nums">{eur(l.honoraires_cents)}</div>
      </div>
    );
    // Litige → lien vers le détail de la mission (action).
    if (l.etat === 'LITIGE') {
      return <Link to={`/soignant/missions/${l.mission_id}`} className="block active:opacity-80">{contenu}</Link>;
    }
    return contenu;
  };

  return (
    <section className="mb-5">
      <div className="flex items-center gap-1.5 mb-2">
        <Zap className="h-4 w-4 text-jolene-mauve-500" />
        <h2 className="text-sm font-semibold text-foreground">Paiement rapide</h2>
      </div>

      {aVenir.length > 0 && (
        <div className="space-y-2">
          <p className="text-xs text-muted-foreground">À venir</p>
          {aVenir.map((l) => <Ligne key={l.mission_id} l={l} />)}
        </div>
      )}

      {verses.length > 0 && (
        <div className="space-y-2 mt-3">
          <p className="text-xs text-muted-foreground">Récemment versé</p>
          {verses.slice(0, 3).map((l) => <Ligne key={l.mission_id} l={l} />)}
        </div>
      )}
    </section>
  );
}
