/**
 * VerificationEtablissement — page établissement de vérification d'identité.
 * Pendant symétrique du parcours de vérification soignant. Trois briques :
 *   1. FINESS — vérification de la structure via l'Annuaire Santé (edge verify-finess).
 *   2. Représentant — nom/prénom + pièce d'identité (edge verify-piece-identite-etab),
 *      match automatique avec un dirigeant INSEE → rattachement AUTO_DIRIGEANT.
 *   3. E-mail professionnel — lien de confirmation (fn_demander_confirmation_email_etab)
 *      → rattachement EMAIL_PRO (gros établissements).
 *
 * Le rattachement adaptatif (fn_evaluer_rattachement_etablissement) choisit la
 * meilleure méthode disponible. Si aucune n'aboutit → validation ADMIN.
 */

import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { messageErreurEdgeFn } from '@/lib/erreurs';
import {
  Shield, CheckCircle2, Building2, UserCheck, Mail, Upload, Loader2,
  ArrowLeft, AlertTriangle, Clock, FileText,
} from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { verifierFichierDocument } from '@/lib/documentUpload';
import { toast } from 'sonner';

type EtabVerif = {
  nom: string | null;
  finess: string | null;
  finess_verifie: boolean | null;
  finess_raison_sociale: string | null;
  representant_nom: string | null;
  representant_prenom: string | null;
  representant_identite_verifiee: boolean | null;
  justificatif_fonction_verifie: boolean | null;
  email_contact: string | null;
  email_contact_verifie: boolean | null;
  rattachement_methode: string | null;
  rattachement_verifie: boolean | null;
};

const LIBELLE_METHODE: Record<string, string> = {
  AUTO_DIRIGEANT: 'Dirigeant vérifié (INSEE)',
  JUSTIFICATIF: 'Justificatif de fonction vérifié',
  EMAIL_PRO: 'E-mail professionnel confirmé',
  ADMIN: 'Validation par un administrateur Jolene',
};

export default function VerificationEtablissement() {
  usePageTitle('Vérification établissement');
  const navigate = useNavigate();
  const { user } = useAuth();

  const [loading, setLoading] = useState(true);
  const [etab, setEtab] = useState<EtabVerif | null>(null);

  // FINESS
  const [finessInput, setFinessInput] = useState('');
  const [finessLoading, setFinessLoading] = useState(false);

  // Représentant
  const [nom, setNom] = useState('');
  const [prenom, setPrenom] = useState('');
  const [typeDoc, setTypeDoc] = useState<'CARTE_IDENTITE' | 'PASSEPORT' | 'TITRE_SEJOUR'>('CARTE_IDENTITE');
  const [pieceFile, setPieceFile] = useState<File | null>(null);
  const [pieceLoading, setPieceLoading] = useState(false);
  const pieceLockRef = useRef(false);

  // Justificatif de fonction (non-dirigeants : RH, chef de service, délégataire)
  const [justifType, setJustifType] = useState<'ATTESTATION_EMPLOYEUR' | 'DELEGATION_SIGNATURE' | 'FICHE_POSTE' | 'CONTRAT_TRAVAIL' | 'DECISION_NOMINATION'>('DELEGATION_SIGNATURE');
  const [justifFile, setJustifFile] = useState<File | null>(null);
  const [justifLoading, setJustifLoading] = useState(false);
  const justifLockRef = useRef(false);

  // E-mail pro
  const [emailInput, setEmailInput] = useState('');
  const [emailLoading, setEmailLoading] = useState(false);

  const recharger = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('etablissements')
      .select('nom, finess, finess_verifie, finess_raison_sociale, representant_nom, representant_prenom, representant_identite_verifiee, justificatif_fonction_verifie, email_contact, email_contact_verifie, rattachement_methode, rattachement_verifie')
      .eq('id', user.id)
      .maybeSingle();
    if (data) {
      const d = data as unknown as EtabVerif;
      setEtab(d);
      setFinessInput(d.finess || '');
      setNom(d.representant_nom || '');
      setPrenom(d.representant_prenom || '');
      setEmailInput(d.email_contact || '');
    }
  };

  useEffect(() => {
    (async () => {
      await recharger();
      setLoading(false);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user]);

  // ── FINESS ────────────────────────────────────────────────────────────────
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
        await recharger();
      } else if (data?.verifie) {
        toast.success(`FINESS vérifié : ${data.raison_sociale || 'structure trouvée'}.`);
        await recharger();
      } else if (data?.revue_manuelle) {
        toast.warning(data?.motif || 'FINESS trouvé, mais le lien avec votre établissement doit être vérifié manuellement.');
        await recharger();
      } else {
        toast.error("Cet établissement n'est pas actif dans l'Annuaire Santé.");
        await recharger();
      }
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur lors de la vérification FINESS.');
    } finally {
      setFinessLoading(false);
    }
  };

  // ── Représentant : pièce d'identité ───────────────────────────────────────
  const verifierPiece = async () => {
    if (!user || !pieceFile) return;
    if (pieceLockRef.current) return;
    if (!nom.trim() || !prenom.trim()) {
      toast.error('Veuillez renseigner le prénom et le nom du représentant.');
      return;
    }
    const validation = await verifierFichierDocument(pieceFile);
    if (validation.ok === false) {
      toast.error(validation.message);
      return;
    }
    pieceLockRef.current = true;
    setPieceLoading(true);
    try {
      const mime = validation.mime;
      const path = `${user.id}/representant-piece-${Date.now()}.${validation.extension}`;
      const { error: upErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, pieceFile, { upsert: false, contentType: mime });
      if (upErr) throw upErr;

      const { error: updErr } = await supabase
        .from('etablissements')
        .update({
          representant_nom: nom.trim(),
          representant_prenom: prenom.trim() || null,
          representant_piece_s3_key: path,
          representant_piece_type_mime: mime,
          representant_piece_type_document: typeDoc,
        })
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

  // ── Justificatif de fonction (non-dirigeant) ──────────────────────────────
  const verifierJustificatif = async () => {
    if (!user || !justifFile) return;
    if (justifLockRef.current) return;
    const validation = await verifierFichierDocument(justifFile);
    if (validation.ok === false) {
      toast.error(validation.message);
      return;
    }
    justifLockRef.current = true;
    setJustifLoading(true);
    try {
      const mime = validation.mime;
      const path = `${user.id}/justificatif-fonction-${Date.now()}.${validation.extension}`;
      const { error: upErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, justifFile, { upsert: false, contentType: mime });
      if (upErr) throw upErr;

      const { error: updErr } = await supabase
        .from('etablissements')
        .update({
          justificatif_fonction_s3_key: path,
          justificatif_fonction_type_mime: mime,
          justificatif_fonction_type: justifType,
        })
        .eq('id', user.id);
      if (updErr) throw updErr;

      const { data, error } = await supabase.functions.invoke('verify-justificatif-fonction', {
        body: { etablissement_id: user.id },
      });
      if (error) { toast.error(await messageErreurEdgeFn(error, "Le justificatif n'a pas pu être vérifié. Vérifiez qu'il mentionne bien votre nom et votre établissement, et qu'il est lisible.")); return; }

      if (data?.justificatif_verifie) {
        toast.success('Justificatif de fonction validé — rattachement confirmé.');
      } else if (data?.verdict === 'REJETE') {
        toast.error(data?.motif || "Le document n'a pas pu être validé comme justificatif de fonction.");
      } else if (data?.etablissement_correspond === false) {
        toast.error("Le document ne mentionne pas clairement votre établissement.");
      } else if (data?.nom_correspond === false) {
        toast.error("Le document ne mentionne pas la personne déclarée comme représentant.");
      } else {
        toast('Document reçu. Vérification en cours.');
      }
      setJustifFile(null);
      await recharger();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur lors de la vérification du justificatif.');
    } finally {
      justifLockRef.current = false;
      setJustifLoading(false);
    }
  };

  // ── E-mail professionnel ──────────────────────────────────────────────────
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

  if (loading) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  const finessOk = !!etab?.finess_verifie;
  const identiteOk = !!etab?.representant_identite_verifiee;
  const justifOk = !!etab?.justificatif_fonction_verifie;
  const estDirigeant = etab?.rattachement_methode === 'AUTO_DIRIGEANT';
  const emailOk = !!etab?.email_contact_verifie;
  const rattachOk = !!etab?.rattachement_verifie;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center gap-3">
          <BoutonY2K variant="ghost" size="sm" onClick={() => navigate(-1)} aria-label="Retour">
            <ArrowLeft className="h-5 w-5" />
          </BoutonY2K>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <Shield className="h-5 w-5 text-primary" /> Vérification de votre établissement
            </h1>
            <p className="text-xs text-muted-foreground">
              Requise pour publier des missions. Vérifiez votre structure (FINESS) et le rattachement de votre représentant.
            </p>
          </div>
        </div>

        {/* Statut global de rattachement */}
        <div className={`rounded-xl border-2 p-4 flex items-start gap-3 ${rattachOk ? 'border-success/30 bg-success/5' : 'border-amber-200 bg-amber-50'}`}>
          {rattachOk ? <CheckCircle2 className="h-6 w-6 text-success shrink-0 mt-0.5" /> : <Clock className="h-6 w-6 text-amber-600 shrink-0 mt-0.5" />}
          <div>
            <p className="font-semibold text-foreground">
              {rattachOk ? 'Établissement vérifié' : 'Vérification en attente'}
            </p>
            <p className="text-sm text-muted-foreground mt-1">
              {rattachOk
                ? `Rattachement validé — ${LIBELLE_METHODE[etab?.rattachement_methode || 'ADMIN'] || 'validé'}. Vous pouvez publier des missions.`
                : "Vérifiez l'identité du représentant. S'il est le dirigeant déclaré, le rattachement est automatique ; sinon, ajoutez un justificatif de fonction."}
            </p>
          </div>
        </div>

        {/* 1. FINESS */}
        <section className="rounded-xl border border-border bg-card p-4 space-y-3">
          <p className="text-sm font-semibold text-foreground flex items-center gap-2">
            <Building2 className="h-4 w-4 text-primary" /> 1. Numéro FINESS
            {finessOk && <CheckCircle2 className="h-4 w-4 text-success" />}
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

        {/* 2. Représentant */}
        <section className="rounded-xl border border-border bg-card p-4 space-y-3">
          <p className="text-sm font-semibold text-foreground flex items-center gap-2">
            <UserCheck className="h-4 w-4 text-primary" /> 2. Représentant de l'établissement
            {identiteOk && <CheckCircle2 className="h-4 w-4 text-success" />}
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
                  accept="application/pdf,image/jpeg,image/png,image/webp"
                  onChange={async e => {
                    const selected = e.target.files?.[0] || null;
                    if (!selected) { setPieceFile(null); return; }
                    const validation = await verifierFichierDocument(selected);
                    if (validation.ok === false) { setPieceFile(null); toast.error(validation.message); e.target.value = ''; return; }
                    setPieceFile(selected);
                  }}
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

        {/* 3. Justificatif de fonction (non-dirigeant) */}
        <section className="rounded-xl border border-border bg-card p-4 space-y-3">
          <p className="text-sm font-semibold text-foreground flex items-center gap-2">
            <FileText className="h-4 w-4 text-primary" /> 3. Justificatif de fonction
            {(justifOk || estDirigeant) && <CheckCircle2 className="h-4 w-4 text-success" />}
          </p>
          {estDirigeant ? (
            <p className="text-sm text-muted-foreground">
              Vous êtes le dirigeant déclaré (INSEE) — rattachement automatique. Aucun justificatif nécessaire.
            </p>
          ) : justifOk ? (
            <p className="text-sm text-muted-foreground">
              Justificatif de fonction vérifié — rattachement confirmé.
            </p>
          ) : (
            <>
              <p className="text-xs text-muted-foreground">
                Si vous n'êtes pas le dirigeant déclaré (RH, chef de service, délégataire), téléversez un justificatif qui vous rattache à l'établissement. Il est vérifié automatiquement par IA (votre nom + l'établissement + l'authenticité du document).
              </p>
              <div>
                <Label htmlFor="justif-type">Type de justificatif</Label>
                <select
                  id="justif-type"
                  value={justifType}
                  onChange={e => setJustifType(e.target.value as typeof justifType)}
                  className="block w-full mt-1 rounded-lg border border-border bg-background px-3 py-2 text-sm"
                >
                  <option value="DELEGATION_SIGNATURE">Délégation de signature / pouvoir</option>
                  <option value="DECISION_NOMINATION">Décision de nomination</option>
                  <option value="ATTESTATION_EMPLOYEUR">Attestation employeur (revue manuelle)</option>
                  <option value="FICHE_POSTE">Fiche de poste (revue manuelle)</option>
                  <option value="CONTRAT_TRAVAIL">Contrat de travail (revue manuelle)</option>
                </select>
              </div>
              <div>
                <Label htmlFor="justif-file" className="sr-only">Justificatif de fonction</Label>
                <input
                  id="justif-file"
                  type="file"
                  accept="application/pdf,image/jpeg,image/png,image/webp"
                  onChange={async e => {
                    const selected = e.target.files?.[0] || null;
                    if (!selected) { setJustifFile(null); return; }
                    const validation = await verifierFichierDocument(selected);
                    if (validation.ok === false) { setJustifFile(null); toast.error(validation.message); e.target.value = ''; return; }
                    setJustifFile(selected);
                  }}
                  className="block w-full text-sm text-foreground file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer"
                />
                {justifFile && (
                  <p className="text-xs text-muted-foreground mt-1">
                    {justifFile.name} ({(justifFile.size / 1024).toFixed(0)} Ko)
                  </p>
                )}
              </div>
              <BoutonY2K onClick={verifierJustificatif} disabled={!justifFile || justifLoading} className="gap-2">
                {justifLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
                Vérifier le justificatif
              </BoutonY2K>
              {!identiteOk && (
                <p className="text-xs text-amber-600">Vérifiez d'abord la pièce d'identité du représentant (étape 2).</p>
              )}
            </>
          )}
        </section>

        {/* 4. E-mail de contact (optionnel) */}
        <section className="rounded-xl border border-border bg-card p-4 space-y-3">
          <p className="text-sm font-semibold text-foreground flex items-center gap-2">
            <Mail className="h-4 w-4 text-primary" /> 4. E-mail de contact
            {emailOk && <CheckCircle2 className="h-4 w-4 text-success" />}
          </p>
          {emailOk ? (
            <p className="text-sm text-muted-foreground">
              Confirmé — <strong>{etab?.email_contact}</strong>.
            </p>
          ) : (
            <>
              <p className="text-xs text-muted-foreground">
                Confirmez l'e-mail de contact de l'établissement (recommandé pour recevoir les notifications). Un lien de validation (valable 24h) vous sera envoyé.
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

        {!rattachOk && (
          <div className="rounded-xl border border-border bg-muted/20 p-3 flex items-start gap-3">
            <AlertTriangle className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" />
            <p className="text-xs text-muted-foreground">
              Si aucune de ces méthodes n'aboutit, un administrateur Jolene validera manuellement votre rattachement après examen de votre dossier.
            </p>
          </div>
        )}
      </div>
    </LayoutApp>
  );
}
