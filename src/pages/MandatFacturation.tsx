import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, CheckCircle, ShieldCheck, Loader2, ArrowLeft, Download, AlertTriangle, X, HelpCircle, ArrowDown } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Checkbox } from '@/components/ui/checkbox';
import { ModalContacterJolene } from '@/components/ModalContacterJolene';
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

/** Marge de tolérance du gate de scroll : les sous-pixels iOS font échouer
 *  l'égalité stricte scrollTop + clientHeight === scrollHeight. */
const SEUIL_FIN_SCROLL = 24;

export default function MandatFacturation() {
  usePageTitle('Mandat de facturation');
  const navigate = useNavigate();
  const { user } = useAuth();

  const [typeExercice, setTypeExercice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [signing, setSigning] = useState(false);
  const [accepted, setAccepted] = useState(false);
  const [alreadySigned, setAlreadySigned] = useState(false);
  const [justSigned, setJustSigned] = useState(false);
  const [signatureDate, setSignatureDate] = useState<string | null>(null);
  const [signatureVersion, setSignatureVersion] = useState<string | null>(null);
  const [hasScrolledToBottom, setHasScrolledToBottom] = useState(false);
  const [soignantInfo, setSoignantInfo] = useState<SoignantMandatInfo | null>(null);
  const [signatureMeta, setSignatureMeta] = useState<MandatPdfMetadata | null>(null);
  const [showConfirmRevoke, setShowConfirmRevoke] = useState(false);
  const [revoking, setRevoking] = useState(false);
  const [contactOpen, setContactOpen] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

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

  const doitSigner = !loading && (!alreadySigned || (signatureVersion !== null && signatureVersion !== MANDAT_FACTURATION_VERSION));
  const estLiberal = !typeExercice || typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';

  // Gate de scroll : détection tolérante (sous-pixels iOS) + cas « contenu plus
  // court que le viewport » (desktop large : rien à faire défiler → déverrouillé).
  const checkFinScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - SEUIL_FIN_SCROLL) {
      setHasScrolledToBottom(true);
    }
  }, []);

  useEffect(() => {
    if (!doitSigner || loading) return;
    checkFinScroll();
    window.addEventListener('resize', checkFinScroll);
    return () => window.removeEventListener('resize', checkFinScroll);
  }, [doitSigner, loading, mandatTexte, checkFinScroll]);

  // Body scroll lock derrière la sheet : le geste de scroll ne doit JAMAIS
  // partir en scroll chaining sur la page (cause du gate qui ne se déverrouille
  // pas sur iOS Safari — le conteneur interne ne recevait pas le scroll).
  useEffect(() => {
    if (!doitSigner || justSigned || !estLiberal) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = prev; };
  }, [doitSigner, justSigned, estLiberal]);

  const allerALaFin = () => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
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

      const now = new Date().toISOString();
      setAlreadySigned(true);
      setJustSigned(true);
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

  // Retour auto après l'écran de confirmation (les nags mandat de l'app
  // disparaissent d'eux-mêmes : ils lisent mandat_facturation_signe en DB).
  useEffect(() => {
    if (!justSigned) return;
    const t = setTimeout(() => navigate(-1), 3500);
    return () => clearTimeout(t);
  }, [justSigned, navigate]);

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
      setJustSigned(false);
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
  if (!estLiberal) {
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

  // ── Écran de confirmation post-signature (horodaté, retour auto) ─────────
  if (justSigned) {
    return (
      <div className="fixed inset-0 z-50 bg-background flex flex-col items-center justify-center px-6 text-center" style={{ height: '100dvh' }}>
        <div className="h-16 w-16 rounded-full bg-success/10 flex items-center justify-center mb-4">
          <CheckCircle className="h-9 w-9 text-success" />
        </div>
        <h1 className="text-xl font-bold text-foreground">Mandat signé ✓</h1>
        <p className="text-sm text-muted-foreground mt-2 max-w-sm">
          Signature horodatée le{' '}
          <strong className="text-foreground">
            {signatureDate && format(new Date(signatureDate), "d MMMM yyyy 'à' HH:mm", { locale: fr })}
          </strong>{' '}
          et archivée comme preuve légale (art. 1366-1367 du Code civil).
          Jolene peut désormais émettre tes factures d'honoraires à chaque mission terminée.
        </p>
        <div className="flex flex-col gap-2 mt-6 w-full max-w-xs">
          <BoutonY2K onClick={() => navigate(-1)} className="w-full">
            Continuer
          </BoutonY2K>
          <BoutonY2K variant="ghost" size="sm" onClick={telechargerPdf} className="gap-2">
            <Download className="h-4 w-4" /> Télécharger mon mandat (PDF)
          </BoutonY2K>
        </div>
        <p className="text-[11px] text-muted-foreground mt-4">Retour automatique dans quelques secondes…</p>
      </div>
    );
  }

  // ── Sheet plein écran dédiée à la signature ───────────────────────────────
  // Refonte Lot 6a.1 : l'ancien conteneur scrollable imbriqué dans le scroll de
  // page de LayoutApp ne défilait pas sur iOS Safari (scroll chaining) → le gate
  // ne se déverrouillait jamais → signature impossible → boucle de paiement morte.
  if (doitSigner) {
    return (
      <div className="fixed inset-0 z-50 bg-background flex flex-col" style={{ height: '100dvh' }}>
        {/* Header sticky */}
        <header
          className="shrink-0 border-b border-border bg-card px-4 py-3 flex items-center gap-3"
          style={{ paddingTop: 'max(0.75rem, env(safe-area-inset-top))' }}
        >
          <button
            onClick={() => navigate(-1)}
            aria-label="Fermer"
            className="h-10 w-10 -ml-2 flex items-center justify-center rounded-full text-muted-foreground hover:text-foreground hover:bg-muted active:scale-95 transition-all"
          >
            <X className="h-5 w-5" />
          </button>
          <div className="flex-1 min-w-0">
            <h1 className="text-base font-bold text-foreground flex items-center gap-2 truncate">
              <FileText className="h-4 w-4 text-primary shrink-0" /> Mandat de facturation
            </h1>
            <p className="text-[11px] text-muted-foreground">Version {MANDAT_FACTURATION_VERSION} — Article 289 I-2 CGI</p>
          </div>
          {/* Aide contextuelle (le FAB global a été retiré — Lot 6a.4) */}
          <button
            onClick={() => setContactOpen(true)}
            aria-label="Besoin d'aide ?"
            className="h-10 w-10 -mr-2 flex items-center justify-center rounded-full text-muted-foreground hover:text-primary hover:bg-muted active:scale-95 transition-all"
          >
            <HelpCircle className="h-5 w-5" />
          </button>
        </header>

        {/* Corps scrollable — SEULE zone de scroll de l'écran */}
        <div
          ref={scrollRef}
          onScroll={checkFinScroll}
          className="flex-1 min-h-0 overflow-y-auto px-5 py-4"
          style={{ overscrollBehavior: 'contain', WebkitOverflowScrolling: 'touch' }}
        >
          {signatureVersion && signatureVersion !== MANDAT_FACTURATION_VERSION && (
            <div className="rounded-xl border-2 border-warning/50 bg-warning/10 p-4 flex items-start gap-3 mb-4">
              <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
              <div className="flex-1">
                <p className="font-semibold text-foreground text-sm">Mandat mis à jour — re-signature requise</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Ton mandat (version {signatureVersion}) n'est plus à jour. Lis et accepte la
                  version {MANDAT_FACTURATION_VERSION} pour continuer à recevoir tes factures.
                </p>
              </div>
            </div>
          )}

          <div className="rounded-xl border border-primary/20 bg-primary/5 p-4 mb-5">
            <div className="flex items-start gap-3">
              <ShieldCheck className="h-5 w-5 text-primary shrink-0 mt-0.5" />
              <div className="flex-1 space-y-1.5">
                <p className="font-semibold text-foreground text-sm">Pourquoi signer ce mandat ?</p>
                <ul className="text-xs text-muted-foreground space-y-1 ml-4 list-disc">
                  <li>Jolene produit et envoie tes factures d'honoraires automatiquement à chaque mission terminée</li>
                  <li>Tes factures sont conservées centralement et accessibles à tout moment</li>
                  <li>Tu restes libéral indépendant : aucun lien de subordination, aucun changement de statut</li>
                </ul>
              </div>
            </div>
          </div>

          {renderMarkdown(mandatTexte)}
          {/* Sentinelle de fin — un peu d'air pour que le dernier paragraphe ne colle pas au footer */}
          <div className="h-4" aria-hidden="true" />
        </div>

        {/* Bouton « Aller à la fin » — visible tant que le gate n'est pas déverrouillé */}
        {!hasScrolledToBottom && (
          <div className="absolute bottom-40 inset-x-0 flex justify-center pointer-events-none z-10">
            <button
              onClick={allerALaFin}
              className="pointer-events-auto inline-flex items-center gap-1.5 rounded-full bg-foreground text-background text-sm font-medium px-4 py-2.5 shadow-lg active:scale-95 transition-transform"
            >
              Aller à la fin <ArrowDown className="h-4 w-4" />
            </button>
          </div>
        )}

        {/* Footer sticky : checkbox + CTA */}
        <footer
          className="shrink-0 border-t border-border bg-card px-5 pt-4 space-y-3"
          style={{ paddingBottom: 'max(1rem, env(safe-area-inset-bottom))' }}
        >
          {!hasScrolledToBottom && (
            <p className="text-xs text-muted-foreground text-center" role="status">
              Fais défiler le document jusqu'en bas pour pouvoir l'accepter
            </p>
          )}
          <div className={`flex items-start gap-3 ${!hasScrolledToBottom ? 'opacity-50' : ''}`}>
            <Checkbox
              id="accept-mandat"
              checked={accepted}
              onCheckedChange={(v) => setAccepted(v === true)}
              disabled={!hasScrolledToBottom}
              aria-disabled={!hasScrolledToBottom}
              className="mt-0.5"
            />
            <label htmlFor="accept-mandat" className={`text-xs text-foreground leading-relaxed ${hasScrolledToBottom ? 'cursor-pointer' : 'cursor-not-allowed'}`}>
              J'ai lu et j'accepte les termes du mandat. Je donne mandat à Jolene d'émettre des
              factures en mon nom et pour mon compte (art. 289 I-2 CGI).
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
          <p className="text-[10px] text-muted-foreground text-center pb-1">
            Signature horodatée et archivée comme preuve légale (art. 1366-1367 du Code civil).
          </p>
        </footer>

        <ModalContacterJolene open={contactOpen} onClose={() => setContactOpen(false)} source="mandat-facturation" />
      </div>
    );
  }

  // ── Mandat signé et à jour : page de statut classique ────────────────────
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

        {/* Texte du mandat en consultation (pas de gate : déjà signé) */}
        <div className="card-base">
          {renderMarkdown(mandatTexte)}
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
