import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import type { DocumentApercuPdf } from '@/lib/apercuPdfCopie';

interface Props { file: File; onPretChange: (pret: boolean) => void; }

export function ApercuPdfCopie({ file, onPretChange }: Props) {
  const conteneur = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const [document, setDocument] = useState<DocumentApercuPdf | null>(null);
  const [page, setPage] = useState(1);
  const [largeur, setLargeur] = useState(0);
  const [revision, setRevision] = useState(0);
  const [chargement, setChargement] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);

  useEffect(() => {
    const element = conteneur.current;
    if (!element) return;
    const mesurer = () => setLargeur(Math.floor(element.getBoundingClientRect().width));
    mesurer();
    const observer = new ResizeObserver(mesurer); observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const controleur = new AbortController();
    let charge: DocumentApercuPdf | null = null;
    setDocument(null); setPage(1); setErreur(null); setChargement(true); onPretChange(false);
    // The renderer and its worker are only imported for this official preview.
    void import('@/lib/apercuPdfCopie').then(module => module.chargerApercuPdf(file, controleur.signal))
      .then(resultat => { charge = resultat; if (controleur.signal.aborted) resultat.detruire(); else setDocument(resultat); })
      .catch(() => { if (!controleur.signal.aborted) { setChargement(false); setErreur('L’aperçu du PDF est indisponible. Réessayez ou choisissez un PDF lisible et non protégé par mot de passe.'); } });
    return () => { controleur.abort(); charge?.detruire(); onPretChange(false); };
  }, [file, revision, onPretChange]);

  useEffect(() => {
    const element = canvas.current;
    if (!document || !element || largeur <= 0) return;
    const controleur = new AbortController();
    setChargement(true); setErreur(null); onPretChange(false);
    void document.rendrePage(page, element, largeur, window.devicePixelRatio, controleur.signal)
      .then(() => { if (!controleur.signal.aborted) { setChargement(false); onPretChange(true); } })
      .catch(() => { if (!controleur.signal.aborted) { setChargement(false); setErreur('Cette page ne peut pas être affichée. Réessayez l’aperçu ou choisissez un autre PDF.'); } });
    return () => { controleur.abort(); onPretChange(false); };
  }, [document, page, largeur, onPretChange]);

  useEffect(() => { const element = canvas.current; return () => { if (element) { element.width = 0; element.height = 0; } }; }, []);

  function changerPage(numero: number) { onPretChange(false); setChargement(true); setPage(numero); }

  return <section aria-label="Aperçu de la copie du bulletin officiel" className="space-y-3">
    <div className="flex flex-wrap items-center justify-between gap-2">
      <Button variant="outline" size="sm" disabled={!document || page <= 1 || chargement || Boolean(erreur)} onClick={() => changerPage(page - 1)}>Page précédente</Button>
      <p aria-live="polite" data-testid="apercu-pdf-pagination" className="text-sm font-medium">{document ? `Page ${page} sur ${document.nombrePages}` : 'Chargement du PDF…'}</p>
      <Button variant="outline" size="sm" disabled={!document || page >= document.nombrePages || chargement || Boolean(erreur)} onClick={() => changerPage(page + 1)}>Page suivante</Button>
    </div>
    {chargement && <p role="status" className="text-sm">Affichage de l’aperçu…</p>}
    {erreur && <div role="alert" className="space-y-2 text-sm text-destructive"><p>{erreur}</p><Button variant="outline" onClick={() => { onPretChange(false); setRevision(v => v + 1); }}>Réessayer l’aperçu</Button></div>}
    <div ref={conteneur} className="w-full overflow-hidden rounded-lg border bg-muted/30">
      <canvas ref={canvas} role="img" aria-label={`Aperçu du PDF, page ${page}`} data-testid="apercu-pdf-canvas" data-ready={!chargement && !erreur && Boolean(document)} className={`mx-auto max-w-full ${chargement || erreur ? 'hidden' : 'block'}`} />
    </div>
    <p className="text-xs text-muted-foreground">Vérifiez le destinataire et la période dans le PDF. Parcourez les pages du document avant de confirmer.</p>
  </section>;
}
