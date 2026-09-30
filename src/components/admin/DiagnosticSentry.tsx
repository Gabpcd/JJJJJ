import { useState } from 'react';
import * as Sentry from '@sentry/react';
import { Bug } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { etatDiagnosticSentry } from '@/lib/diagnosticSentry';

export function DiagnosticSentry() {
  const [resultat, setResultat] = useState<string | null>(null);
  const etat = etatDiagnosticSentry();

  function tester() {
    // Recontrôler au clic : le SDK peut avoir été désactivé depuis le rendu.
    const actuel = etatDiagnosticSentry();
    if (!actuel.disponible) { setResultat(actuel.detail); return; }
    try {
      const reference = Sentry.captureException(new Error('Sentry test event from /admin/status'), {
        tags: { test: 'true', source: 'admin-diagnostic' }, level: 'info',
      });
      const suffixe = /^[a-f0-9]{32}$/i.test(reference) ? ` Référence : ${reference}.` : '';
      setResultat(`Tentative d’envoi effectuée. La réception reste à confirmer dans Sentry.${suffixe}`);
    } catch {
      // Une exception du SDK peut contenir sa configuration : ne pas l'afficher.
      setResultat('Le diagnostic Sentry a échoué. Aucun envoi confirmé.');
    }
  }

  return (
    <section aria-label="Diagnostic Sentry" className="space-y-3">
      <p className="text-xs text-muted-foreground">
        Crée un événement de test. Retrouvez-le dans Sentry pour vérifier sa réception,
        sa version et la lisibilité de la trace. Ce bouton ne confirme pas ces vérifications.
      </p>
      <p className="text-xs">{etat.detail}</p>
      <BoutonY2K
        size="sm" variant="secondary" disabled={!etat.disponible}
        iconeGauche={<Bug className="h-3.5 w-3.5" />} onClick={tester}
      >
        Tester Sentry
      </BoutonY2K>
      <p role="status" className="text-xs break-words">{resultat}</p>
    </section>
  );
}
