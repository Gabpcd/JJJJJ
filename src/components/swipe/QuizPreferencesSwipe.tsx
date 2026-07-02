/**
 * QuizPreferencesSwipe — cold start du matching (7d-4, Lot 7 v2 A1).
 *
 * Mini-quiz 5 questions à l'arrivée sur Explorer (une seule fois) :
 * horaires · rythme · rayon · taux minimum · dispo urgences.
 * → pré-remplit les filtres de recherche (mêmes états que la sheet Filtres)
 * → amorce les préférences horaires du scoring (fn_initialiser_preferences_matching,
 *   qui n'écrase jamais des préférences déjà APPRISES : le déclaratif ne prime
 *   jamais sur les signaux réels de swipe)
 * → « dispo urgences » = opt-in au pool disponible_urgence existant.
 *
 * Skippable (« Plus tard ») — le deck marche sans, il apprendra en route.
 */
import { useState } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  DialogResponsive, DialogResponsiveContent, DialogResponsiveHeader,
  DialogResponsiveTitle, DialogResponsiveDescription, DialogResponsiveBody,
} from '@/components/ui/DialogResponsive';

export const CLE_QUIZ_PREFS = 'jolene_quiz_prefs_fait';

export interface ReponsesQuiz {
  horaire: 'JOUR' | 'NUIT' | 'TOUS';
  rythme: 'SEMAINE' | 'WEEKEND' | 'TOUS';
  rayonKm: number;
  tauxMin: number;
  dispoUrgence: boolean;
}

interface Props {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  /** Applique les réponses aux filtres de la page (rayon, taux, horaire). */
  onAppliquer: (r: ReponsesQuiz) => void;
}

function Chip({ actif, onClick, children }: { actif: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={actif}
      className={`rounded-full border px-3 py-1.5 text-sm min-h-[36px] transition-colors ${
        actif ? 'border-primary bg-primary/10 font-semibold text-foreground' : 'border-border text-muted-foreground hover:border-primary/40'
      }`}
    >
      {children}
    </button>
  );
}

export function QuizPreferencesSwipe({ open, onOpenChange, onAppliquer }: Props) {
  const [horaire, setHoraire] = useState<ReponsesQuiz['horaire']>('TOUS');
  const [rythme, setRythme] = useState<ReponsesQuiz['rythme']>('TOUS');
  const [rayonKm, setRayonKm] = useState(20);
  const [tauxMin, setTauxMin] = useState(0);
  const [dispoUrgence, setDispoUrgence] = useState(false);
  const [envoi, setEnvoi] = useState(false);

  const fermer = () => {
    localStorage.setItem(CLE_QUIZ_PREFS, '1');
    onOpenChange(false);
  };

  const valider = async () => {
    if (envoi) return;
    setEnvoi(true);
    try {
      // Amorçage des préférences apprises : la tranche choisie démarre à 0,8,
      // l'autre à 0,3 (« Les deux » = neutre 0,5) — l'apprentissage réel
      // affinera dès les premiers swipes.
      const [pNuit, pJour] = horaire === 'NUIT' ? [0.8, 0.3] : horaire === 'JOUR' ? [0.3, 0.8] : [0.5, 0.5];
      const [pWe, pSem] = rythme === 'WEEKEND' ? [0.8, 0.3] : rythme === 'SEMAINE' ? [0.3, 0.8] : [0.5, 0.5];
      await supabase.rpc('fn_initialiser_preferences_matching' as any, {
        p_pref_nuit: pNuit, p_pref_jour: pJour, p_pref_weekend: pWe, p_pref_semaine: pSem,
      });

      if (dispoUrgence) {
        const { data: { user } } = await supabase.auth.getUser();
        if (user) {
          await supabase.from('soignants').update({ disponible_urgence: true } as any).eq('id', user.id);
        }
      }

      onAppliquer({ horaire, rythme, rayonKm, tauxMin, dispoUrgence });
      toast.success('C\'est noté — ton deck est personnalisé ✨');
    } catch { /* best effort — les filtres locaux sont appliqués quoi qu'il arrive */ }
    setEnvoi(false);
    fermer();
  };

  return (
    <DialogResponsive open={open} onOpenChange={(o) => { if (!o) fermer(); else onOpenChange(o); }}>
      <DialogResponsiveContent maxWidth="sm">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>5 questions pour un deck qui te ressemble</DialogResponsiveTitle>
          <DialogResponsiveDescription>
            30 secondes — et le deck apprendra ensuite de chacun de tes swipes.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody>
          <div className="space-y-4">
            <div>
              <p className="text-sm font-semibold text-foreground mb-1.5">Tu préfères travailler…</p>
              <div className="flex gap-2 flex-wrap">
                <Chip actif={horaire === 'JOUR'} onClick={() => setHoraire('JOUR')}>☀️ De jour</Chip>
                <Chip actif={horaire === 'NUIT'} onClick={() => setHoraire('NUIT')}>🌙 De nuit</Chip>
                <Chip actif={horaire === 'TOUS'} onClick={() => setHoraire('TOUS')}>Les deux</Chip>
              </div>
            </div>

            <div>
              <p className="text-sm font-semibold text-foreground mb-1.5">Plutôt…</p>
              <div className="flex gap-2 flex-wrap">
                <Chip actif={rythme === 'SEMAINE'} onClick={() => setRythme('SEMAINE')}>Semaine</Chip>
                <Chip actif={rythme === 'WEEKEND'} onClick={() => setRythme('WEEKEND')}>Week-end</Chip>
                <Chip actif={rythme === 'TOUS'} onClick={() => setRythme('TOUS')}>Les deux</Chip>
              </div>
            </div>

            <div>
              <p className="text-sm font-semibold text-foreground mb-1.5">Jusqu'à quelle distance ?</p>
              <div className="flex gap-2 flex-wrap">
                {[5, 10, 20, 50].map(km => (
                  <Chip key={km} actif={rayonKm === km} onClick={() => setRayonKm(km)}>{km} km</Chip>
                ))}
              </div>
            </div>

            <div>
              <p className="text-sm font-semibold text-foreground mb-1.5">Taux horaire minimum ?</p>
              <div className="flex gap-2 flex-wrap">
                <Chip actif={tauxMin === 0} onClick={() => setTauxMin(0)}>Peu importe</Chip>
                {[25, 30, 35].map(t => (
                  <Chip key={t} actif={tauxMin === t} onClick={() => setTauxMin(t)}>≥ {t} €/h</Chip>
                ))}
              </div>
            </div>

            <div>
              <p className="text-sm font-semibold text-foreground mb-1.5">
                Partante pour des missions urgentes (dernière minute, souvent mieux payées) ?
              </p>
              <div className="flex gap-2 flex-wrap">
                <Chip actif={dispoUrgence} onClick={() => setDispoUrgence(true)}>⚡ Oui, préviens-moi</Chip>
                <Chip actif={!dispoUrgence} onClick={() => setDispoUrgence(false)}>Non merci</Chip>
              </div>
            </div>

            <div className="flex gap-2 pt-1">
              <BoutonY2K className="flex-1" loading={envoi} onClick={valider}>
                C'est parti 🚀
              </BoutonY2K>
              <BoutonY2K variant="ghost" onClick={fermer} disabled={envoi}>
                Plus tard
              </BoutonY2K>
            </div>
          </div>
        </DialogResponsiveBody>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}
