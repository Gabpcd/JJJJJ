import { Calendar, ExternalLink } from 'lucide-react';
import { Link } from 'react-router-dom';
import { REGLES_INSTALLATION_LIBERAL } from '@/lib/regles-installation-liberal';

export type RegimeFiscal = 'MICRO_BNC' | 'DECLARATION_CONTROLEE';

interface RappelsFiscauxProps {
  profession?: string | null;
  regimeFiscal?: RegimeFiscal | null;
  regimeFiscalConfirme?: boolean;
}

// Aucun échéancier individuel n'est synchronisé dans Jolene. Ne pas déduire
// une date, une fréquence ou une urgence du seul régime fiscal/profession.
export function RappelsFiscaux({ profession, regimeFiscal, regimeFiscalConfirme = false }: RappelsFiscauxProps) {
  const installation = profession ? REGLES_INSTALLATION_LIBERAL[profession] : undefined;
  const caisse = installation?.caisse_retraite;
  const lienCaisse = installation?.lien_caisse_retraite;
  const regime = regimeFiscal === 'MICRO_BNC' ? 'Micro-BNC'
    : regimeFiscal === 'DECLARATION_CONTROLEE' ? 'Déclaration contrôlée' : null;
  const organismes = [
    { label: 'URSSAF', href: 'https://www.urssaf.fr/' },
    ...(caisse && lienCaisse ? [{ label: caisse, href: lienCaisse }] : []),
    { label: 'Impôts', href: 'https://www.impots.gouv.fr/accueil' },
  ];

  return (
    <section className="card-base mb-6" aria-label="Mes échéances fiscales et sociales">
      <div className="flex items-center gap-2 mb-2">
        <Calendar className="h-5 w-5 text-primary shrink-0" />
        <h3 className="font-semibold text-foreground">Mes échéances fiscales et sociales</h3>
      </div>
      <p className="text-sm text-muted-foreground mb-3">
        Retrouve tes dates et tes montants à régler dans tes espaces officiels.
      </p>
      <p className="text-xs text-muted-foreground mb-3">
        {regime ? `${regime}${regimeFiscalConfirme ? '' : ' · à confirmer'}` : 'Régime fiscal à renseigner'}
      </p>
      <div className="flex flex-wrap gap-2">
        {organismes.map(({ label, href }) => (
          <a key={label} href={href} target="_blank" rel="noopener noreferrer"
            className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-border px-3 text-sm font-medium text-primary hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            aria-label={`${label} — site officiel (nouvelle fenêtre)`}>
            {label}<ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
          </a>
        ))}
      </div>
      <Link to="/soignant/charges" className="mt-3 inline-flex min-h-11 items-center text-sm font-medium text-primary underline underline-offset-4">
        Mes charges et mon régime fiscal
      </Link>
    </section>
  );
}
