/**
 * ActiverEtablissement — Session F item F2.
 *
 * Page unique « Activer mon établissement » qui fusionne les deux anciens
 * parcours d'activation établissement en une checklist à 3 étapes :
 *   1. Contrat plateforme (signature électronique) — logique reprise de
 *      l'ancienne FinaliserInscriptionEtab (RPC fn_signer_contrat_service).
 *   2. Vérification établissement (FINESS + représentant + e-mail pro) —
 *      logique reprise de l'ancienne VerificationEtablissement (edge functions
 *      verify-finess / verify-piece-identite-etab + RPC
 *      fn_demander_confirmation_email_etab).
 *   3. Coordonnées bancaires (RIB) — DIFFÉRÉ : demandé à la première
 *      facturation (just-in-time, standard Stripe). Aucune action requise ici.
 *
 * Les états ✓ done / actuel / à faire sont pilotés par l'état réel de
 * l'établissement (contrat signé ? rattachement vérifié ?). Le CTA principal
 * fait défiler / ouvre la première étape incomplète.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { messageErreurEdgeFn } from '@/lib/erreurs';
import {
  FileText, CheckCircle, CheckCircle2, Loader2, ArrowLeft, Shield, Upload,
  Building2, UserCheck, Mail, AlertTriangle, Clock, CreditCard, ChevronRight,
} from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import SignatureCanvas from '@/components/SignatureCanvas';
import { buildContratServiceTexte, CONTRAT_SERVICE_VERSION, hashContratTexte } from '@/constantes/contratServiceEtablissement';

/* ─── Markdown léger (repris de FinaliserInscriptionEtab) ─────────────────── */
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
            <li key={i} dangerouslySetInnerHTML={{ __html: item.replace(/[<>]/g, m => m === '<' ? '&lt;' : '&gt;').replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />
          ))}
        </ol>,
      );
      listBuffer = [];
    }
  };
  for (const line of lines) {
    if (line.startsWith('# ')) { flushList(); elements.push(<h1 key={key++} className="text-xl font-bold text-foreground mb-3 mt-2">{line.substring(2)}</h1>); }
    else if (line.startsWith('## ')) { flushList(); elements.push(<h2 key={key++} className="text-base font-bold text-foreground mt-5 mb-2">{line.substring(3)}</h2>); }
    else if (line.match(/^\d+\.\s/)) { listBuffer.push(line.replace(/^\d+\.\s/, '')); }
    else if (line.startsWith('- ')) { listBuffer.push(line.substring(2)); }
    else if (line.trim() === '---') { flushList(); elements.push(<hr key={key++} className="border-border my-4" />); }
    else if (line.trim() === '') { flushList(); }
    else { flushList(); elements.push(<p key={key++} className="text-sm text-foreground mb-2 leading-relaxed" dangerouslySetInnerHTML={{ __html: line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />); }
  }
  flushList();
  return elements;
}

/* ─── Vérification : libellés + types (repris de VerificationEtablissement) ── */
type EtabState = {
  nom: string | null;
  siret?: string | null;
  type?: string | null;
  adresse_rue?: string | null;
  adresse_code_postal?: string | null;
  adresse_ville?: string | null;
  email_contact: string | null;
  // Contrat
  contrat_service_signe: boolean | null;
  contrat_service_signe_le: string | null;
  // Vérification
  finess: string | null;
  finess_verifie: boolean | null;
  finess_raison_sociale: string | null;
  representant_nom: string | null;
  representant_prenom: string | null;
  representant_identite_verifiee: boolean | null;
  email_contact_verifie: boolean | null;
  rattachement_methode: string | null;
  rattachement_verifie: boolean | null;
};

const LIBELLE_METHODE: Record<string, string> = {
  AUTO_DIRIGEANT: 'Dirigeant vérifié (INSEE)',
  EMAIL_PRO: 'E-mail professionnel confirmé',
  ADMIN: 'Validation par un administrateur Jolene',
};

const ALLOWED_EXT = ['pdf', 'jpg', 'jpeg', 'png'];

type EtatEtape = 'fait' | 'actuel' | 'a_faire';

export default function ActiverEtablissement() {
  usePageTitle('Activer mon établissement');
  const navigate = useNavigate();
  const { user } = useAuth();

  const [loading, setLoading] = useState(true);
  const [etab, setEtab] = useState<EtabState | null>(null);

  // ── Étape 1 : Contrat ──────────────────────────────────────────────────────
  const [hasScrolled, setHasScrolled] = useState(false);
  const [accepte, setAccepte] = useState(false);
  const [certifie, setCertifie] = useState(false);
  const [signing, setSigning] = useState(false);
  const signLockRef = useRef(false);

  // ── Étape 2 : Vérification ─────────────────────────────────────────────────
  const [finessInput, setFinessInput] = useState('');
  const [finessLoading, setFinessLoading] = useState(false);
  const [nom, setNom] = useState('');
  const [prenom, setPrenom] = useState('');
  const [typeDoc, setTypeDoc] = useState<'CARTE_IDENTITE' | 'PASSEPORT' | 'TITRE_SEJOUR'>('CARTE_IDENTITE');
  const [pieceFile, setPieceFile] = useState<File | null>(null);
  const [pieceLoading, setPieceLoading] = useState(false);
  const pieceLockRef = useRef(false);
  const [emailInput, setEmailInput] = useState('');
  const [emailLoading, setEmailLoading] = useState(false);

  // Étape actuellement dépliée (1 = contrat, 2 = vérif, 3 = RIB différé)
  const [etapeOuverte, setEtapeOuverte] = useState<1 | 2 | 3 | null>(null);

  const recharger = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('etablissements')
      .select('nom, siret, type, adresse_rue, adresse_code_postal, adresse_ville, email_contact, contrat_service_signe, contrat_service_signe_le, finess, finess_verifie, finess_raison_sociale, representant_nom, representant_prenom, representant_identite_verifiee, email_contact_verifie, rattachement_methode, rattachement_verifie')
      .eq('id', user.id)
      .maybeSingle();
    if (data) {
      const d = data as unknown as EtabState;
      setEtab(d);
      setFinessInput(d.finess || '');
      setNom(d.representant_nom || '');
      setPrenom(d.representant_prenom || '');
      setEmailInput(d.email_contact || '');
    }
  };

  useEffect(() => {
    if (!user) return;
    (async () => {
      await recharger();
      setLoading(false);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user]);

  // ── États dérivés ──────────────────────────────────────────────────────────
  const contratSigne = !!etab?.contrat_service_signe;
  const rattachOk = !!etab?.rattachement_verifie;
  const finessOk = !!etab?.finess_verifie;
  const identiteOk = !!etab?.representant_identite_verifiee;
  const emailOk = !!etab?.email_contact_verifie;
  const toutActive = contratSigne && rattachOk;

  // Première étape incomplète (1 contrat → 2 vérif). Le RIB (3) est différé,
  // jamais bloquant.
  const premiereEtapeIncomplete: 1 | 2 | null = !contratSigne ? 1 : !rattachOk ? 2 : null;

  // Au chargement, ouvrir automatiquement la première étape incomplète.
  useEffect(() => {
    if (loading) return;
    if (etapeOuverte !== null) return;
    setEtapeOuverte(premiereEtapeIncomplete);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading]);

  const contratTexte = useMemo(
    () => buildContratServiceTexte(etab || {}),
    [etab],
  );

  const etatEtape = (index: 1 | 2 | 3): EtatEtape => {
    if (index === 1) return contratSigne ? 'fait' : premiereEtapeIncomplete === 1 ? 'actuel' : 'a_faire';
    if (index === 2) {
      if (rattachOk) return 'fait';
      return premiereEtapeIncomplete === 2 ? 'actuel' : 'a_faire';
    }
    // Étape 3 (RIB) : différée → toujours « à renseigner plus tard ».
    return 'a_faire';
  };

  // ── Étape 1 : Contrat ──────────────────────────────────────────────────────
  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 50) setHasScrolled(true);
  };

  const signerContrat = async (signatureBase64: string) => {
    if (!user) return;
    if (signLockRef.current) return; // verrou synchrone anti double-clic
    signLockRef.current = true;
    setSigning(true);
    try {
      // Upload signature image (PNG base64 → bucket jolene-documents)
      let signatureS3Key: string | null = null;
      try {
        const matches = signatureBase64.match(/^data:image\/(\w+);base64,(.+)$/);
        if (matches) {
          const ext = matches[1] === 'jpeg' ? 'jpg' : matches[1];
          const binary = atob(matches[2]);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const blob = new Blob([bytes], { type: `image/${matches[1]}` });
          const path = `${user.id}/signatures/contrat-service-${Date.now()}.${ext}`;
          const { error: upErr } = await supabase.storage
            .from('jolene-documents')
            .upload(path, blob, { upsert: false, contentType: `image/${matches[1]}` });
          if (!upErr) signatureS3Key = path;
        }
      } catch {
        // Best-effort : si upload signature échoue, continue sans bloquer
      }

      const hash = await hashContratTexte(contratTexte);
      // L'IP réelle est récupérée côté serveur (RPC SECURITY DEFINER). Passer
      // '' depuis le frontend est safe : la RPC override avec l'IP serveur.
      const { data, error } = await supabase.rpc('fn_signer_contrat_service' as any, {
        p_version: CONTRAT_SERVICE_VERSION,
        p_ip: '',
        p_user_agent: navigator.userAgent,
        p_contenu_hash: hash,
        p_signature_s3_key: signatureS3Key,
      });
      if (error) throw error;
      if ((data as any)?.success === false) throw new Error((data as any)?.error);
      toast.success('Contrat de service signé avec succès !');
      await recharger();
      // Avancer vers l'étape de vérification.
      setEtapeOuverte(2);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la signature');
    } finally {
      signLockRef.current = false;
      setSigning(false);
    }
  };

  // ── Étape 2 : FINESS ───────────────────────────────────────────────────────
  const verifierFiness = async () => {
    if (!user) return;
    const finess = finessInput.replace(/\D/g, '');
    if (finess.length !== 9) {
      toast.error('Le numéro FINESS comporte 9 chiffres.');
      return;
    }
    setFinessLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('verify-finess', {
        body: { finess, etablissement_id: user.id },
      });
      if (error) { toast.error(await messageErreurEdgeFn(error, 'Erreur lors de la vérification FINESS. Réessayez.')); return; }
      if (data?.fhir_indisponible) {
        toast.error('Annuaire Santé momentanément indisponible. Réessayez dans un instant.');
      } else if (data?.trouve === false) {
        toast.error("Ce numéro FINESS est introuvable dans l'Annuaire Santé.");
      } else if (data?.verifie) {
        toast.success(`FINESS vérifié : ${data.raison_sociale || 'structure trouvée'}.`);
        await recharger();
      } else {
        toast.error("Cet établissement n'est pas actif dans l'Annuaire Santé.");
      }
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur lors de la vérification FINESS.');
    } finally {
      setFinessLoading(false);
    }
  };

  // ── Étape 2 : Représentant ─────────────────────────────────────────────────
  const verifierPiece = async () => {
    if (!user || !pieceFile) return;
    if (pieceLockRef.current) return;
    if (!nom.trim()) {
      toast.error('Veuillez renseigner le nom du représentant.');
      return;
    }
    const ext = pieceFile.name.split('.').pop()?.toLowerCase() || '';
    if (!ALLOWED_EXT.includes(ext)) {
      toast.error('Format accepté : PDF, JPG ou PNG.');
      return;
    }
    if (pieceFile.size > 10 * 1024 * 1024) {
      toast.error('Fichier trop volumineux (max 10 Mo).');
      return;
    }
    pieceLockRef.current = true;
    setPieceLoading(true);
    try {
      const mime = ext === 'pdf' ? 'application/pdf' : `image/${ext === 'jpg' ? 'jpeg' : ext}`;
      const path = `${user.id}/representant-piece-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, pieceFile, { upsert: true, contentType: mime });
      if (upErr) throw upErr;

      const { error: updErr } = await supabase
        .from('etablissements')
        .update({
          representant_nom: nom.trim(),
          representant_prenom: prenom.trim() || null,
          representant_piece_s3_key: path,
          representant_piece_type_mime: mime,
          representant_piece_type_document: typeDoc,
        } as Record<string, unknown>)
        .eq('id', user.id);
      if (updErr) throw updErr;

      const { data, error } = await supabase.functions.invoke('verify-piece-identite-etab', {
        body: { etablissement_id: user.id },
      });
      if (error) { toast.error(await messageErreurEdgeFn(error, "Le document n'a pas pu être vérifié. Vérifiez qu'il s'agit bien d'une pièce d'identité officielle (CNI, passeport, titre de séjour), lisible et complète.")); return; }

      if (data?.identite_verifiee) {
        toast.success('Identité du représentant vérifiée.');
      } else if (data?.verdict === 'REJETE') {
        toast.error(data?.motif || "Le document n'a pas pu être validé. Vérifiez la lisibilité et la concordance du nom.");
      } else if (data?.verdict === 'EN_ATTENTE') {
        toast('Vérification en cours d\'analyse. Le résultat sera mis à jour sous peu.');
      } else if (data?.nom_correspond === false) {
        toast.error('Le nom du document ne correspond pas au représentant déclaré.');
      } else {
        toast('Document reçu. Vérification en cours.');
      }
      setPieceFile(null);
      await recharger();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur lors de la vérification de la pièce.');
    } finally {
      pieceLockRef.current = false;
      setPieceLoading(false);
    }
  };

  // ── Étape 2 : E-mail professionnel ─────────────────────────────────────────
  const envoyerLienEmail = async () => {
    if (!user) return;
    const email = emailInput.trim();
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(email)) {
      toast.error('Adresse e-mail invalide.');
      return;
    }
    setEmailLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_demander_confirmation_email_etab' as any, {
        p_etablissement_id: user.id,
        p_email: email,
      } as any);
      if (error) throw error;
      if ((data as { success?: boolean })?.success === false) {
        throw new Error((data as { error?: string })?.error || 'Erreur');
      }
      toast.success(`Un lien de confirmation a été envoyé à ${email}.`);
      await recharger();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur lors de l\'envoi du lien.');
    } finally {
      setEmailLoading(false);
    }
  };

  // CTA principal : ouvre la première étape incomplète.
  const avancerVersProchaineEtape = () => {
    if (premiereEtapeIncomplete) {
      setEtapeOuverte(premiereEtapeIncomplete);
      requestAnimationFrame(() => {
        document.getElementById(`etape-${premiereEtapeIncomplete}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    } else {
      navigate('/etablissement/tableau-de-bord');
    }
  };

  if (loading) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  const PuceEtape = ({ index, icone }: { index: 1 | 2 | 3; icone: React.ReactNode }) => {
    const etat = etatEtape(index);
    return (
      <div
        className={
          etat === 'fait'
            ? 'flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-jolene-cyan-100 text-jolene-cyan-800 border-2 border-jolene-cyan-300'
            : etat === 'actuel'
              ? 'flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-hero text-white shadow-holographic'
              : 'flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground border border-border'
        }
      >
        {etat === 'fait' ? <CheckCircle2 className="h-5 w-5" /> : icone}
      </div>
    );
  };

  const EnTeteEtape = ({ index, etat }: { index: 1 | 2 | 3; etat: EtatEtape }) => (
    <BadgeY2K
      variant={etat === 'fait' ? 'success' : etat === 'actuel' ? 'info' : 'warning'}
      size="sm"
    >
      {etat === 'fait' ? 'Terminé' : etat === 'actuel' ? 'À compléter' : index === 3 ? 'Plus tard' : 'À faire'}
    </BadgeY2K>
  );

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-3xl mx-auto space-y-5">
        {/* En-tête */}
        <div className="flex items-center gap-3">
          <BoutonY2K variant="ghost" size="sm" onClick={() => navigate(-1)} aria-label="Retour">
            <ArrowLeft className="h-5 w-5" />
          </BoutonY2K>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <Shield className="h-5 w-5 text-primary" /> Activer mon établissement
            </h1>
            <p className="text-xs text-muted-foreground">
              Signez le contrat de service et vérifiez votre établissement pour publier des missions.
            </p>
          </div>
        </div>

        {/* Statut global */}
        <div className={`rounded-xl border-2 p-4 flex items-start gap-3 ${toutActive ? 'border-jolene-cyan-300 bg-jolene-cyan-50' : 'border-amber-200 bg-amber-50'}`}>
          {toutActive ? <CheckCircle2 className="h-6 w-6 text-jolene-cyan-700 shrink-0 mt-0.5" /> : <Clock className="h-6 w-6 text-amber-600 shrink-0 mt-0.5" />}
          <div className="flex-1">
            <p className="font-semibold text-foreground">
              {toutActive ? 'Établissement activé' : 'Activation en cours'}
            </p>
            <p className="text-sm text-muted-foreground mt-1">
              {toutActive
                ? 'Votre contrat est signé et votre établissement est vérifié. Vous pouvez publier des missions. Le RIB vous sera demandé à la première facturation.'
                : `Étape ${premiereEtapeIncomplete === 1 ? '1 — contrat de service' : '2 — vérification de l\'établissement'} à compléter.`}
            </p>
            {!toutActive && (
              <BoutonY2K size="sm" className="mt-3 gap-1" onClick={avancerVersProchaineEtape} iconeDroite={<ChevronRight className="h-4 w-4" />}>
                {premiereEtapeIncomplete === 1 ? 'Signer le contrat' : 'Vérifier mon établissement'}
              </BoutonY2K>
            )}
            {toutActive && (
              <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => navigate('/etablissement/tableau-de-bord')}>
                Aller au tableau de bord
              </BoutonY2K>
            )}
          </div>
        </div>

        {/* ── Étape 1 : Contrat de service ──────────────────────────────────── */}
        <CardY2K id="etape-1" noPadding className="overflow-hidden">
          <div className="p-5 space-y-3">
            <div className="flex items-center gap-3">
              <PuceEtape index={1} icone={<FileText className="h-5 w-5" />} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground">1. Contrat de service</p>
                <p className="text-xs text-muted-foreground">Signature électronique du contrat plateforme Jolene</p>
              </div>
              <EnTeteEtape index={1} etat={etatEtape(1)} />
            </div>

            {contratSigne ? (
              <div className="rounded-xl border border-jolene-cyan-200 bg-jolene-cyan-50 p-3 flex items-center gap-3">
                <CheckCircle className="h-5 w-5 text-jolene-cyan-700 shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">Contrat de service signé</p>
                  <p className="text-xs text-muted-foreground">
                    Version {CONTRAT_SERVICE_VERSION} — signé le {etab?.contrat_service_signe_le ? new Date(etab.contrat_service_signe_le).toLocaleDateString('fr-FR') : 'aujourd\'hui'}
                  </p>
                </div>
              </div>
            ) : etapeOuverte === 1 ? (
              <div className="space-y-4 pt-1">
                <div className="rounded-xl border border-border bg-card p-4">
                  <p className="text-sm font-semibold text-foreground mb-3">Contrat de service Jolene — Version {CONTRAT_SERVICE_VERSION}</p>
                  <div
                    className="max-h-[50vh] overflow-y-auto border border-border rounded-lg p-4 bg-muted/20 text-sm"
                    onScroll={handleScroll}
                  >
                    {renderMarkdown(contratTexte)}
                  </div>
                  {!hasScrolled && (
                    <p className="text-xs text-muted-foreground mt-2 animate-pulse">Veuillez lire le contrat jusqu'au bout pour pouvoir signer.</p>
                  )}
                </div>

                <div className="space-y-3">
                  <label className="flex items-start gap-3 cursor-pointer">
                    <Checkbox checked={accepte} onCheckedChange={v => setAccepte(!!v)} disabled={!hasScrolled} />
                    <span className="text-sm text-foreground">J'ai lu et j'accepte le contrat de service Jolene</span>
                  </label>
                  <label className="flex items-start gap-3 cursor-pointer">
                    <Checkbox checked={certifie} onCheckedChange={v => setCertifie(!!v)} disabled={!hasScrolled} />
                    <span className="text-sm text-foreground">Je certifie être habilité(e) à engager mon établissement</span>
                  </label>
                </div>

                {accepte && certifie && (
                  <div className="space-y-3">
                    <p className="text-sm font-medium text-foreground">Votre signature :</p>
                    <SignatureCanvas onSave={signerContrat} />
                    {signing && (
                      <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <Loader2 className="h-4 w-4 animate-spin" /> Signature en cours...
                      </div>
                    )}
                  </div>
                )}
              </div>
            ) : (
              <BoutonY2K size="sm" variant="secondary" onClick={() => setEtapeOuverte(1)}>
                Signer le contrat
              </BoutonY2K>
            )}
          </div>
        </CardY2K>

        {/* ── Étape 2 : Vérification de l'établissement ─────────────────────── */}
        <CardY2K id="etape-2" noPadding className="overflow-hidden">
          <div className="p-5 space-y-3">
            <div className="flex items-center gap-3">
              <PuceEtape index={2} icone={<Building2 className="h-5 w-5" />} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground">2. Vérification de l'établissement</p>
                <p className="text-xs text-muted-foreground">FINESS, représentant légal et e-mail professionnel</p>
              </div>
              <EnTeteEtape index={2} etat={etatEtape(2)} />
            </div>

            {rattachOk ? (
              <div className="rounded-xl border border-jolene-cyan-200 bg-jolene-cyan-50 p-3 flex items-center gap-3">
                <CheckCircle2 className="h-5 w-5 text-jolene-cyan-700 shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">Établissement vérifié</p>
                  <p className="text-xs text-muted-foreground">
                    Rattachement validé — {LIBELLE_METHODE[etab?.rattachement_methode || 'ADMIN'] || 'validé'}.
                  </p>
                </div>
              </div>
            ) : !contratSigne ? (
              <p className="text-xs text-muted-foreground">
                Signez d'abord le contrat de service (étape 1) pour débloquer la vérification.
              </p>
            ) : etapeOuverte === 2 ? (
              <div className="space-y-4 pt-1">
                {/* 2a. FINESS */}
                <section className="rounded-xl border border-border bg-card p-4 space-y-3">
                  <p className="text-sm font-semibold text-foreground flex items-center gap-2">
                    <Building2 className="h-4 w-4 text-primary" /> Numéro FINESS
                    {finessOk && <CheckCircle2 className="h-4 w-4 text-jolene-cyan-700" />}
                  </p>
                  {finessOk ? (
                    <p className="text-sm text-muted-foreground">
                      Vérifié — <strong>{etab?.finess_raison_sociale || etab?.finess}</strong> (FINESS {etab?.finess}).
                    </p>
                  ) : (
                    <>
                      <p className="text-xs text-muted-foreground">
                        Le numéro FINESS (9 chiffres) identifie votre structure dans l'Annuaire Santé officiel.
                      </p>
                      <div className="flex flex-col sm:flex-row gap-2">
                        <div className="flex-1">
                          <Label htmlFor="finess-input" className="sr-only">Numéro FINESS</Label>
                          <Input
                            id="finess-input"
                            inputMode="numeric"
                            placeholder="Ex. 750100125"
                            value={finessInput}
                            onChange={e => setFinessInput(e.target.value)}
                            maxLength={11}
                          />
                        </div>
                        <BoutonY2K onClick={verifierFiness} disabled={finessLoading} className="gap-2">
                          {finessLoading && <Loader2 className="h-4 w-4 animate-spin" />}
                          Vérifier
                        </BoutonY2K>
                      </div>
                    </>
                  )}
                </section>

                {/* 2b. Représentant */}
                <section className="rounded-xl border border-border bg-card p-4 space-y-3">
                  <p className="text-sm font-semibold text-foreground flex items-center gap-2">
                    <UserCheck className="h-4 w-4 text-primary" /> Représentant de l'établissement
                    {identiteOk && <CheckCircle2 className="h-4 w-4 text-jolene-cyan-700" />}
                  </p>
                  {identiteOk ? (
                    <p className="text-sm text-muted-foreground">
                      Identité vérifiée — <strong>{etab?.representant_prenom} {etab?.representant_nom}</strong>.
                    </p>
                  ) : (
                    <>
                      <p className="text-xs text-muted-foreground">
                        Renseignez l'identité de la personne habilitée et téléversez sa pièce d'identité (CNI, passeport ou titre de séjour). Pour les petites structures, une correspondance automatique avec le dirigeant déclaré valide le rattachement.
                      </p>
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div>
                          <Label htmlFor="rep-prenom">Prénom</Label>
                          <Input id="rep-prenom" value={prenom} onChange={e => setPrenom(e.target.value)} placeholder="Prénom" />
                        </div>
                        <div>
                          <Label htmlFor="rep-nom">Nom</Label>
                          <Input id="rep-nom" value={nom} onChange={e => setNom(e.target.value)} placeholder="Nom de famille" />
                        </div>
                      </div>
                      <div>
                        <Label htmlFor="rep-type-doc">Type de document</Label>
                        <select
                          id="rep-type-doc"
                          value={typeDoc}
                          onChange={e => setTypeDoc(e.target.value as typeof typeDoc)}
                          className="block w-full mt-1 rounded-lg border border-border bg-background px-3 py-2 text-sm"
                        >
                          <option value="CARTE_IDENTITE">Carte nationale d'identité</option>
                          <option value="PASSEPORT">Passeport</option>
                          <option value="TITRE_SEJOUR">Titre de séjour</option>
                        </select>
                      </div>
                      <div>
                        <Label htmlFor="rep-piece" className="sr-only">Pièce d'identité</Label>
                        <input
                          id="rep-piece"
                          type="file"
                          accept=".pdf,.jpg,.jpeg,.png"
                          onChange={e => setPieceFile(e.target.files?.[0] || null)}
                          className="block w-full text-sm text-foreground file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer"
                        />
                        {pieceFile && (
                          <p className="text-xs text-muted-foreground mt-1">
                            {pieceFile.name} ({(pieceFile.size / 1024).toFixed(0)} Ko)
                          </p>
                        )}
                      </div>
                      <BoutonY2K onClick={verifierPiece} disabled={!pieceFile || pieceLoading} className="gap-2">
                        {pieceLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
                        Vérifier la pièce d'identité
                      </BoutonY2K>
                    </>
                  )}
                </section>

                {/* 2c. E-mail professionnel */}
                <section className="rounded-xl border border-border bg-card p-4 space-y-3">
                  <p className="text-sm font-semibold text-foreground flex items-center gap-2">
                    <Mail className="h-4 w-4 text-primary" /> E-mail professionnel
                    {emailOk && <CheckCircle2 className="h-4 w-4 text-jolene-cyan-700" />}
                  </p>
                  {emailOk ? (
                    <p className="text-sm text-muted-foreground">
                      Confirmé — <strong>{etab?.email_contact}</strong>.
                    </p>
                  ) : (
                    <>
                      <p className="text-xs text-muted-foreground">
                        Alternative pour les grands établissements (CHU, groupes) : confirmez une adresse e-mail au domaine professionnel de la structure. Un lien de validation (valable 24h) vous sera envoyé.
                      </p>
                      <div className="flex flex-col sm:flex-row gap-2">
                        <div className="flex-1">
                          <Label htmlFor="email-input" className="sr-only">E-mail professionnel</Label>
                          <Input
                            id="email-input"
                            type="email"
                            placeholder="prenom.nom@etablissement.fr"
                            value={emailInput}
                            onChange={e => setEmailInput(e.target.value)}
                          />
                        </div>
                        <BoutonY2K variant="secondary" onClick={envoyerLienEmail} disabled={emailLoading} className="gap-2">
                          {emailLoading && <Loader2 className="h-4 w-4 animate-spin" />}
                          Envoyer le lien
                        </BoutonY2K>
                      </div>
                    </>
                  )}
                </section>

                <div className="rounded-xl border border-border bg-muted/20 p-3 flex items-start gap-3">
                  <AlertTriangle className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" />
                  <p className="text-xs text-muted-foreground">
                    Si aucune de ces méthodes n'aboutit, un administrateur Jolene validera manuellement votre rattachement après examen de votre dossier.
                  </p>
                </div>
              </div>
            ) : (
              <BoutonY2K size="sm" variant="secondary" onClick={() => setEtapeOuverte(2)}>
                Vérifier mon établissement
              </BoutonY2K>
            )}
          </div>
        </CardY2K>

        {/* ── Étape 3 : Coordonnées bancaires (différé) ─────────────────────── */}
        <CardY2K id="etape-3" noPadding className="overflow-hidden">
          <div className="p-5 space-y-3">
            <div className="flex items-center gap-3">
              <PuceEtape index={3} icone={<CreditCard className="h-5 w-5" />} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground">3. Coordonnées bancaires (RIB)</p>
                <p className="text-xs text-muted-foreground">À renseigner à la première facturation</p>
              </div>
              <EnTeteEtape index={3} etat={etatEtape(3)} />
            </div>
            <div className="rounded-xl border border-border bg-muted/20 p-3 flex items-start gap-3">
              <Clock className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" />
              <p className="text-xs text-muted-foreground">
                Aucune action requise maintenant. Vos coordonnées bancaires vous seront demandées au moment de votre première facturation, afin de ne pas retarder la publication de vos missions.
              </p>
            </div>
          </div>
        </CardY2K>
      </div>
    </LayoutApp>
  );
}
