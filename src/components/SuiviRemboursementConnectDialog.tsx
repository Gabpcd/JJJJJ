import { useEffect, useState } from 'react';
import { AlertTriangle, CheckCircle, Clock, Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import {
  DialogResponsive, DialogResponsiveContent, DialogResponsiveHeader,
  DialogResponsiveTitle, DialogResponsiveDescription, DialogResponsiveBody, DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import {
  etatRetourConnect, lireSuiviRemboursementConnect, presentationRemboursementConnect,
  type SuiviRemboursementConnect,
} from '@/lib/suiviRemboursementConnect';

type Props = { factureId: string; numeroFacture?: string; checkoutSessionId?: string; onClose: () => void };
type Lecture = { cle: string; statut: 'chargement' | 'erreur' | 'ok'; suivi?: SuiviRemboursementConnect };
const euros = (centimes: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(centimes / 100);
const date = (valeur: string) => new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(valeur));

export function SuiviRemboursementConnectDialog({ factureId, numeroFacture, checkoutSessionId, onClose }: Props) {
  const { user } = useAuth();
  const [tentative, setTentative] = useState(0);
  const cle = `${user?.id ?? ''}:${factureId}:${checkoutSessionId ?? ''}:${tentative}`;
  const [lecture, setLecture] = useState<Lecture>({ cle: '', statut: 'chargement' });
  const statut = lecture.cle === cle ? lecture.statut : 'chargement';
  const suivi = statut === 'ok' ? lecture.suivi : undefined;

  useEffect(() => {
    if (!user?.id) { setLecture({ cle, statut: 'erreur' }); return; }
    let actif = true;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    setLecture({ cle, statut: 'chargement' });
    void lireSuiviRemboursementConnect(factureId, checkoutSessionId, controller.signal)
      .then(resultat => { if (actif) setLecture({ cle, statut: 'ok', suivi: resultat }); })
      .catch(() => { if (actif) setLecture({ cle, statut: 'erreur' }); })
      .finally(() => clearTimeout(timeout));
    return () => { actif = false; clearTimeout(timeout); controller.abort(); };
  }, [cle, factureId, checkoutSessionId, user?.id]);

  return (
    <DialogResponsive open onOpenChange={open => { if (!open) onClose(); }}>
      <DialogResponsiveContent maxWidth="lg">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Suivi du paiement par carte</DialogResponsiveTitle>
          <DialogResponsiveDescription>
            {numeroFacture ? `Facture ${numeroFacture}. ` : ''}Consultez le paiement de l’établissement et son éventuel remboursement.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          {statut === 'chargement' && <p role="status" className="flex items-center gap-2 text-sm"><Loader2 className="h-4 w-4 animate-spin" /> Vérification du suivi…</p>}
          {statut === 'erreur' && <div role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm">
            <p>Impossible de vérifier le suivi pour le moment. Aucun paiement ni remboursement n’est confirmé par cet écran.</p>
            <button type="button" className="btn-secondary mt-3 min-h-[44px]" onClick={() => setTentative(n => n + 1)}>Réessayer le suivi</button>
          </div>}
          {suivi && <>
            {suivi.operations.length === 0 && <div className="rounded-xl border border-border bg-muted/20 p-4 text-sm">
              <p className="font-semibold">Aucun remboursement enregistré dans ce suivi.</p>
              {checkoutSessionId && <p className="mt-2">{
                etatRetourConnect(suivi) === 'CONFIRME' ? 'Le paiement de cette session est confirmé et enregistré.'
                  : etatRetourConnect(suivi) === 'EN_ATTENTE' ? 'La confirmation de ce paiement est encore en attente.'
                    : 'La situation de ce paiement nécessite une vérification. Ne recommencez pas le paiement sur la seule base de cet écran.'
              }</p>}
            </div>}
            {suivi.operations.map(op => {
              const presentation = presentationRemboursementConnect(op);
              const Icon = presentation.ton === 'succes' ? CheckCircle : presentation.ton === 'incident' ? AlertTriangle : Clock;
              const couleur = presentation.ton === 'succes' ? 'border-success/30 bg-success/5' : presentation.ton === 'incident' ? 'border-warning/40 bg-warning/5' : 'border-border bg-muted/20';
              return <article key={op.id} className={`space-y-3 rounded-xl border p-4 ${couleur}`}>
                <h3 className="flex items-center gap-2 font-semibold"><Icon className="h-5 w-5 shrink-0" />{presentation.titre}</h3>
                <p className="text-sm">{presentation.detail}</p>
                <dl className="space-y-2 text-sm">
                  <div className="flex flex-wrap justify-between gap-x-4 gap-y-1"><dt>Honoraires concernés</dt><dd className="font-semibold tabular-nums">{euros(op.montant_honoraires_centimes)}</dd></div>
                  {suivi.visibilite_montants === 'TOTAL_ETABLISSEMENT' && <>
                    <div className="flex flex-wrap justify-between gap-x-4 gap-y-1"><dt>Commission concernée</dt><dd className="font-semibold tabular-nums">{euros(op.montant_commission_centimes!)}</dd></div>
                    <div className="flex flex-wrap justify-between gap-x-4 gap-y-1 border-t border-border pt-2"><dt>Montant du remboursement</dt><dd className="font-semibold tabular-nums">{euros(op.montant_total_centimes!)}</dd></div>
                  </>}
                  <div className="flex flex-wrap justify-between gap-x-4 gap-y-1"><dt>Suivi créé le</dt><dd>{date(op.cree_le)}</dd></div>
                  {op.statut === 'SUCCEEDED' && op.succeeded_at && <div className="flex flex-wrap justify-between gap-x-4 gap-y-1"><dt>Confirmation reçue le</dt><dd>{date(op.succeeded_at)}</dd></div>}
                </dl>
              </article>;
            })}
            <p className="text-xs text-muted-foreground">Les virements et autres modes de règlement ne figurent pas dans ce suivi. Actualiser cette page ne déclenche aucune opération financière.</p>
          </>}
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          {statut === 'ok' && <button type="button" className="btn-secondary min-h-[44px]" onClick={() => setTentative(n => n + 1)}>Actualiser le suivi</button>}
          <button type="button" className="btn-primary min-h-[44px]" onClick={onClose}>Fermer le suivi</button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}
