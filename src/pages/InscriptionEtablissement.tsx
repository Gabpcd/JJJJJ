import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Eye, EyeOff, Check, AlertCircle, CheckCircle2, Loader2, ShieldCheck, ShieldAlert, ShieldX } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { handleError } from '@/lib/handleError';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { SelectTypeEtablissement } from '@/components/SelectTypeEtablissement';
import { validerSiret } from '@/lib/luhn';
import { supabase } from '@/integrations/supabase/client';
import { FooterLegal } from '@/components/FooterLegal';
import { AuthLayout } from '@/components/AuthLayout';
import { CaptchaTurnstile } from '@/components/CaptchaTurnstile';
import { SwitchTypeInscription } from '@/components/inscription/SwitchTypeInscription';

interface SiretInseeResult {
  statut: 'VERIFIE' | 'ALERTE' | 'INTROUVABLE';
  raison_sociale: string | null;
  est_actif: boolean;
  est_sante: boolean;
  est_public: boolean;
  code_naf: string | null;
  libelle_naf: string | null;
  categorie_juridique: string | null;
  message: string;
}

export default function InscriptionEtablissement() {
  usePageTitle('Inscription Établissement');
  const navigate = useNavigate();
  const { inscriptionEtablissement } = useAuth();
  const { afficherNotification } = useNotification();

  // J5.D.2 — Capturer ?ref=ETB-XXXXXX et le stocker en sessionStorage
  // pour pré-remplir le champ "Code parrainage" dans la page parrainage post-inscription.
  useEffect(() => {
    try {
      const ref = new URLSearchParams(window.location.search).get('ref');
      if (ref && /^ETB-[A-Z0-9]{4,16}$/i.test(ref)) {
        sessionStorage.setItem('jolene.parrainage_etab_code', ref.toUpperCase());
      }
    } catch { /* noop */ }
  }, []);
  const [etape, setEtape] = useState(1);
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [cgu, setCgu] = useState(false);
  const [cgv, setCgv] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);

  const [form, setForm] = useState({
    email: '', motDePasse: '', confirmMdp: '',
    nom: '', siret: '', finess: '', type: '',
    rue: '', ville: '', codePostal: '', departement: '',
    emailContact: '', telephoneContact: '',
    numeroLicence: '',
    lat: null as number | null, lng: null as number | null,
  });

  const [siretValidation, setSiretValidation] = useState<{ valide: boolean; message: string } | null>(null);
  const [inseeCheck, setInseeCheck] = useState<SiretInseeResult | null>(null);
  const [inseeLoading, setInseeLoading] = useState(false);

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));
  const etape1Valide = form.email && form.motDePasse.length >= 8 && form.motDePasse === form.confirmMdp && cgu && cgv;
  const siretEstValide = siretValidation?.valide === true;
  // Funnel 2 étapes : étape 2 = identité établissement fusionnée (les anciennes
  // « Votre établissement » + « Coordonnées » réunies en un seul écran court).
  // N'exige que les 4 champs réellement requis par register-etablissement :
  // nom, SIRET (Luhn), type et ville. Rue / code postal / département / email
  // de contact / téléphone / géolocalisation sont déférés au tableau de bord
  // (le backend les accepte vides ; email_contact retombe sur l'email du compte).
  const etape2Valide = !!(form.nom && siretEstValide && form.type && form.ville);

  // Cohérence live : le nom saisi correspond-il à la raison sociale officielle
  // du SIRET (INSEE) ? Sinon on avertit pour que l'utilisateur corrige avant de
  // valider (le backend bloquera sinon en validation manuelle).
  const coherenceNom = useMemo<null | 'OK' | 'PARTIEL' | 'INCOHERENT'>(() => {
    const rs = inseeCheck?.raison_sociale;
    if (!rs || !form.nom) return null;
    const norm = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/\b(sas|sasu|sarl|sa|eurl|sci|scp|selarl|selas|snc|gie|association|asso|groupe|clinique|centre|hopital|ehpad|cabinet|pharmacie|ste|societe)\b/g, '')
      .replace(/[^a-z0-9]+/g, ' ').trim();
    const na = norm(form.nom), nb = norm(rs);
    if (!na || !nb) return null;
    if (na === nb || na.includes(nb) || nb.includes(na)) return 'OK';
    const sa = new Set(na.split(' ').filter(w => w.length >= 3));
    const sb = new Set(nb.split(' ').filter(w => w.length >= 3));
    if ([...sa].some(w => sb.has(w))) return 'PARTIEL';
    return 'INCOHERENT';
  }, [form.nom, inseeCheck?.raison_sociale]);

  const verifierSiretInsee = useCallback(async (siret: string) => {
    if (siret.length !== 14) return;
    const luhn = validerSiret(siret);
    if (!luhn.valide) return;

    setInseeLoading(true);
    setInseeCheck(null);
    try {
      const { data, error } = await supabase.functions.invoke('verify-siret', {
        body: { siret },
      });
      if (error) throw error;
      setInseeCheck(data as SiretInseeResult);
      // Auto-fill nom if empty and we got a raison sociale
      if (data?.raison_sociale && !form.nom) {
        maj('nom', data.raison_sociale);
      }
    } catch (err) {
      if (import.meta.env.DEV) console.warn('Vérification INSEE échouée:', err);
      setInseeCheck({
        statut: 'ALERTE',
        raison_sociale: null,
        est_actif: false,
        est_sante: false,
        est_public: false,
        code_naf: null,
        libelle_naf: null,
        categorie_juridique: null,
        message: 'Service de vérification temporairement indisponible',
      });
    } finally {
      setInseeLoading(false);
    }
  }, [form.nom]);

  const handleSiretBlur = () => {
    if (form.siret.length > 0) {
      const result = validerSiret(form.siret);
      setSiretValidation(result);
      if (result.valide) {
        verifierSiretInsee(form.siret);
      }
    } else {
      setSiretValidation(null);
      setInseeCheck(null);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await inscriptionEtablissement({ ...form, turnstileToken });
      // PII (email) hors URL : sessionStorage évite leak via historique navigateur
      try { sessionStorage.setItem('inscription_email', form.email); } catch { /* sessionStorage indisponible */ }
      navigate('/inscription/succes?role=etab');
    } catch (err) {
      if (!gererErreurSupabase(err, () => handleSubmit(e))) {
        handleError(err, 'inscription établissement');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AuthLayout backTo="/connexion">
      <div className="card-base max-w-lg w-full">
        <div className="flex items-center justify-center gap-2 mb-6">
          <HeartPulse className="h-7 w-7 text-rose" />
          <span className="text-xl font-bold text-rose">Jolene</span>
        </div>
        <h1 className="text-xl font-bold text-foreground text-center mb-2">Inscription Établissement</h1>
        <SwitchTypeInscription actif="etablissement" />

        <div className="flex items-center justify-center gap-0 mb-2">
          {[1, 2].map((n) => (
            <React.Fragment key={n}>
              {n > 1 && <div className={`h-1 w-12 mx-1 rounded-full ${etape >= n ? 'bg-primary' : 'bg-muted'}`} />}
              <div className={`h-9 w-9 rounded-full flex items-center justify-center text-sm font-bold ${etape >= n ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>
                {etape > n ? <Check className="h-4 w-4" /> : n}
              </div>
            </React.Fragment>
          ))}
        </div>
        <p className="text-center text-xs text-muted-foreground mb-6">
          Étape {etape}/2 — {etape === 1 ? 'Identifiants' : 'Votre établissement'} · ≈ 2 minutes
        </p>

        <form onSubmit={handleSubmit}>
          {etape === 1 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 1 — Vos identifiants</p>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Email *</span>
                <input type="email" autoComplete="email" value={form.email} onChange={e => maj('email', e.target.value)} className="input-base" required />
              </label>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe *</span>
                <div className="relative">
                  <input type={afficherMdp ? 'text' : 'password'} value={form.motDePasse} onChange={e => maj('motDePasse', e.target.value)} placeholder="Minimum 8 caractères" className="input-base pr-10" required minLength={8} />
                  <button
                    type="button"
                    onClick={() => setAfficherMdp(!afficherMdp)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground"
                    aria-label={afficherMdp ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
                    aria-pressed={afficherMdp}
                  >
                    {afficherMdp ? <EyeOff className="h-4 w-4" aria-hidden="true" /> : <Eye className="h-4 w-4" aria-hidden="true" />}
                  </button>
                </div>
              </label>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Confirmer *</span>
                <input type="password" autoComplete="new-password" value={form.confirmMdp} onChange={e => maj('confirmMdp', e.target.value)} className="input-base" required minLength={8} />
                {form.confirmMdp && form.confirmMdp !== form.motDePasse && <p className="text-xs text-destructive mt-1" role="alert">Les mots de passe ne correspondent pas</p>}
              </label>
              <label className="flex items-start gap-2 cursor-pointer">
                <input type="checkbox" checked={cgu} onChange={e => setCgu(e.target.checked)} className="mt-1 h-4 w-4 rounded accent-primary" />
                <span className="text-sm text-muted-foreground">J'accepte les <a href="/cgu" target="_blank" rel="noopener noreferrer" className="text-primary underline font-medium">Conditions Générales d'Utilisation</a> et la <a href="/confidentialite" target="_blank" rel="noopener noreferrer" className="text-primary underline font-medium">Politique de confidentialité</a> *</span>
              </label>
              <label className="flex items-start gap-2 cursor-pointer">
                <input type="checkbox" checked={cgv} onChange={e => setCgv(e.target.checked)} className="mt-1 h-4 w-4 rounded accent-primary" />
                <span className="text-sm text-muted-foreground">J'accepte les <a href="/cgv" target="_blank" rel="noopener noreferrer" className="text-primary underline font-medium">Conditions Générales de Vente</a> *</span>
              </label>
              <button type="button" onClick={() => setEtape(2)} disabled={!etape1Valide} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed">Continuer</button>
            </div>
          )}

          {etape === 2 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 2 — Votre établissement</p>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Nom de l'établissement *</label>
                <input value={form.nom} onChange={e => maj('nom', e.target.value)} className={`input-base ${coherenceNom === 'INCOHERENT' ? 'border-amber-500' : ''}`} required />
                {coherenceNom === 'INCOHERENT' && inseeCheck?.raison_sociale && (
                  <div className="mt-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-2">
                    <p>⚠️ Ce nom ne correspond pas à la raison sociale officielle du SIRET : <strong>{inseeCheck.raison_sociale}</strong>.</p>
                    <p className="mt-0.5">Corrigez-le, ou utilisez le nom officiel. Sinon votre compte passera en validation manuelle (24-48 h).</p>
                    <button type="button" onClick={() => maj('nom', inseeCheck!.raison_sociale!)} className="mt-1 text-primary underline font-medium">
                      Utiliser « {inseeCheck.raison_sociale} »
                    </button>
                  </div>
                )}
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">SIRET * (14 chiffres)</label>
                  <div className="relative">
                    <input value={form.siret} onChange={e => { maj('siret', e.target.value.replace(/\D/g, '').slice(0, 14)); setSiretValidation(null); setInseeCheck(null); }} onBlur={handleSiretBlur} className={`input-base pr-10 ${siretValidation && !siretValidation.valide ? 'border-destructive' : ''} ${siretEstValide ? 'border-green-500' : ''}`} required />
                    {inseeLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground animate-spin" />}
                    {!inseeLoading && siretEstValide && <CheckCircle2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-green-500" />}
                    {!inseeLoading && siretValidation && !siretValidation.valide && <AlertCircle className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-destructive" />}
                  </div>
                  {siretValidation && !siretValidation.valide && <p className="text-xs text-destructive mt-1">{siretValidation.message}</p>}
                </div>
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">{form.type === 'PHARMACIE_OFFICINE' ? 'N° Licence' : 'FINESS (9 chiffres)'}</label><input value={form.type === 'PHARMACIE_OFFICINE' ? form.numeroLicence : form.finess} onChange={e => form.type === 'PHARMACIE_OFFICINE' ? maj('numeroLicence', e.target.value) : maj('finess', e.target.value.replace(/\D/g, '').slice(0, 9))} className="input-base" /></div>
              </div>

              {/* Résultat vérification INSEE */}
              {inseeCheck && (
                <div className={`rounded-lg border p-3 flex items-start gap-3 ${
                  inseeCheck.statut === 'VERIFIE' ? 'bg-green-50 border-green-200 dark:bg-green-950/20 dark:border-green-800' :
                  inseeCheck.statut === 'ALERTE' ? 'bg-amber-50 border-amber-200 dark:bg-amber-950/20 dark:border-amber-800' :
                  'bg-red-50 border-red-200 dark:bg-red-950/20 dark:border-red-800'
                }`}>
                  {inseeCheck.statut === 'VERIFIE' && <ShieldCheck className="h-5 w-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" />}
                  {inseeCheck.statut === 'ALERTE' && <ShieldAlert className="h-5 w-5 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />}
                  {inseeCheck.statut === 'INTROUVABLE' && <ShieldX className="h-5 w-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" />}
                  <div>
                    <p className={`text-sm font-medium ${
                      inseeCheck.statut === 'VERIFIE' ? 'text-green-800 dark:text-green-300' :
                      inseeCheck.statut === 'ALERTE' ? 'text-amber-800 dark:text-amber-300' :
                      'text-red-800 dark:text-red-300'
                    }`}>{inseeCheck.message}</p>
                    {inseeCheck.statut === 'VERIFIE' && (
                      <p className="text-xs text-green-600 dark:text-green-400 mt-1">✅ Votre établissement pourra publier des missions immédiatement.</p>
                    )}
                    {inseeCheck.statut === 'ALERTE' && (
                      <p className="text-xs text-amber-600 dark:text-amber-400 mt-1">🟡 Votre inscription sera en attente de validation par Jolene (24-48h).</p>
                    )}
                    {inseeCheck.statut === 'INTROUVABLE' && (
                      <p className="text-xs text-red-600 dark:text-red-400 mt-1">❌ Veuillez vérifier votre numéro SIRET. Vous pouvez tout de même vous inscrire, une vérification manuelle sera effectuée.</p>
                    )}
                  </div>
                </div>
              )}

              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Type d'établissement *</label><SelectTypeEtablissement value={form.type} onChange={v => maj('type', v)} /></div>
              {form.type !== 'PHARMACIE_OFFICINE' && (
                <p className="text-xs text-muted-foreground">ℹ️ Le plafond Loi Rist s'applique aux taux horaires en CDD.</p>
              )}
              {/* Seule la ville est requise ici. L'adresse complète (rue / code
                  postal / département), l'email et le téléphone de contact ainsi
                  que la géolocalisation sont déférés au tableau de bord pour
                  alléger le funnel. register-etablissement accepte ces champs
                  vides (rue → « Non renseigné », CP → « 00000 », email_contact →
                  email du compte). */}
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Ville *</label>
                <input value={form.ville} onChange={e => maj('ville', e.target.value)} placeholder="Ville" className="input-base" autoComplete="address-level2" required />
              </div>
              <CaptchaTurnstile className="flex justify-center pt-2" onVerify={setTurnstileToken} onExpire={() => setTurnstileToken(null)} onError={() => setTurnstileToken(null)} />
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEtape(1)} className="btn-secondary flex-1">Retour</button>
                <button type="submit" disabled={!etape2Valide || submitting} className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2">
                  {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
                  {submitting ? 'Création…' : 'Créer le compte'}
                </button>
              </div>
            </div>
          )}
        </form>

        <p className="text-center mt-6 text-sm text-muted-foreground">
          Déjà un compte ? <a href="/connexion" className="text-primary hover:underline font-medium">Se connecter</a>
        </p>
      </div>
      <FooterLegal />
    </AuthLayout>
  );
}
