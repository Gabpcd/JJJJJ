import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowRight, X, CheckCircle2, UserCircle, FileUp, Search, FileSignature, MapPin,
  Building2, PlusCircle, Users, CreditCard, QrCode, Star, Shield, AlertTriangle,
  ClipboardCheck, FileText,
} from 'lucide-react';
import { UserRole } from '@/lib/types';
import { Progress } from '@/components/ui/progress';
import { supabase } from '@/integrations/supabase/client';

interface Etape {
  id: string;
  titre: string;
  description: string;
  icone: React.ElementType;
  lien?: string;
  labelLien?: string;
  encart?: { titre: string; texte: string; lien?: string; labelLien?: string };
}

const ETAPES_SOIGNANT: Etape[] = [
  { id: 'bienvenue', titre: 'Bienvenue sur Jolene 🎉', description: 'En quelques minutes, on vous présente l\'essentiel : trouver des missions, signer un contrat, pointer, et suivre votre score.', icone: UserCircle },
  { id: 'profil', titre: 'Complétez votre profil', description: 'Renseignez vos infos personnelles, profession et numéro RPPS. Plus votre profil est complet, plus vous obtenez de missions.', icone: UserCircle, lien: '/soignant/profil', labelLien: 'Aller au profil' },
  { id: 'documents', titre: 'Téléversez vos documents', description: 'Diplômes, pièce d\'identité, attestations. Ces documents sont obligatoires pour postuler aux missions.', icone: FileUp, lien: '/soignant/mes-documents?tab=justificatifs', labelLien: 'Ajouter mes documents' },
  { id: 'recherche', titre: 'Trouvez une mission', description: 'Parcourez les missions disponibles dans votre rayon. Filtrez par profession, type d\'établissement, taux horaire. Postulez en un clic.', icone: Search, lien: '/soignant/recherche-missions', labelLien: 'Voir les missions' },
  { id: 'pointage', titre: 'Pointage QR (recommandé)', description: 'Le jour J, scannez le QR affiché par l\'établissement pour pointer votre arrivée et votre départ. Si pas de QR : GPS ou code secours en backup.', icone: QrCode },
  { id: 'score', titre: 'Score Jolene & DPAE', description: 'Votre score qualité reflète votre fiabilité (notations, ponctualité, ancienneté). Pour signer un CDD, complétez vos infos DPAE (lieu de naissance, NIR, etc.).', icone: Star,
    encart: { titre: 'DPAE incomplète ?', texte: 'Pour pouvoir signer des CDD, remplissez votre identité DPAE complète (NIR, lieu de naissance, nationalité).', lien: '/soignant/mes-documents?tab=dpae', labelLien: 'Compléter ma DPAE' } },
  { id: 'parametres', titre: 'Paramètres & vie privée', description: 'Le GPS est utilisé à votre demande pour un pointage ou pour localiser votre profil. Jamais en continu ni en arrière-plan.', icone: Shield, lien: '/soignant/parametres', labelLien: 'Mes paramètres' },
];

const ETAPES_ETABLISSEMENT: Etape[] = [
  { id: 'bienvenue', titre: 'Bienvenue sur Jolene 🎉', description: 'En quelques minutes, on vous montre comment publier une mission, gérer les candidatures, signer le contrat, valider le pointage et facturer.', icone: Building2 },
  { id: 'profil', titre: 'Complétez votre établissement', description: 'Adresse, SIRET, FINESS, contact RH. Plus vos infos sont complètes, plus les soignants vous font confiance.', icone: Building2, lien: '/etablissement/parametres?tab=profil', labelLien: 'Compléter le profil' },
  { id: 'mission', titre: 'Publiez votre première mission', description: 'Décrivez le besoin, profession, dates, horaires, taux. Les soignants qualifiés sont notifiés automatiquement. Récap des coûts avant publication.', icone: PlusCircle, lien: '/etablissement/missions/creer', labelLien: 'Créer une mission' },
  { id: 'candidatures', titre: 'Gérez les candidatures', description: 'Consultez les profils des soignants intéressés, leur score qualité, leurs notations. Acceptez en un clic, paiement Stripe Connect.', icone: Users },
  { id: 'contrat', titre: 'Signature contrat & DPAE', description: 'Une fois la candidature acceptée, le contrat se génère automatiquement. Signature OTP par SMS. DPAE pré-remplie pour copier sur net-entreprises.fr.', icone: FileSignature },
  { id: 'pointage', titre: 'Affichage QR pointage', description: 'Imprimez ou affichez le QR mission. Le soignant le scanne pour pointer. Vous suivez les pointages en temps réel et les alertes anti-triche.', icone: QrCode, lien: '/etablissement/presences', labelLien: 'Voir le pointage' },
  { id: 'facturation', titre: 'Facturation & obligations', description: 'À la fin de chaque mission, validation des heures. Facturation automatique CDD ou libéral. Suivi des obligations financières.', icone: CreditCard, lien: '/etablissement/facturation', labelLien: 'Ma facturation' },
];

const STORAGE_KEY = 'onboarding_complete';

function getStorageKey(userId: string) {
  return `${STORAGE_KEY}_${userId}`;
}

interface OnboardingGuideProps {
  role: UserRole;
  userId: string;
}

export function OnboardingGuide({ role, userId }: OnboardingGuideProps) {
  const navigate = useNavigate();
  const [etapeCourante, setEtapeCourante] = useState(0);
  const [visible, setVisible] = useState(false);
  const [direction, setDirection] = useState<'next' | 'prev'>('next');

  // Sprint 6 PR 5 : persistance DB en priorité sur localStorage (multi-device)
  useEffect(() => {
    let cancelled = false;
    async function init() {
      const { data } = await supabase.rpc('fn_etat_onboarding' as any);
      if (cancelled) return;
      const result = data as any;
      if (result?.success && result.termine_le) {
        setVisible(false);
        localStorage.setItem(getStorageKey(userId), 'true');
        return;
      }
      // Fallback localStorage si RPC ne renvoie rien (compatibilité)
      const done = localStorage.getItem(getStorageKey(userId));
      if (!done) setVisible(true);
    }
    init();
    return () => { cancelled = true; };
  }, [userId]);

  async function marquerEtape(etapeId: string, termine: boolean = false) {
    try {
      await supabase.rpc('fn_marquer_etape_onboarding' as any, {
        p_etape_id: etapeId,
        p_termine: termine,
      });
    } catch {
      // best-effort, fallback localStorage suffit
    }
  }

  const etapes = role === 'SOIGNANT' ? ETAPES_SOIGNANT : ETAPES_ETABLISSEMENT;
  const progression = Math.round(((etapeCourante + 1) / etapes.length) * 100);

  const fermer = () => {
    localStorage.setItem(getStorageKey(userId), 'true');
    marquerEtape('TERMINE', true);
    setVisible(false);
  };

  const suivant = () => {
    if (etapeCourante < etapes.length - 1) {
      // Marquer l'étape actuelle comme complétée
      marquerEtape(etapes[etapeCourante].id, false);
      setDirection('next');
      setEtapeCourante(etapeCourante + 1);
    } else {
      fermer();
    }
  };

  const precedent = () => {
    if (etapeCourante > 0) {
      setDirection('prev');
      setEtapeCourante(etapeCourante - 1);
    }
  };

  if (!visible) return null;

  const etape = etapes[etapeCourante];
  const Icone = etape.icone;
  const isLast = etapeCourante === etapes.length - 1;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/55 p-4 overflow-y-auto" style={{ paddingTop: 'max(1rem, env(safe-area-inset-top))', paddingBottom: 'max(1rem, env(safe-area-inset-bottom))' }}>
      <div className="bg-card rounded-2xl shadow-2xl max-w-md w-full overflow-hidden animate-in fade-in zoom-in-95 duration-300 my-auto">
        {/* Header */}
        <div className="px-6 pt-6 pb-3">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-semibold text-primary">
              Étape {etapeCourante + 1} / {etapes.length}
            </span>
            <button
              onClick={fermer}
              className="text-muted-foreground hover:text-foreground transition-colors rounded-full p-1"
              aria-label="Passer l'introduction"
              title="Passer"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
          <Progress value={progression} className="h-1.5" />
        </div>

        {/* Content with transition */}
        <div
          key={etapeCourante}
          className={`px-6 py-6 animate-in duration-300 ${direction === 'next' ? 'slide-in-from-right-4' : 'slide-in-from-left-4'} fade-in`}
        >
          {/* Large icon */}
          <div className="flex justify-center mb-5">
            <div className="rounded-2xl p-5 bg-primary/10 animate-in zoom-in-50 duration-500">
              <Icone className="h-12 w-12 text-primary" />
            </div>
          </div>

          <div className="text-center space-y-2">
            <h2 className="text-lg font-bold text-foreground">{etape.titre}</h2>
            <p className="text-sm text-muted-foreground leading-relaxed">{etape.description}</p>
          </div>

          {etape.lien && (
            <button
              onClick={() => { fermer(); navigate(etape.lien!); }}
              className="mt-4 mx-auto flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
            >
              {etape.labelLien} <ArrowRight className="h-3.5 w-3.5" />
            </button>
          )}

          {etape.encart && (
            <div className="mt-4 rounded-xl bg-warning/5 border border-warning/30 p-3">
              <p className="text-xs font-semibold text-foreground mb-1 inline-flex items-center gap-1.5">
                <AlertTriangle className="h-3.5 w-3.5 text-warning" /> {etape.encart.titre}
              </p>
              <p className="text-xs text-muted-foreground">{etape.encart.texte}</p>
              {etape.encart.lien && (
                <button
                  onClick={() => { fermer(); navigate(etape.encart!.lien!); }}
                  className="mt-2 text-xs font-medium text-warning hover:underline inline-flex items-center gap-1"
                >
                  {etape.encart.labelLien} <ArrowRight className="h-3 w-3" />
                </button>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 flex items-center justify-between border-t border-border">
          <div className="flex gap-2">
            {etapeCourante > 0 && (
              <button
                onClick={precedent}
                className="text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                Précédent
              </button>
            )}
            {etapeCourante >= 3 && (
              <button
                onClick={fermer}
                className="text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                Passer
              </button>
            )}
          </div>
          <button
            onClick={suivant}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 transition-colors"
          >
            {isLast ? 'Commencer' : 'Suivant'}
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>

        {/* Step dots */}
        <div className="flex items-center justify-center gap-1.5 pb-5">
          {etapes.map((_, i) => (
            <button
              key={i}
              onClick={() => { setDirection(i > etapeCourante ? 'next' : 'prev'); setEtapeCourante(i); }}
              className={`h-1.5 rounded-full transition-all duration-300 ${
                i === etapeCourante
                  ? 'w-6 bg-primary'
                  : i < etapeCourante
                  ? 'w-1.5 bg-primary/50'
                  : 'w-1.5 bg-muted-foreground/20'
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
