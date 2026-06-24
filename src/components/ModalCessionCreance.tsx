import { useState } from 'react';
import { ShieldCheck, X, Zap } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Checkbox } from '@/components/ui/checkbox';
import { supabase } from '@/integrations/supabase/client';
import { messageErreurEdgeFn } from '@/lib/erreurs';
import { toast } from 'sonner';
import {
  CESSION_CREANCE_VERSION,
  CESSION_CREANCE_TEXTE,
  hashCessionTexte,
} from '@/constantes/cessionCreance';

interface Props {
  open: boolean;
  onClose: () => void;
  factureId: string;
  numeroFacture: string;
  montant: number;
  onSuccess: () => void;
}

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

function renderMarkdown(texte: string) {
  const lines = texte.split('\n');
  const elements: JSX.Element[] = [];
  let listBuffer: string[] = [];
  let key = 0;

  const flushList = () => {
    if (listBuffer.length > 0) {
      elements.push(
        <ol key={key++} className="list-decimal list-inside space-y-1 text-xs text-foreground ml-2 mb-2">
          {listBuffer.map((item, i) => (
            <li key={i} dangerouslySetInnerHTML={{ __html: item.replace(/[<>]/g, m => m === '<' ? '&lt;' : '&gt;').replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />
          ))}
        </ol>,
      );
      listBuffer = [];
    }
  };

  for (const line of lines) {
    if (line.startsWith('# ')) {
      flushList();
      elements.push(<h1 key={key++} className="text-lg font-bold text-foreground mb-2 mt-1">{line.substring(2)}</h1>);
    } else if (line.startsWith('## ')) {
      flushList();
      elements.push(<h2 key={key++} className="text-sm font-bold text-foreground mt-3 mb-1.5">{line.substring(3)}</h2>);
    } else if (line.match(/^-\s/)) {
      flushList();
      elements.push(<p key={key++} className="text-xs text-foreground ml-3 mb-1"
        dangerouslySetInnerHTML={{ __html: '• ' + line.substring(2).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />);
    } else if (line.match(/^\d+\.\s/)) {
      listBuffer.push(line.replace(/^\d+\.\s/, ''));
    } else if (line.trim() === '---') {
      flushList();
      elements.push(<hr key={key++} className="border-border my-3" />);
    } else if (line.trim() === '') {
      flushList();
    } else {
      flushList();
      elements.push(
        <p key={key++} className="text-xs text-foreground mb-1.5 leading-relaxed"
          dangerouslySetInnerHTML={{ __html: line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />
      );
    }
  }
  flushList();
  return elements;
}

export function ModalCessionCreance({ open, onClose, factureId, numeroFacture, montant, onSuccess }: Props) {
  const [accepted, setAccepted] = useState(false);
  const [hasScrolledToBottom, setHasScrolledToBottom] = useState(false);
  const [signing, setSigning] = useState(false);

  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 40) {
      setHasScrolledToBottom(true);
    }
  };

  const signerEtDemander = async () => {
    if (!accepted) {
      toast.error('Vous devez accepter la cession pour continuer');
      return;
    }
    setSigning(true);
    try {
      // 1. Signer la cession de créance
      const hash = await hashCessionTexte(CESSION_CREANCE_TEXTE);
      const { data: cessionData, error: cessionErr } = await supabase.rpc('fn_signer_cession_creance' as any, {
        p_facture_honoraire_id: factureId,
        p_version: CESSION_CREANCE_VERSION,
        p_ip: null,
        p_user_agent: navigator.userAgent,
        p_contenu_hash: hash,
      });
      if (cessionErr) throw cessionErr;
      if ((cessionData as any)?.error) throw new Error((cessionData as any).error);

      // 2. Demander l'avance auprès du factor
      const { data, error } = await supabase.functions.invoke('factor-request-advance', {
        body: { facture_honoraire_id: factureId },
      });
      if (error) {
        const msg = await messageErreurEdgeFn(error, 'Erreur lors de la demande d\'affacturage.');
        toast.error(msg);
        return;
      }
      if (data?.configured === false) {
        toast.success('Cession signée. La demande d\'affacturage sera traitée dès activation Defacto.');
      } else if (data?.success) {
        toast.success(data.message || 'Cession signée et avance demandée');
      } else {
        toast.error(data?.message || 'Demande refusée par le factor');
      }
      onSuccess();
      onClose();
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la signature');
    } finally {
      setSigning(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-[calc(100%-1rem)] sm:max-w-2xl max-h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Zap className="h-5 w-5 text-primary" />
            Demande de paiement rapide
          </DialogTitle>
        </DialogHeader>

        {/* Récap facture */}
        <div className="rounded-lg bg-primary/5 border border-primary/20 p-3 space-y-1">
          <p className="text-xs text-muted-foreground">Facture concernée</p>
          <div className="flex items-center justify-between">
            <span className="font-mono text-sm font-bold text-foreground">{numeroFacture}</span>
            <span className="text-lg font-bold text-foreground">{fmt(montant)}</span>
          </div>
          <p className="text-[10px] text-muted-foreground">
            En signant la cession ci-dessous, vous transférez la propriété de cette créance à Jolene,
            qui pourra alors la vendre à l'affactureur partenaire pour vous verser le montant net sous 24-48h.
          </p>
        </div>

        {/* Texte légal scrollable */}
        <div
          className="flex-1 overflow-y-auto border border-border rounded-lg px-4 py-3 bg-background"
          onScroll={handleScroll}
        >
          {renderMarkdown(CESSION_CREANCE_TEXTE)}
        </div>

        {/* Acceptation */}
        <div className="space-y-3">
          {!hasScrolledToBottom && (
            <p className="text-xs text-muted-foreground italic text-center">
              Faites défiler le document jusqu'en bas pour pouvoir l'accepter
            </p>
          )}

          <div className="flex items-start gap-3">
            <Checkbox
              id="accept-cession"
              checked={accepted}
              onCheckedChange={(v) => setAccepted(v === true)}
              disabled={!hasScrolledToBottom}
            />
            <label htmlFor="accept-cession" className="text-xs text-foreground cursor-pointer leading-relaxed">
              J'accepte de céder à Jolene la créance correspondant à la facture {numeroFacture}
              pour un montant de {fmt(montant)}, et j'autorise Jolene à la vendre à un affactureur partenaire
              afin de recevoir le montant net sous 24-48h.
            </label>
          </div>

          <div className="flex gap-2">
            <BoutonY2K variant="ghost" onClick={onClose} disabled={signing}>
              Annuler
            </BoutonY2K>
            <BoutonY2K
              onClick={signerEtDemander}
              disabled={!accepted || signing || !hasScrolledToBottom}
              loading={signing}
              className="flex-1 gap-2"
              iconeGauche={signing ? undefined : <ShieldCheck className="h-4 w-4" />}
            >
              Signer et demander l'avance
            </BoutonY2K>
          </div>

          <p className="text-[10px] text-muted-foreground text-center">
            Signature horodatée et archivée comme preuve légale (Articles 1366 et 1367 du Code civil).
          </p>
        </div>
      </DialogContent>
    </Dialog>
  );
}
