import { useState } from 'react';
import { HelpCircle, RotateCcw, ExternalLink, CheckCircle2, AlertTriangle } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

interface Props {
  onComplete?: (recommandation: 'SECTEUR_2_ELIGIBLE' | 'SECTEUR_1_UNIQUEMENT') => void;
}

const QUESTIONS = [
  "Es-tu ou as-tu été ancien chef de clinique des universités — assistant des hôpitaux ?",
  "Es-tu ou as-tu été ancien assistant hospitalier universitaire ?",
  "Es-tu ou as-tu été praticien hospitalier (PH), ancien assistant des hôpitaux, médecin des armées, ou ancien chef de clinique de médecine générale ?",
] as const;

export function QuizSecteurMedecin({ onComplete }: Props) {
  const [answers, setAnswers] = useState<(boolean | null)[]>([null, null, null]);
  const [step, setStep] = useState(0);

  const reset = () => {
    setAnswers([null, null, null]);
    setStep(0);
  };

  const answer = (val: boolean) => {
    const next = [...answers];
    next[step] = val;
    setAnswers(next);
    if (step < QUESTIONS.length - 1) {
      setStep(step + 1);
    } else if (onComplete) {
      const eligible = next.some(a => a === true);
      onComplete(eligible ? 'SECTEUR_2_ELIGIBLE' : 'SECTEUR_1_UNIQUEMENT');
    }
  };

  const termine = answers.every(a => a !== null);
  const eligibleSecteur2 = termine && answers.some(a => a === true);

  return (
    <div className="card-base">
      <div className="flex items-start gap-2 mb-3">
        <HelpCircle className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div>
          <h3 className="text-base font-bold text-foreground">Es-tu éligible au secteur 2 ?</h3>
          <p className="text-xs text-muted-foreground mt-1">
            Le secteur détermine tes tarifs. Ce choix est majeur et partiellement irréversible. Ce quiz t'aide à voir ton éligibilité.
          </p>
        </div>
      </div>

      {!termine && (
        <div className="space-y-3 mt-4">
          <div className="flex items-center gap-2 text-xs text-muted-foreground mb-2">
            <span>Question {step + 1} / {QUESTIONS.length}</span>
            <div className="flex-1 h-1 bg-muted rounded-full overflow-hidden">
              <div
                className="h-full bg-primary transition-all"
                style={{ width: `${((step) / QUESTIONS.length) * 100}%` }}
              />
            </div>
          </div>
          <p className="text-sm text-foreground font-medium">{QUESTIONS[step]}</p>
          <div className="flex gap-2">
            <BoutonY2K type="button" variant="secondary" onClick={() => answer(true)} className="flex-1">
              Oui
            </BoutonY2K>
            <BoutonY2K type="button" variant="secondary" onClick={() => answer(false)} className="flex-1">
              Non
            </BoutonY2K>
          </div>
        </div>
      )}

      {termine && (
        <div className="mt-4 space-y-3">
          {eligibleSecteur2 ? (
            <div className="rounded-xl border-2 border-success/40 bg-success/5 p-3 flex items-start gap-2">
              <CheckCircle2 className="h-5 w-5 text-success shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-semibold text-success">Tu es ÉLIGIBLE au secteur 2</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Tu peux choisir entre le secteur 1 (honoraires opposables) ou le secteur 2 (honoraires libres avec tact et mesure). Attention : ce choix se fait à la 1ère installation et le secteur 1 est irrévocable.
                </p>
              </div>
            </div>
          ) : (
            <div className="rounded-xl border-2 border-warning/40 bg-warning/5 p-3 flex items-start gap-2">
              <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-semibold text-warning">Éligible uniquement au secteur 1</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Tu es éligible UNIQUEMENT au secteur 1 (honoraires opposables selon la convention médicale). Le secteur 2 nécessite des titres hospitaliers spécifiques que tu ne détiens pas selon ce quiz. Le secteur 3 (non conventionné) reste possible mais tes patients seront très faiblement remboursés.
                </p>
              </div>
            </div>
          )}
          <div className="flex gap-2 flex-wrap">
            <BoutonY2K type="button" variant="ghost" size="sm" onClick={reset} className="gap-1.5" iconeGauche={<RotateCcw className="h-3.5 w-3.5" />}>
              Recommencer
            </BoutonY2K>
            <a
              href="https://www.ameli.fr/medecin/exercice-liberal/accompagnement-l-installation/avant-l-installation/le-conventionnement-avec-l-assurance-maladie"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-xs text-primary hover:underline px-2"
            >
              En savoir plus sur Ameli <ExternalLink className="h-3 w-3" />
            </a>
          </div>
        </div>
      )}
    </div>
  );
}
