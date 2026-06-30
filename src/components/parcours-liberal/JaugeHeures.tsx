import { Sparkles } from 'lucide-react';

interface Props {
  heuresJolene: number;
  heuresExternesValidees: number;
  heuresExternesEnAttente: number;
  seuilRequis: number;
  eligibleFreeTransition?: boolean;
  titre?: string;
  legendeJolene?: string;
  legendeExternes?: string;
  /** Date de démarrage du parcours — active la projection « libéral vers {mois} ». */
  demarreLe?: string | null;
}

const HACHURES_BG = 'repeating-linear-gradient(45deg, #fb923c, #fb923c 5px, #fed7aa 5px, #fed7aa 10px)';

export function JaugeHeures({
  heuresJolene,
  heuresExternesValidees,
  heuresExternesEnAttente,
  seuilRequis,
  eligibleFreeTransition,
  titre,
  legendeJolene = 'Heures via Jolene',
  legendeExternes = 'Heures externes validées',
  demarreLe,
}: Props) {
  const total = heuresJolene + heuresExternesValidees;
  const totalAvecAttente = total + heuresExternesEnAttente;
  const pctCapped = Math.min(100, (total / seuilRequis) * 100);
  const pctJolene = Math.min(100, (heuresJolene / seuilRequis) * 100);
  const pctValidees = Math.min(100 - pctJolene, (heuresExternesValidees / seuilRequis) * 100);
  const pctAttente = Math.min(100 - pctJolene - pctValidees, (heuresExternesEnAttente / seuilRequis) * 100);

  const atteint = total >= seuilRequis;
  const atteintViaExternes = atteint && !eligibleFreeTransition;
  const restant = Math.max(0, seuilRequis - totalAvecAttente);

  // Projection motivationnelle : au rythme moyen constaté depuis le début du
  // parcours, date estimée d'atteinte du seuil. Affichée seulement si le rythme
  // est mesurable (≥ 2 semaines de recul et ≥ 20h cumulées).
  let projection: string | null = null;
  if (!atteint && demarreLe && total >= 20) {
    const moisEcoules = (Date.now() - new Date(demarreLe).getTime()) / (30.44 * 86400000);
    if (moisEcoules >= 0.5) {
      const rythme = total / moisEcoules;
      if (rythme >= 5) {
        const dateCible = new Date(Date.now() + ((seuilRequis - total) / rythme) * 30.44 * 86400000);
        projection = `📅 À ce rythme (~${Math.round(rythme)}h/mois), objectif atteint vers ${dateCible.toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })}. Ajoute tes heures externes pour avancer la date.`;
      }
    }
  }

  return (
    <div className="card-base">
      {titre && <h3 className="text-base font-bold text-foreground mb-3">{titre}</h3>}

      <div className="flex items-baseline justify-between gap-2 mb-2 flex-wrap">
        <span className="text-lg font-bold text-foreground">
          {total.toLocaleString('fr-FR')}h <span className="text-sm font-normal text-muted-foreground">/ {seuilRequis.toLocaleString('fr-FR')}h</span>
        </span>
        <span className={`text-sm font-semibold ${atteint ? 'text-success' : 'text-primary'}`}>
          {Math.round(pctCapped)}%
        </span>
      </div>

      {projection && (
        <p className="text-xs text-primary font-medium mb-2">{projection}</p>
      )}

      <div className="h-3 w-full rounded-full bg-muted overflow-hidden flex">
        <div className="h-full bg-primary transition-all duration-500" style={{ width: `${pctJolene}%` }} aria-label={legendeJolene} />
        <div className="h-full bg-info transition-all duration-500" style={{ width: `${pctValidees}%` }} aria-label={legendeExternes} />
        <div className="h-full transition-all duration-500" style={{ width: `${pctAttente}%`, backgroundImage: HACHURES_BG }} aria-label="Heures externes en attente" />
      </div>

      <div className="flex flex-wrap gap-x-4 gap-y-1.5 mt-3 text-xs text-muted-foreground">
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm bg-primary" /> {legendeJolene} : <strong className="text-foreground">{heuresJolene}h</strong>
        </span>
        {heuresExternesValidees > 0 && (
          <span className="flex items-center gap-1.5">
            <span className="h-3 w-3 rounded-sm bg-info" /> {legendeExternes} : <strong className="text-foreground">{heuresExternesValidees}h</strong>
          </span>
        )}
        {heuresExternesEnAttente > 0 && (
          <span className="flex items-center gap-1.5">
            <span className="h-3 w-3 rounded-sm" style={{ backgroundImage: HACHURES_BG }} /> En attente validation : <strong className="text-foreground">{heuresExternesEnAttente}h</strong>
          </span>
        )}
      </div>

      {eligibleFreeTransition && (
        <div className="mt-4 rounded-xl border-2 border-primary/40 bg-gradient-to-r from-primary/10 to-info/10 p-3 flex items-start gap-2">
          <Sparkles className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-primary">Free Transition RC Pro disponible</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Tes 3 200h sont faites chez Jolene — ta RC Pro est offerte la première année.
            </p>
          </div>
        </div>
      )}

      {atteintViaExternes && (
        <div className="mt-4 rounded-xl border border-border bg-muted/40 p-3">
          <p className="text-sm font-medium text-foreground">Tes {seuilRequis}h sont atteintes, bravo.</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            L'offre Free Transition RC Pro est réservée aux heures réalisées chez Jolene.
          </p>
        </div>
      )}

      {!atteint && restant > 0 && (
        <p className="text-xs text-muted-foreground mt-3">
          Il te reste <strong className="text-foreground">{restant.toLocaleString('fr-FR')}h</strong> à effectuer pour atteindre le seuil.
        </p>
      )}
    </div>
  );
}
