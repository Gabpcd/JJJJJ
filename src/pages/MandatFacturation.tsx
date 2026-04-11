import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, CheckCircle, ShieldCheck, Loader2, ArrowLeft, ExternalLink } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  MANDAT_FACTURATION_VERSION,
  MANDAT_FACTURATION_TEXTE,
  hashMandatTexte,
} from '@/constantes/mandatFacturation';

// Conversion markdown-like basique pour affichage
function renderMarkdown(texte: string) {
  const lines = texte.split('\n');
  const elements: JSX.Element[] = [];
  let listBuffer: string[] = [];
  let key = 0;

  const flushList = () => {
    if (listBuffer.length > 0) {
      elements.push(
        <ol key={key++} className="list-decimal list-inside space-y-1.5 text-sm text-foreground ml-2 mb-3">
          {listBuffer.map((item, i) => (
            <li key={i} dangerouslySetInnerHTML={{ __html: item.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/[<>]/g, m => m === '<' ? '&lt;' : '&gt;') }} />
          ))}
        </ol>,
      );
      listBuffer = [];
    }
  };

  for (const line of lines) {
    if (line.startsWith('# ')) {
      flushList();
      elements.push(<h1 key={key++} className="text-xl font-bold text-foreground mb-3 mt-2">{line.substring(2)}</h1>);
    } else if (line.startsWith('## ')) {
      flushList();
      elements.push(<h2 key={key++} className="text-base font-bold text-foreground mt-5 mb-2">{line.substring(3)}</h2>);
    } else if (line.match(/^\d+\.\s/)) {
      listBuffer.push(line.replace(/^\d+\.\s/, ''));
    } else if (line.trim() === '---') {
      flushList();
      elements.push(<hr key={key++} className="border-border my-4" />);
    } else if (line.trim() === '') {
      flushList();
    } else {
      flushList();
      elements.push(
        <p key={key++} className="text-sm text-foreground mb-2 leading-relaxed"
           dangerouslySetInnerHTML={{ __html: line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />
      );
    }
  }
  flushList();
  return elements;
}

export default function MandatFacturation() {
  usePageTitle('Mandat de facturation');
  const navigate = useNavigate();
  const { user } = useAuth();

  const [loading, setLoading] = useState(true);
  const [signing, setSigning] = useState(false);
  const [accepted, setAccepted] = useState(false);
  const [alreadySigned, setAlreadySigned] = useState(false);
  const [signatureDate, setSignatureDate] = useState<string | null>(null);
  const [signatureVersion, setSignatureVersion] = useState<string | null>(null);
  const [hasScrolledToBottom, setHasScrolledToBottom] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase
        .from('soignants')
        .select('mandat_facturation_signe, mandat_facturation_signe_le, mandat_facturation_version')
        .eq('id', user.id)
        .maybeSingle();
      if (data?.mandat_facturation_signe) {
        setAlreadySigned(true);
        setSignatureDate(data.mandat_facturation_signe_le);
        setSignatureVersion(data.mandat_facturation_version);
      }
      setLoading(false);
    })();
  }, [user]);

  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 50) {
      setHasScrolledToBottom(true);
    }
  };

  const signer = async () => {
    if (!accepted) {
      toast.error('Vous devez accepter le mandat pour continuer');
      return;
    }
    setSigning(true);
    try {
      const hash = await hashMandatTexte(MANDAT_FACTURATION_TEXTE);
      const { data, error } = await supabase.rpc('fn_signer_mandat_facturation' as any, {
        p_version: MANDAT_FACTURATION_VERSION,
        p_ip: null, // L'IP est capturée côté serveur si besoin via un edge trigger
        p_user_agent: navigator.userAgent,
        p_contenu_hash: hash,
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);

      toast.success('Mandat signé avec succès');
      setAlreadySigned(true);
      setSignatureDate(new Date().toISOString());
      setSignatureVersion(MANDAT_FACTURATION_VERSION);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la signature');
    } finally {
      setSigning(false);
    }
  };

  if (loading) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <FileText className="h-5 w-5 text-primary" /> Mandat de facturation
            </h1>
            <p className="text-xs text-muted-foreground">Version {MANDAT_FACTURATION_VERSION} — Article 289 I-2 CGI</p>
          </div>
        </div>

        {alreadySigned && (
          <div className="rounded-xl border-2 border-success/30 bg-success/5 p-4 flex items-start gap-3">
            <CheckCircle className="h-6 w-6 text-success shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat signé et actif</p>
              <p className="text-sm text-muted-foreground mt-0.5">
                Vous avez accepté le mandat de facturation version {signatureVersion} le{' '}
                {signatureDate && format(new Date(signatureDate), "dd MMMM yyyy 'à' HH:mm", { locale: fr })}.
              </p>
              <p className="text-xs text-muted-foreground mt-2">
                Jolene peut désormais émettre des factures d'honoraires en votre nom à chaque mission terminée.
                Vous pouvez retirer votre consentement à tout moment en contactant le support, avec un préavis de 30 jours.
              </p>
            </div>
          </div>
        )}

        {!alreadySigned && (
          <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4">
            <div className="flex items-start gap-3">
              <ShieldCheck className="h-6 w-6 text-primary shrink-0 mt-0.5" />
              <div className="flex-1 space-y-2">
                <p className="font-semibold text-foreground">Pourquoi signer ce mandat ?</p>
                <ul className="text-sm text-muted-foreground space-y-1 ml-4 list-disc">
                  <li>Jolene pourra produire et envoyer vos factures d'honoraires automatiquement à chaque mission terminée</li>
                  <li>Vos factures sont conservées centralement et accessibles à tout moment</li>
                  <li>Préparation au paiement rapide (avance sous 48h) — disponible prochainement</li>
                  <li>Vous restez libéral indépendant : aucun lien de subordination, aucun changement de statut</li>
                </ul>
              </div>
            </div>
          </div>
        )}

        <div className="card-base p-0 overflow-hidden">
          <div
            className="max-h-[50vh] overflow-y-auto px-5 py-4 border-b border-border"
            onScroll={handleScroll}
          >
            {renderMarkdown(MANDAT_FACTURATION_TEXTE)}
          </div>

          {!alreadySigned && (
            <div className="p-5 space-y-4 bg-muted/20">
              {!hasScrolledToBottom && (
                <p className="text-xs text-muted-foreground italic text-center">
                  Faites défiler le document jusqu'en bas pour l'accepter
                </p>
              )}

              <div className="flex items-start gap-3">
                <Checkbox
                  id="accept-mandat"
                  checked={accepted}
                  onCheckedChange={(v) => setAccepted(v === true)}
                  disabled={!hasScrolledToBottom}
                />
                <label htmlFor="accept-mandat" className="text-sm text-foreground cursor-pointer leading-relaxed">
                  J'ai lu et j'accepte expressément les termes du mandat de facturation ci-dessus. Je confirme donner mandat à Jolene
                  d'émettre des factures en mon nom et pour mon compte, conformément à l'article 289 I-2 du CGI.
                </label>
              </div>

              <Button
                onClick={signer}
                disabled={!accepted || signing || !hasScrolledToBottom}
                className="w-full gap-2"
              >
                {signing ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle className="h-4 w-4" />}
                Signer électroniquement le mandat
              </Button>

              <p className="text-[10px] text-muted-foreground text-center">
                Votre signature sera horodatée et archivée comme preuve légale (Articles 1366 et 1367 du Code civil).
              </p>
            </div>
          )}
        </div>
      </div>
    </LayoutApp>
  );
}
