import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, CheckCircle, ShieldCheck, Loader2, ArrowLeft, ExternalLink, Download, AlertTriangle } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Checkbox } from '@/components/ui/checkbox';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { PROFESSIONS } from '@/lib/constantes';
import {
  MANDAT_FACTURATION_VERSION,
  buildMandatFacturationTexte,
  hashMandatTexte,
  type SoignantMandatInfo,
} from '@/constantes/mandatFacturation';
import { telechargerMandatFacturationPdf, type MandatPdfMetadata } from '@/lib/mandat-facturation-pdf';

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
            // eslint-disable-next-line react/no-danger
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

  const [typeExercice, setTypeExercice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [signing, setSigning] = useState(false);
  const [accepted, setAccepted] = useState(false);
  const [alreadySigned, setAlreadySigned] = useState(false);
  const [signatureDate, setSignatureDate] = useState<string | null>(null);
  const [signatureVersion, setSignatureVersion] = useState<string | null>(null);
  const [hasScrolledToBottom, setHasScrolledToBottom] = useState(false);
  const [soignantInfo, setSoignantInfo] = useState<SoignantMandatInfo | null>(null);
  const [signatureMeta, setSignatureMeta] = useState<MandatPdfMetadata | null>(null);
  const [showConfirmRevoke, setShowConfirmRevoke] = useState(false);
  const [revoking, setRevoking] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase
        .from('soignants')
        .select('prenom, nom, email, profession, numero_rpps, numero_adeli, siret_liberal, adresse_rue, adresse_code_postal, adresse_ville, mandat_facturation_signe, mandat_facturation_signe_le, mandat_facturation_version, type_exercice')
        .eq('id', user.id)
        .maybeSingle();
      if (data) {
        setTypeExercice((data as any).type_exercice || null);
        setSoignantInfo({
          prenom: (data as any).prenom,
          nom: (data as any).nom,
          email: (data as any).email,
          profession: (data as any).profession,
          professionLabel: PROFESSIONS.find(p => p.valeur === (data as any).profession)?.label || (data as any).profession,
          numero_rpps: (data as any).numero_rpps,
          numero_adeli: (data as any).numero_adeli,
          siret_liberal: (data as any).siret_liberal,
          adresse_rue: (data as any).adresse_rue,
          adresse_code_postal: (data as any).adresse_code_postal,
          adresse_ville: (data as any).adresse_ville,
        });
        if ((data as any).mandat_facturation_signe) {
          setAlreadySigned(true);
          setSignatureDate((data as any).mandat_facturation_signe_le);
          setSignatureVersion((data as any).mandat_facturation_version);
          // Récupère les métadonnées techniques de la signature pour le PDF
          const { data: sig } = await supabase
            .from('mandats_facturation_signatures' as any)
            .select('signed_at, version, ip_address, user_agent, contenu_hash')
            .eq('soignant_id', user.id)
            .is('revoked_at', null)
            .order('signed_at', { ascending: false })
            .limit(1)
            .maybeSingle();
          if (sig) {
            setSignatureMeta({
              signed_at: (sig as any).signed_at,
              version: (sig as any).version,
              ip_address: (sig as any).ip_address,
              user_agent: (sig as any).user_agent,
              contenu_hash: (sig as any).contenu_hash,
            });
          }
        }
      }
      setLoading(false);
    })();
  }, [user]);

  // Texte du mandat avec les infos du soignant injectées dans la section Parties
  const mandatTexte = useMemo(
    () => buildMandatFacturationTexte(soignantInfo || {}),
    [soignantInfo],
  );

  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 50) {
      setHasScrolledToBottom(true);
    }
  };

  const signer = async () => {
    if (!accepted) {
      toast.error('Tu dois accepter le mandat pour continuer');
      return;
    }
    setSigning(true);
    try {
      const hash = await hashMandatTexte(mandatTexte);
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
      const now = new Date().toISOString();
      setSignatureDate(now);
      setSignatureVersion(MANDAT_FACTURATION_VERSION);
      setSignatureMeta({
        signed_at: now,
        version: MANDAT_FACTURATION_VERSION,
        ip_address: null,
        user_agent: navigator.userAgent,
        contenu_hash: hash,
      });
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la signature');
    } finally {
      setSigning(false);
    }
  };

  const telechargerPdf = () => {
    if (!soignantInfo || !signatureMeta) {
      toast.error('Impossible de générer le PDF : signature introuvable.');
      return;
    }
    try {
      telechargerMandatFacturationPdf(soignantInfo, signatureMeta);
    } catch (err: any) {
      toast.error('Erreur lors de la génération du PDF.');
    }
  };

  const revoquer = async () => {
    setRevoking(true);
    try {
      const { data, error } = await supabase.rpc('fn_revoquer_mandat_facturation' as any, { p_motif: null });
      if (error) throw error;
      if ((data as any)?.success === false) throw new Error((data as any)?.error || 'Erreur révocation');

      toast.success('Mandat révoqué. Aucune facture ne sera plus émise tant que tu ne signes pas un nouveau mandat.');
      setAlreadySigned(false);
      setSignatureDate(null);
      setSignatureVersion(null);
      setSignatureMeta(null);
      setAccepted(false);
      setHasScrolledToBottom(false);
      setShowConfirmRevoke(false);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la révocation');
    } finally {
      setRevoking(false);
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

  // Salarié pur → pas de mandat de facturation (art. 289 I-2 CGI : libéral uniquement)
  if (!loading && typeExercice && typeExercice !== 'LIBERAL' && typeExercice !== 'MIXTE') {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="max-w-lg mx-auto py-12 text-center space-y-4">
          <FileText className="h-12 w-12 text-muted-foreground mx-auto" />
          <h1 className="text-xl font-bold text-foreground">Mandat non applicable</h1>
          <p className="text-sm text-muted-foreground">
            Le mandat de facturation concerne uniquement les soignants exerçant en libéral ou mixte.
            En tant que salarié(e), tes paiements sont gérés par l'établissement employeur.
          </p>
          <Button variant="outline" onClick={() => navigate(-1)}>Retour</Button>
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

        {alreadySigned && signatureVersion && signatureVersion !== MANDAT_FACTURATION_VERSION && (
          <div className="rounded-xl border-2 border-warning/50 bg-warning/10 p-4 flex items-start gap-3">
            <AlertTriangle className="h-6 w-6 text-warning shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat mis à jour — re-signature requise</p>
              <p className="text-sm text-muted-foreground mt-1">
                Ton mandat actuel (version {signatureVersion}) n'est plus à jour.
                La version {MANDAT_FACTURATION_VERSION} intègre la facturation hebdomadaire pour les missions longues.
                Lis et accepte le nouveau mandat ci-dessous pour continuer à recevoir tes factures.
              </p>
            </div>
          </div>
        )}

        {alreadySigned && (!signatureVersion || signatureVersion === MANDAT_FACTURATION_VERSION) && (
          <div className="rounded-xl border-2 border-success/30 bg-success/5 p-4 flex items-start gap-3">
            <CheckCircle className="h-6 w-6 text-success shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat signé et actif</p>
              <p className="text-sm text-muted-foreground mt-0.5">
                Tu as accepté le mandat de facturation version {signatureVersion} le{' '}
                {signatureDate && format(new Date(signatureDate), "dd MMMM yyyy 'à' HH:mm", { locale: fr })}.
              </p>
              <p className="text-xs text-muted-foreground mt-2">
                Jolene peut désormais émettre des factures d'honoraires en ton nom à chaque mission terminée.
                Tu peux révoquer ce mandat à tout moment depuis cette page : aucune nouvelle facture ne
                sera émise après révocation. Les factures déjà émises restent valides et exigibles.
              </p>
              <div className="flex flex-wrap gap-2 mt-3">
                <BoutonY2K
                  type="button"
                  variant="secondary"
                  size="sm"
                  onClick={telechargerPdf}
                  disabled={!signatureMeta}
                  className="gap-2"
                >
                  <Download className="h-4 w-4" />
                  Télécharger mon mandat (PDF)
                </BoutonY2K>
                <BoutonY2K
                  type="button"
                  variant="secondary"
                  size="sm"
                  onClick={() => setShowConfirmRevoke(true)}
                  className="gap-2 text-destructive hover:text-destructive border-destructive/30 hover:bg-destructive/5"
                >
                  Révoquer mon mandat
                </BoutonY2K>
              </div>
            </div>
          </div>
        )}

        {(!alreadySigned || (signatureVersion && signatureVersion !== MANDAT_FACTURATION_VERSION)) && (
          <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4">
            <div className="flex items-start gap-3">
              <ShieldCheck className="h-6 w-6 text-primary shrink-0 mt-0.5" />
              <div className="flex-1 space-y-2">
                <p className="font-semibold text-foreground">Pourquoi signer ce mandat ?</p>
                <ul className="text-sm text-muted-foreground space-y-1 ml-4 list-disc">
                  <li>Jolene pourra produire et envoyer tes factures d'honoraires automatiquement à chaque mission terminée</li>
                  <li>Tes factures sont conservées centralement et accessibles à tout moment</li>
                  <li>Préparation au paiement rapide (avance sous 48h) — disponible prochainement</li>
                  <li>Tu restes libéral indépendant : aucun lien de subordination, aucun changement de statut</li>
                </ul>
              </div>
            </div>
          </div>
        )}

        <div className="card-base p-0 overflow-hidden flex flex-col max-h-[calc(100dvh-14rem)] md:max-h-[70vh]">
          <div
            className="flex-1 min-h-0 overflow-y-auto px-5 py-4 border-b border-border"
            onScroll={handleScroll}
          >
            {renderMarkdown(mandatTexte)}
          </div>

          {!alreadySigned && (
            <div className="p-5 space-y-4 bg-muted/20 shrink-0">
              {!hasScrolledToBottom && (
                <p className="text-xs text-warning italic text-center font-medium" role="status">
                  ⚠️ Fais défiler le document jusqu'en bas pour pouvoir l'accepter
                </p>
              )}

              <div className={`flex items-start gap-3 ${!hasScrolledToBottom ? 'opacity-50' : ''}`}>
                <Checkbox
                  id="accept-mandat"
                  checked={accepted}
                  onCheckedChange={(v) => setAccepted(v === true)}
                  disabled={!hasScrolledToBottom}
                  aria-disabled={!hasScrolledToBottom}
                />
                <label htmlFor="accept-mandat" className={`text-sm text-foreground leading-relaxed ${hasScrolledToBottom ? 'cursor-pointer' : 'cursor-not-allowed'}`}>
                  J'ai lu et j'accepte expressément les termes du mandat de facturation ci-dessus. Je confirme donner mandat à Jolene
                  d'émettre des factures en mon nom et pour mon compte, conformément à l'article 289 I-2 du CGI.
                </label>
              </div>

              <BoutonY2K
                onClick={signer}
                disabled={!accepted || signing || !hasScrolledToBottom}
                className="w-full gap-2"
              >
                {signing ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle className="h-4 w-4" />}
                Signer électroniquement le mandat
              </BoutonY2K>

              <p className="text-[10px] text-muted-foreground text-center">
                Ta signature sera horodatée et archivée comme preuve légale (Articles 1366 et 1367 du Code civil).
              </p>
            </div>
          )}
        </div>
      </div>

      {showConfirmRevoke && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => !revoking && setShowConfirmRevoke(false)}>
          <div className="bg-background rounded-xl shadow-xl max-w-md w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-start gap-3">
              <AlertTriangle className="h-6 w-6 text-destructive shrink-0 mt-0.5" />
              <div>
                <h2 className="text-lg font-bold text-foreground">Révoquer le mandat de facturation ?</h2>
                <p className="text-sm text-muted-foreground mt-1">
                  Cette action est immédiate. Aucune nouvelle facture d'honoraires ne pourra plus
                  être émise par Jolene en ton nom à partir de maintenant.
                </p>
                <p className="text-xs text-muted-foreground mt-2">
                  Les factures déjà émises restent valides et exigibles : la révocation n'a pas
                  d'effet rétroactif (cohérent avec l'art. 289 I-2 CGI). Tu pourras signer un
                  nouveau mandat à tout moment.
                </p>
              </div>
            </div>
            <div className="flex gap-2 justify-end pt-2">
              <BoutonY2K type="button" variant="secondary" disabled={revoking} onClick={() => setShowConfirmRevoke(false)}>
                Annuler
              </BoutonY2K>
              <BoutonY2K type="button" variant="destructive" disabled={revoking} loading={revoking} onClick={revoquer}>
                {revoking ? 'Révocation…' : 'Confirmer la révocation'}
              </BoutonY2K>
            </div>
          </div>
        </div>
      )}
    </LayoutApp>
  );
}
