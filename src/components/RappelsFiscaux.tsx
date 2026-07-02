/**
 * RappelsFiscaux — échéances fiscales du libéral, branchées sur le régime fiscal.
 *
 * §7.7 Lot 7a — règles de copy :
 * - Jamais un numéro de formulaire seul à côté d'une date (« 2035 — 15 mai 2027 »
 *   se lit comme une année et sème la confusion). Toujours : action en langage
 *   clair + année des revenus + formulaire entre parenthèses.
 * - Micro-BNC (défaut, tag « à confirmer » tant que non répondu) : PAS de 2035 —
 *   la déclaration passe par la 2042-C-PRO avec la déclaration de revenus.
 * - URSSAF et CARPIMKO sont communs aux deux régimes.
 */
import { useMemo } from 'react';
import { Calendar } from 'lucide-react';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';

export type RegimeFiscal = 'MICRO_BNC' | 'DECLARATION_CONTROLEE';

interface RappelsFiscauxProps {
  regimeFiscal?: RegimeFiscal | null;
  regimeFiscalConfirme?: boolean;
}

function getProchainTrimestreURSSAF(): Date {
  const now = new Date();
  const y = now.getFullYear();
  const echeances = [
    new Date(y, 0, 5), new Date(y, 3, 5), new Date(y, 6, 5), new Date(y, 9, 5),
  ];
  return echeances.find(d => d > now) || new Date(y + 1, 0, 5);
}

function getEcheanceCARPIMKO(): Date {
  const now = new Date();
  const avril = new Date(now.getFullYear(), 3, 1);
  return avril > now ? avril : new Date(now.getFullYear() + 1, 3, 1);
}

/** Déclaration contrôlée : dépôt de la 2035 — 15 mai de l'année suivant les revenus. */
function getEcheance2035(): Date {
  const now = new Date();
  const mai = new Date(now.getFullYear(), 4, 15);
  return mai > now ? mai : new Date(now.getFullYear() + 1, 4, 15);
}

/** Micro-BNC : la 2042-C-PRO part avec la déclaration de revenus (fin mai–début
 *  juin selon le département) — date indicative, affichée avec ≈. */
function getEcheance2042CPro(): Date {
  const now = new Date();
  const finMai = new Date(now.getFullYear(), 4, 31);
  return finMai > now ? finMai : new Date(now.getFullYear() + 1, 4, 31);
}

export function RappelsFiscaux({ regimeFiscal = 'MICRO_BNC', regimeFiscalConfirme = false }: RappelsFiscauxProps) {
  const navigate = useNavigate();
  const microBnc = (regimeFiscal ?? 'MICRO_BNC') === 'MICRO_BNC';

  const echeances = useMemo(() => {
    const dateImpot = microBnc ? getEcheance2042CPro() : getEcheance2035();
    const anneeRevenus = dateImpot.getFullYear() - 1;
    return [
      {
        label: 'URSSAF — déclaration trimestrielle',
        date: getProchainTrimestreURSSAF(),
        approx: false,
        icon: '🏛️',
      },
      {
        label: 'CARPIMKO — cotisation annuelle',
        date: getEcheanceCARPIMKO(),
        approx: false,
        icon: '🛡️',
      },
      microBnc
        ? {
            label: `Déclaration de tes revenus ${anneeRevenus} (formulaire 2042-C-PRO)`,
            date: dateImpot,
            approx: true,
            icon: '📋',
          }
        : {
            label: `Déclaration de tes revenus ${anneeRevenus} (formulaire 2035)`,
            date: dateImpot,
            approx: false,
            icon: '📋',
          },
    ];
  }, [microBnc]);

  return (
    <div className="card-base mb-6 cursor-pointer hover:shadow-md transition-all" onClick={() => navigate('/soignant/charges')}>
      <div className="flex items-center justify-between gap-2 mb-3">
        <div className="flex items-center gap-2 min-w-0">
          <Calendar className="h-5 w-5 text-primary shrink-0" />
          <h3 className="font-semibold text-foreground">📅 Prochaines échéances fiscales</h3>
        </div>
        {/* Régime affiché en clair ; « à confirmer » tant que la question n'a pas
            été posée — le clic sur la carte mène à Mes charges où elle se règle. */}
        <span className={`shrink-0 text-[10px] font-medium px-2 py-0.5 rounded-full ${
          regimeFiscalConfirme ? 'bg-muted text-muted-foreground' : 'bg-warning/10 text-warning'
        }`}>
          {microBnc ? 'Micro-BNC' : 'Déclaration contrôlée'}{regimeFiscalConfirme ? '' : ' · à confirmer'}
        </span>
      </div>
      <div className="space-y-2">
        {echeances.map(e => {
          const jours = differenceInDays(e.date, new Date());
          const color = jours <= 14 ? 'text-destructive' : jours <= 30 ? 'text-warning' : 'text-muted-foreground';
          return (
            <div key={e.label} className="flex items-center justify-between gap-3 py-1.5 border-b border-border/50 last:border-0">
              <div className="flex items-center gap-2 min-w-0">
                <span className="shrink-0">{e.icon}</span>
                <span className="text-sm text-foreground">{e.label}</span>
              </div>
              <div className="text-right shrink-0">
                <p className="text-xs font-medium text-foreground">
                  {e.approx ? '≈ ' : ''}{format(e.date, 'd MMM yyyy', { locale: fr })}
                </p>
                <p className={`text-[10px] ${color}`}>
                  {jours <= 0 ? 'Échue' : `dans ${jours}j`}
                </p>
              </div>
            </div>
          );
        })}
      </div>
      <p className="text-xs text-primary mt-2 text-center">Voir mes charges détaillées →</p>
    </div>
  );
}
