import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Copy, RefreshCw } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getChorusStatutBadge } from '@/lib/chorus-helpers';
import { toast } from 'sonner';

interface Submission {
  id: string;
  invoice_id: string;
  piste_request_id: string | null;
  payload_xml: string | null;
  response_raw: any;
  submission_type: string | null;
  type_document: string | null;
  status: string;
  error_code: string | null;
  error_message: string | null;
  submitted_at: string | null;
  last_checked_at: string | null;
  created_at: string;
  avoir_reference_invoice: string | null;
  facture?: {
    numero_facture: string;
    montant_ttc: number;
    soignant?: { prenom: string; nom: string } | null;
    etablissement?: { nom: string } | null;
  } | null;
}

interface Props {
  submission: Submission | null;
  open: boolean;
  onClose: () => void;
  onResubmit?: (factureId: string) => void;
  resubmitLoading?: boolean;
}

function fmtDate(d: string | null | undefined): string {
  if (!d) return '—';
  try { return format(new Date(d), "d MMM yyyy 'à' HH:mm", { locale: fr }); } catch { return d; }
}

export function ChorusSubmissionDetailDialog({ submission, open, onClose, onResubmit, resubmitLoading }: Props) {
  const [showPayload, setShowPayload] = useState(false);
  const [showResponse, setShowResponse] = useState(false);

  if (!submission) return null;

  const badge = getChorusStatutBadge(submission.status);
  const canResubmit = ['error', 'rejected'].includes(submission.status);

  const copyJson = () => {
    navigator.clipboard.writeText(JSON.stringify(submission.response_raw ?? {}, null, 2));
    toast.success('JSON copié');
  };

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            Soumission Chorus Pro
            <span className={`badge-base text-xs ${badge.classes}`}>{badge.label}</span>
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4 text-sm">
          <section>
            <h3 className="font-semibold text-foreground mb-2">Facture</h3>
            <div className="grid grid-cols-2 gap-2 text-muted-foreground">
              <div><strong>Numéro :</strong> {submission.facture?.numero_facture ?? submission.invoice_id.slice(0, 8)}</div>
              <div><strong>Montant TTC :</strong> {submission.facture?.montant_ttc ? `${submission.facture.montant_ttc} €` : '—'}</div>
              <div><strong>Soignant :</strong> {submission.facture?.soignant ? `${submission.facture.soignant.prenom} ${submission.facture.soignant.nom}` : '—'}</div>
              <div><strong>Établissement :</strong> {submission.facture?.etablissement?.nom ?? '—'}</div>
              <div><strong>Type :</strong> {submission.type_document ?? '—'}</div>
              {submission.avoir_reference_invoice && (
                <div><strong>Réf. avoir :</strong> {submission.avoir_reference_invoice}</div>
              )}
            </div>
          </section>

          <section>
            <h3 className="font-semibold text-foreground mb-2">Chronologie</h3>
            <div className="grid grid-cols-2 gap-2 text-muted-foreground">
              <div><strong>Créée :</strong> {fmtDate(submission.created_at)}</div>
              <div><strong>Soumise :</strong> {fmtDate(submission.submitted_at)}</div>
              <div><strong>Dernière sync :</strong> {fmtDate(submission.last_checked_at)}</div>
              <div><strong>Type dépôt :</strong> {submission.submission_type ?? '—'}</div>
            </div>
            {submission.piste_request_id && (
              <p className="mt-2"><strong>PISTE request ID :</strong> <code className="text-xs">{submission.piste_request_id}</code></p>
            )}
          </section>

          {(submission.error_code || submission.error_message) && (
            <section className="bg-destructive/5 border border-destructive/30 rounded-lg p-3">
              <h3 className="font-semibold text-destructive mb-2">Erreur</h3>
              {submission.error_code && <p><strong>Code :</strong> {submission.error_code}</p>}
              {submission.error_message && <p className="text-sm whitespace-pre-wrap">{submission.error_message}</p>}
            </section>
          )}

          {submission.payload_xml && (
            <section>
              <button onClick={() => setShowPayload(!showPayload)} className="text-sm font-semibold text-primary hover:underline">
                {showPayload ? '▼' : '▶'} Payload XML ({submission.payload_xml.length} chars)
              </button>
              {showPayload && (
                <pre className="mt-2 text-xs bg-muted p-3 rounded overflow-x-auto max-h-64">{submission.payload_xml}</pre>
              )}
            </section>
          )}

          {submission.response_raw && (
            <section>
              <div className="flex items-center justify-between">
                <button onClick={() => setShowResponse(!showResponse)} className="text-sm font-semibold text-primary hover:underline">
                  {showResponse ? '▼' : '▶'} Response PISTE
                </button>
                <Button variant="ghost" size="sm" onClick={copyJson}>
                  <Copy className="h-3.5 w-3.5 mr-1" /> Copier JSON
                </Button>
              </div>
              {showResponse && (
                <pre className="mt-2 text-xs bg-muted p-3 rounded overflow-x-auto max-h-64">
                  {JSON.stringify(submission.response_raw, null, 2)}
                </pre>
              )}
            </section>
          )}
        </div>

        <div className="flex justify-end gap-2 mt-4 pt-4 border-t">
          {canResubmit && onResubmit && (
            <Button onClick={() => onResubmit(submission.invoice_id)} disabled={resubmitLoading} variant="default">
              <RefreshCw className={`h-4 w-4 mr-1 ${resubmitLoading ? 'animate-spin' : ''}`} />
              Resubmit
            </Button>
          )}
          <Button variant="outline" onClick={onClose}>Fermer</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
