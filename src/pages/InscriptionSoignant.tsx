import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect, useCallback } from 'react';
import * as Sentry from '@sentry/react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Eye, EyeOff, Check, Loader2, ShieldCheck, ShieldAlert } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { getLabelProfession } from '@/lib/constantes';
import { useNotification } from '@/contexts/NotificationContext';
import { mapperErreurInscription, estRefusInscriptionAttendu, type ErreurInscriptionMappee } from '@/lib/erreurs';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { ErreurInscription } from '@/components/inscription/ErreurInscription';
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';
import { CaptchaTurnstile, TURNSTILE_REQUIRED } from '@/components/CaptchaTurnstile';
import { SelectProfession } from '@/components/SelectProfession';
import { DeclarationEtudiant, FORMATIONS_ETUDIANT } from '@/components/inscription/DeclarationEtudiant';
import { FooterLegal } from '@/components/FooterLegal';
import { AuthLayout } from '@/components/AuthLayout';
import { CONTRATS, PROFESSIONS_SANS_RPPS, PROFESSIONS_RPPS_REQUIS, PROFESSIONS_NON_LIBERAL } from '@/lib/constantes';
import { Checkbox } from '@/components/ui/checkbox';
import { logger } from '@/lib/logger';
import { BoutonProSanteConnect } from '@/components/BoutonProSanteConnect';
import { ApercuMarche } from '@/components/inscription/ApercuMarche';
import { SwitchTypeInscription } from '@/components/inscription/SwitchTypeInscription';


function JaugeForce({ motDePasse }: { motDePasse: string }) {
  let force = 0;
  if (motDePasse.length >= 8) force++;
  if (/[A-Z]/.test(motDePasse)) force++;
  if (/[0-9]/.test(motDePasse)) force++;
  if (/[^A-Za-z0-9]/.test(motDePasse)) force++;
  const labels = ['', 'Faible', 'Moyen', 'Fort', 'Très fort'];
  const colors = ['', 'bg-destructive', 'bg-warning', 'bg-primary', 'bg-success'];
  if (!motDePasse) return null;
  return (
    <div className="mt-1.5">
      <div className="flex gap-1" aria-hidden="true">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className={`h-1 flex-1 rounded-full ${i <= force ? colors[force] : 'bg-muted'}`} />
        ))}
      </div>
      <p className="text-[10px] text-muted-foreground mt-0.5" role="status" aria-live="polite">Force du mot de passe : {labels[force]}</p>
    </div>
  );
}

const EMAIL_REGEX = /^[^\s@]{1,64}@[^\s@]{1,255}\.[a-z]{2,}$/i;

function ExerciceTypeSection({ profession, estSalarieEtablissement, onChangeSalarie }: { profession: string; estSalarieEtablissement: boolean | null; onChangeSalarie: (v: boolean) => void }) {
  const { uniqueType } = useTypesExerciceAutorises(profession);

  if (uniqueType) {
    return (
      <div>
        <label className="text-sm font-medium text-foreground mb-1.5 block">Type d'exercice</label>
        <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
          <p className="text-sm text-foreground">
            En tant que <strong>{getLabelProfession(profession)}</strong>, ton type d'exercice est automatiquement défini comme <strong>{uniqueType === 'SALARIE' ? 'salarié' : uniqueType === 'LIBERAL' ? 'libéral' : 'mixte'}</strong>.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div>
      <label className="text-sm font-medium text-foreground mb-1.5 block">Es-tu actuellement salarié(e) d'un établissement de santé ?</label>
      <div className="flex gap-3 mt-1">
        <button type="button" onClick={() => onChangeSalarie(true)} className={`flex-1 py-2.5 px-4 rounded-xl border text-sm font-medium transition-colors ${estSalarieEtablissement === true ? 'border-primary bg-primary/5 text-primary' : 'border-input text-muted-foreground hover:bg-accent/50'}`}>Oui</button>
        <button type="button" onClick={() => onChangeSalarie(false)} className={`flex-1 py-2.5 px-4 rounded-xl border text-sm font-medium transition-colors ${estSalarieEtablissement === false ? 'border-primary bg-primary/5 text-primary' : 'border-input text-muted-foreground hover:bg-accent/50'}`}>Non</button>
      </div>
      {estSalarieEtablissement === true && (
        <div className="mt-3 p-3 bg-primary/5 border border-primary/20 rounded-xl">
          <p className="text-xs text-foreground">ℹ️ Tu pourras effectuer des missions sur Jolene en complément de ton activité salariée. Vérifie que ton contrat de travail n'inclut pas de clause d'exclusivité.</p>
        </div>
      )}
    </div>
  );
}

export default function InscriptionSoignant() {
  usePageTitle('Inscription Soignant');
  const navigate = useNavigate();
  const { inscriptionSoignant } = useAuth();
  const { afficherNotification } = useNotification();

  // J5.D.1 — Capturer ?ref=CODE et le stocker en sessionStorage pour
  // pré-remplir le champ "Code parrainage" dans le wizard profil après inscription.
  useEffect(() => {
    try {
      const q = new URLSearchParams(window.location.search);
      const ref = q.get('ref') || q.get('parrain');
      if (ref && /^[A-Z0-9-]{4,16}$/i.test(ref)) {
        sessionStorage.setItem('jolene.parrainage_code', ref.toUpperCase());
      }
    } catch { /* noop */ }
  }, []);
  const [etape, setEtape] = useState(1);
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [cgu, setCgu] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);
  const [erreurInscription, setErreurInscription] = useState<ErreurInscriptionMappee | null>(null);

  const champsAHighlighter = new Set(erreurInscription?.champs_highlight ?? []);
  const classeChampErreur = (champ: string) => champsAHighlighter.has(champ) ? 'border-destructive ring-1 ring-destructive/30' : '';

  const [form, setForm] = useState({
    email: '', motDePasse: '', confirmMdp: '',
    prenom: '', nom: '', telephone: '', dateNaissance: '',
    profession: '', typesContrat: [] as string[], rpps: '', rayon: 30,
    lat: null as number | null, lng: null as number | null,
    estSalarieEtablissement: null as boolean | null,
    estEtudiant: false, scolariteFormation: '', scolariteAnnee: '',
  });

  // RPPS verification state
  const [rppsVerifiant, setRppsVerifiant] = useState(false);
  const [rppsResultat, setRppsResultat] = useState<{ trouve: boolean; nom_affiche?: string; specialite_code?: string | null; specialite_label?: string | null; fhir_indisponible?: boolean; profession_api?: string; profession_correspond?: boolean | null } | null>(null);
  const [rppsPreRempli, setRppsPreRempli] = useState(false);
  // Session E-1 : un RPPS non trouvé dans l'annuaire ne doit plus éjecter le
  // soignant du funnel — il peut continuer avec une vérification manuelle sous
  // 24 h (même traitement backend que fhir_indisponible : compte créé avec
  // rpps_verifie=false, revue via Admin → Modération → Identité).
  const [rppsVerifManuelle, setRppsVerifManuelle] = useState(false);

  const normaliser = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().trim();

  const rppsCorrespond = (): boolean | null => {
    if (!rppsResultat || !rppsResultat.trouve) return null;
    // nom_affiche is already built from the response — just check against form
    const nomApi = normaliser(rppsResultat.nom_affiche || '');
    const nomForm = normaliser(form.nom);
    const prenomForm3 = normaliser(form.prenom).slice(0, 3);
    const partiesApi = (rppsResultat.nom_affiche || '').split(/[\s-]+/);
    const nomMatch = nomApi.includes(nomForm) || nomForm.includes(nomApi);
    const prenomMatch = partiesApi.some(p => normaliser(p).slice(0, 3) === prenomForm3);
    return nomMatch && prenomMatch;
  };

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const toggleContrat = (valeur: string) => {
    setForm(prev => {
      const current = prev.typesContrat;
      const next = current.includes(valeur)
        ? current.filter(v => v !== valeur)
        : [...current, valeur];
      return { ...prev, typesContrat: next };
    });
  };

  // Auto-décocher LIBERAL/VACATION si la profession ne peut pas exercer en libéral
  const peutEtreLiberal = !!form.profession && !PROFESSIONS_NON_LIBERAL.includes(form.profession);
  useEffect(() => {
    if (!form.profession) return;
    if (peutEtreLiberal) return;
    setForm(prev => {
      const cleaned = prev.typesContrat.filter(v => v !== 'LIBERAL' && v !== 'VACATION');
      if (cleaned.length === prev.typesContrat.length) return prev;
      return { ...prev, typesContrat: cleaned };
    });
  }, [form.profession, peutEtreLiberal]);

  // Vider le RPPS si la profession ne le requiert pas (AS / AES)
  useEffect(() => {
    if (!form.profession) return;
    if (PROFESSIONS_SANS_RPPS.includes(form.profession) && form.rpps) {
      setForm(prev => ({ ...prev, rpps: '' }));
    }
  }, [form.profession]);

  // L1: Date de naissance obligatoire + validation email + 18+ check
  const emailValide = EMAIL_REGEX.test(form.email.trim());
  const etape1Valide = emailValide && form.motDePasse.length >= 8 && form.motDePasse === form.confirmMdp && cgu;
  const dateNaissanceRequise = !form.dateNaissance;
  const dateNaissanceMajeur = (() => {
    if (!form.dateNaissance) return false;
    const d = new Date(form.dateNaissance);
    if (isNaN(d.getTime())) return false;
    const ageMs = Date.now() - d.getTime();
    return ageMs >= 18 * 365.25 * 86400000;
  })();
  const rppsRequis = form.profession && !PROFESSIONS_SANS_RPPS.includes(form.profession);
  // RPPS OBLIGATOIRE (saisie requise) seulement pour les professions « Ordre
  // historique » ; pour les autres à RPPS, il reste optionnel (diplôme à la place).
  const rppsObligatoireInscription = !!form.profession && PROFESSIONS_RPPS_REQUIS.includes(form.profession);
  // Téléphone OBLIGATOIRE à l'inscription : donnée opérationnelle critique (un étab
  // doit pouvoir joindre le soignant pour une mission urgente). Même pattern que l'input.
  const telephoneValide = /^[+]?[0-9\s]{8,15}$/.test(form.telephone.trim());
  const rppsMatch = rppsCorrespond();
  // Mismatch de profession (RPPS d'une autre profession) = bloquant, au même titre que nom/prénom.
  const rppsProfessionMismatch = !!rppsResultat?.trouve && rppsResultat?.profession_correspond === false;
  const rppsBloquant = rppsRequis && form.rpps.length === 11 && rppsResultat && !rppsResultat.fhir_indisponible && (!rppsResultat.trouve || rppsMatch === false || rppsProfessionMismatch) && !rppsVerifManuelle;
  const etape2Valide = form.prenom && form.nom && form.profession && form.typesContrat.length > 0 && !rppsBloquant && !dateNaissanceRequise && dateNaissanceMajeur && telephoneValide && (!TURNSTILE_REQUIRED || !!turnstileToken) && (!rppsObligatoireInscription || form.rpps.length === 11);

  // Verify RPPS when 11 digits entered
  useEffect(() => {
    if (form.rpps.length !== 11 || !form.prenom || !form.nom) {
      setRppsResultat(null);
      setRppsPreRempli(false);
      setRppsVerifManuelle(false);
      return;
    }
    const controller = new AbortController();
    const timeout = setTimeout(async () => {
      setRppsVerifiant(true);
      try {
        const rppsValue = form.rpps;
        const response = await fetch(
          `${SUPABASE_URL}/functions/v1/verify-rpps`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
              'apikey': SUPABASE_PUBLISHABLE_KEY,
            },
            body: JSON.stringify({
              rpps: rppsValue,
              numero_rpps: rppsValue,
              prenom: form.prenom,
              nom: form.nom,
              profession: form.profession,
              turnstileToken,
            }),
            signal: controller.signal,
          }
        );

        const data = await response.json();
        if (controller.signal.aborted) return;
        logger.debug('RPPS response:', data);

        if (!response.ok) {
          const codeBackend = (data && typeof data === 'object' && 'code' in data) ? String(data.code) : 'RPPS_API_UNAVAILABLE';
          // Refus ATTENDU (captcha manquant 403, RPPS introuvable / format invalide
          // = saisie utilisateur) → breadcrumb seulement, pas d'issue Sentry.
          // On ne capture QUE les vraies anomalies (5xx, RPPS_API_UNAVAILABLE…).
          const refusAttendu = response.status === 403 ||
            ['RPPS_NOT_FOUND', 'RPPS_FORMAT_INVALID', 'RPPS_TRAITS_MISMATCH'].includes(codeBackend);
          if (refusAttendu) {
            Sentry.addBreadcrumb({ level: 'info', category: 'verify-rpps', message: `verify-rpps ${response.status} ${codeBackend} (refus attendu)` });
          } else {
            Sentry.captureException(new Error(`verify-rpps ${response.status}: ${data?.message || data?.error || 'unknown'}`), {
              tags: { type: 'verify_rpps_temps_reel', code: codeBackend, http_status: String(response.status) },
            });
          }
          setRppsResultat(data?.trouve === false ? { trouve: false } : null);
        } else if (data) {
          const nomAffiche = data.nom_api || data.nom || '';
          const prenomAffiche = data.prenom || data.prenom_api || '';
          const label = [prenomAffiche, nomAffiche].filter(Boolean).join(' ') || nomAffiche;
          const resultat = {
            trouve: !!data.trouve,
            nom_affiche: label,
            specialite_code: data.specialite_code ?? null,
            specialite_label: data.specialite_label ?? null,
            fhir_indisponible: !!data.fhir_indisponible,
            profession_api: data.profession_api ?? undefined,
            profession_correspond: data.profession_correspond ?? null,
          };
          setRppsResultat(resultat);
          if (data.trouve && !data.fhir_indisponible && (nomAffiche || prenomAffiche)) {
            setForm(prev => ({
              ...prev,
              ...(nomAffiche ? { nom: nomAffiche } : {}),
              ...(prenomAffiche ? { prenom: prenomAffiche } : {}),
            }));
            setRppsPreRempli(true);
          }
        } else {
          setRppsResultat({ trouve: false });
        }
      } catch (err: any) {
        if (err?.name === 'AbortError') return; // re-render cancellation, normal
        Sentry.captureException(err, {
          tags: { type: 'verify_rpps_temps_reel', code: 'NETWORK_ERROR' },
        });
        setRppsResultat(null);
      }
      if (!controller.signal.aborted) setRppsVerifiant(false);
    }, 500);
    return () => {
      clearTimeout(timeout);
      controller.abort();
    };
  }, [form.rpps, form.prenom, form.nom]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setErreurInscription(null);
    try {
      const formationLabel = FORMATIONS_ETUDIANT.find(f => f.valeur === form.scolariteFormation)?.label || form.scolariteFormation;
      const etudiantDetails = form.estEtudiant && form.scolariteFormation && form.scolariteAnnee
        ? `${formationLabel} — année ${form.scolariteAnnee} validée`
        : null;
      await inscriptionSoignant({ ...form, turnstileToken, est_etudiant: form.estEtudiant, etudiant_details: etudiantDetails });
      // PII (email) hors URL : sessionStorage évite leak via historique/referer
      // + profession pour l'aperçu marché de la page succès (Session E-2)
      try {
        sessionStorage.setItem('inscription_email', form.email);
        sessionStorage.setItem('inscription_profession', form.profession);
      } catch { /* sessionStorage indisponible */ }
      navigate('/inscription/succes?role=soignant');
    } catch (err) {
      if (gererErreurSupabase(err, () => handleSubmit(e))) {
        // Erreur réseau / session — gérée par l'helper, pas d'affichage local.
        return;
      }
      // Affichage inline avec code + action proposée.
      const erreurMappee = mapperErreurInscription(err);
      setErreurInscription(erreurMappee);
      // Sentry UNIQUEMENT pour les vraies anomalies. Un refus métier attendu
      // (e-mail/RPPS déjà utilisé, captcha, mot de passe faible…) est déjà
      // affiché clairement à l'utilisateur → pas d'issue Sentry (sinon le feed
      // se remplit de faux positifs).
      if (!estRefusInscriptionAttendu(erreurMappee.code)) {
        Sentry.captureException(err, {
          tags: { type: 'inscription_soignant', code: erreurMappee.code },
          extra: { champs_highlight: erreurMappee.champs_highlight },
        });
      }
      // Si l'erreur cible un champ d'étape 1 mais on est en étape 2,
      // remonter à l'étape 1 pour rendre le champ visible.
      if (erreurMappee.champs_highlight?.some(c => c === 'email' || c === 'motDePasse') && etape !== 1) {
        setEtape(1);
      }
      // Pas de toast : l'Alert inline juste au-dessus du bouton submit
      // est plus actionnable (boutons "Se connecter" / "Réessayer" / etc.).
    } finally {
      setSubmitting(false);
    }
  };

  const handleSeConnecter = () => {
    try { sessionStorage.setItem('connexion_email', form.email); } catch { /* noop */ }
    navigate('/connexion');
  };

  const handleRetry = () => {
    setErreurInscription(null);
    // Re-soumettre le formulaire en simulant un submit.
    const formEl = document.querySelector('form');
    if (formEl) formEl.requestSubmit();
  };

  return (
    <AuthLayout backTo="/connexion">
      <div className="card-base max-w-lg w-full">
        <div className="flex items-center justify-center gap-2 mb-6">
          <HeartPulse className="h-7 w-7 text-rose" />
          <span className="text-xl font-bold text-rose">Jolene</span>
        </div>
        <h1 className="text-xl font-bold text-foreground text-center mb-2">Inscription Soignant</h1>
        <SwitchTypeInscription actif="soignant" />

        {/* Stepper honnête : la création du compte se termine à l'étape Profil.
            Les documents et la vérification sont des tâches post-inscription,
            réalisées tranquillement depuis le tableau de bord
            (ChecklistActivation) — ce ne sont PAS des étapes d'inscription.
            Afficher « Documents » / « Vérifié » alourdissait inutilement le
            funnel et surprenait le soignant (mur documentaire perçu comme
            obligatoire à l'inscription). */}
        <div className="flex items-center justify-center gap-0 mb-2">
          {[
            { num: 1, label: 'Compte' },
            { num: 2, label: 'Profil' },
          ].map((s, i) => (
            <React.Fragment key={s.num}>
              {i > 0 && <div className={`h-1 w-8 sm:w-10 mx-1 rounded-full ${etape > s.num - 1 ? 'bg-primary' : 'bg-muted'}`} />}
              <div className="flex flex-col items-center gap-1">
                <div className={`h-9 w-9 rounded-full flex items-center justify-center text-sm font-bold ${etape > s.num ? 'bg-success text-success-foreground' : etape === s.num ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>
                  {etape > s.num ? <Check className="h-4 w-4" /> : s.num}
                </div>
                <span className={`text-[10px] font-semibold ${etape >= s.num ? 'text-primary' : 'text-muted-foreground'}`}>{s.label}</span>
              </div>
            </React.Fragment>
          ))}
        </div>
        <p className="text-center text-xs text-muted-foreground mb-8 px-2">
          ≈ 2 minutes. Tes documents et la vérification se font ensuite, tranquillement, depuis ton espace — pas maintenant.
        </p>

        {/* Pro Santé Connect — inscription rapide avec carte CPS/e-CPS */}
        {etape === 1 && (
          <div className="mb-6">
            <BoutonProSanteConnect
              intention="signup"
              onSwitchToEmail={() => {
                // Safari iOS scrolle nativement vers l'input focusé.
                // Pas de scrollIntoView smooth ici (créait un saut au focus mobile).
                document.querySelector<HTMLInputElement>('input[type="email"]')?.focus();
              }}
            />
            <p className="text-[10px] text-muted-foreground text-center mt-1.5">
              Avec une carte CPS/e-CPS, ton inscription est automatique et ton RPPS vérifié instantanément
            </p>
            <div className="my-4 flex items-center gap-3">
              <div className="flex-1 h-px bg-border" />
              <span className="text-xs text-muted-foreground">ou inscription manuelle</span>
              <div className="flex-1 h-px bg-border" />
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          {etape === 1 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 1 — Tes identifiants</p>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Email *</span>
                <input type="email" autoComplete="email" value={form.email} onChange={e => maj('email', e.target.value)} className={`input-base ${classeChampErreur('email')}`} required aria-invalid={form.email.length > 0 && !emailValide} aria-describedby={form.email.length > 0 && !emailValide ? 'email-err' : undefined} />
                {form.email.length > 0 && !emailValide && (
                  <p id="email-err" className="text-xs text-destructive mt-1 break-words" role="alert">Format d'email invalide</p>
                )}
              </label>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe *</span>
                <div className="relative">
                  <input type={afficherMdp ? 'text' : 'password'} value={form.motDePasse} onChange={e => maj('motDePasse', e.target.value)} placeholder="Minimum 8 caractères" className={`input-base pr-10 ${classeChampErreur('motDePasse')}`} required minLength={8} />
                  <button type="button" onClick={() => setAfficherMdp(!afficherMdp)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground" aria-label={afficherMdp ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}>
                    {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
                <JaugeForce motDePasse={form.motDePasse} />
              </label>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Confirmer le mot de passe *</span>
                <input type="password" autoComplete="new-password" value={form.confirmMdp} onChange={e => maj('confirmMdp', e.target.value)} className="input-base" required minLength={8} aria-invalid={!!form.confirmMdp && form.confirmMdp !== form.motDePasse} aria-describedby={form.confirmMdp && form.confirmMdp !== form.motDePasse ? 'confirm-err' : undefined} />
                {form.confirmMdp && form.confirmMdp !== form.motDePasse && (
                  <p id="confirm-err" className="text-xs text-destructive mt-1 break-words" role="alert">Les mots de passe ne correspondent pas</p>
                )}
              </label>
              <label className="flex items-start gap-2 cursor-pointer">
                <input type="checkbox" checked={cgu} onChange={e => setCgu(e.target.checked)} className="mt-1 h-4 w-4 rounded border-input text-primary accent-primary" />
                <span className="text-sm text-muted-foreground">J'accepte les <a href="/cgu" target="_blank" rel="noopener noreferrer" className="text-primary underline font-medium">Conditions Générales d'Utilisation</a> et la <a href="/confidentialite" target="_blank" rel="noopener noreferrer" className="text-primary underline font-medium">Politique de confidentialité</a> *</span>
              </label>
              {erreurInscription && (etape === 1 || champsAHighlighter.has('email') || champsAHighlighter.has('motDePasse')) && (
                <ErreurInscription
                  erreur={erreurInscription}
                  onRetry={handleRetry}
                  onSeConnecter={handleSeConnecter}
                />
              )}
              <button type="button" onClick={() => setEtape(2)} disabled={!etape1Valide} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed">Continuer</button>
            </div>
          )}

          {etape === 2 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 2 — Ton profil professionnel</p>
              {/* La valeur avant l'effort (Session E-2) : dès la profession choisie,
                  montrer le marché réel — missions et taux, ou établissements inscrits.
                  Rendu prominent (carte mise en avant) : c'est la motivation à finir.
                  La géolocalisation et le rayon sont déférés à l'espace personnel
                  (tâche post-inscription) pour alléger le funnel — l'aperçu reste
                  national tant que la position n'est pas renseignée. */}
              {form.profession && (
                <ApercuMarche
                  profession={form.profession}
                  lat={form.lat}
                  lng={form.lng}
                  rayonKm={form.rayon}
                  className="ring-1 ring-primary/20 rounded-2xl"
                />
              )}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <label className="block">
                  <span className="text-sm font-medium text-foreground mb-1.5 block">Prénom *{rppsPreRempli && <span className="text-xs text-emerald-600 ml-1.5 font-normal">Vérifié via RPPS</span>}</span>
                  <input value={form.prenom} onChange={e => { if (!rppsPreRempli) maj('prenom', e.target.value); }} readOnly={rppsPreRempli} className={`input-base ${rppsPreRempli ? 'bg-emerald-50/50 cursor-not-allowed' : ''} ${classeChampErreur('prenom')}`} required autoComplete="given-name" />
                </label>
                <label className="block">
                  <span className="text-sm font-medium text-foreground mb-1.5 block">Nom *{rppsPreRempli && <span className="text-xs text-emerald-600 ml-1.5 font-normal">Vérifié via RPPS</span>}</span>
                  <input value={form.nom} onChange={e => { if (!rppsPreRempli) maj('nom', e.target.value); }} readOnly={rppsPreRempli} className={`input-base ${rppsPreRempli ? 'bg-emerald-50/50 cursor-not-allowed' : ''} ${classeChampErreur('nom')}`} required autoComplete="family-name" />
                </label>
              </div>
              <label className="block"><span className="text-sm font-medium text-foreground mb-1.5 block">Téléphone *</span><input value={form.telephone} onChange={e => maj('telephone', e.target.value)} type="tel" inputMode="tel" autoComplete="tel" placeholder="+33 6 ..." className={`input-base ${classeChampErreur('telephone')}`} pattern="[\\+]?[0-9\\s]{8,15}" required aria-invalid={form.telephone.length > 0 && !telephoneValide} />
                {form.telephone.length > 0 && !telephoneValide && <p className="text-xs text-destructive mt-1 break-words" role="alert">Numéro de téléphone invalide</p>}
                <p className="text-[11px] text-muted-foreground mt-1">Nécessaire pour qu'un établissement puisse te joindre (missions urgentes).</p>
              </label>
              <label className="block"><span className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance *</span><input type="date" value={form.dateNaissance} onChange={e => maj('dateNaissance', e.target.value)} className={`input-base ${classeChampErreur('dateNaissance')}`} max={new Date(new Date().setFullYear(new Date().getFullYear() - 18)).toISOString().split('T')[0]} required aria-invalid={!!form.dateNaissance && !dateNaissanceMajeur} aria-describedby={form.dateNaissance && !dateNaissanceMajeur ? 'date-err' : undefined} />
                {dateNaissanceRequise && <p className="text-xs text-destructive mt-1 break-words">La date de naissance est obligatoire</p>}
                {form.dateNaissance && !dateNaissanceMajeur && <p id="date-err" className="text-xs text-destructive mt-1 break-words" role="alert">Tu dois avoir 18 ans révolus pour t'inscrire</p>}
              </label>
              <div>
                <label htmlFor="profession-select" className="text-sm font-medium text-foreground mb-1.5 block">Profession *</label>
                <SelectProfession value={form.profession} onChange={v => maj('profession', v)} triggerId="profession-select" />
              </div>
              <DeclarationEtudiant
                estEtudiant={form.estEtudiant}
                formation={form.scolariteFormation}
                annee={form.scolariteAnnee}
                professionDeclaree={form.profession}
                onToggle={(v) => maj('estEtudiant', v)}
                onChangeFormation={(v) => maj('scolariteFormation', v)}
                onChangeAnnee={(v) => maj('scolariteAnnee', v)}
                onSuggererProfession={(p) => maj('profession', p)}
              />
              <fieldset className="border-0 p-0 m-0">
                <legend className="text-sm font-medium text-foreground mb-1.5">Types de contrat acceptés * <span className="text-xs text-muted-foreground font-normal">(au moins 1)</span></legend>
                <div className="grid grid-cols-2 gap-2 mt-1" role="group" aria-label="Types de contrat acceptés">
                  {CONTRATS.filter(c => peutEtreLiberal || (c.valeur !== 'LIBERAL' && c.valeur !== 'VACATION')).map(c => (
                    <label key={c.valeur} className="flex items-center gap-2 cursor-pointer rounded-lg border border-input px-3 py-2.5 hover:bg-accent/50 transition-colors has-[:checked]:border-primary has-[:checked]:bg-primary/5">
                      <Checkbox
                        checked={form.typesContrat.includes(c.valeur)}
                        onCheckedChange={() => toggleContrat(c.valeur)}
                        aria-label={c.label}
                      />
                      <span className="text-sm text-foreground">{c.label}</span>
                    </label>
                  ))}
                </div>
                {form.profession && !peutEtreLiberal && (
                  <p className="text-[10px] text-muted-foreground mt-1.5">
                    Ta profession ne peut pas exercer en libéral. Seuls CDD et Salarié sont disponibles.
                  </p>
                )}
                {form.typesContrat.length === 0 && (
                  <p className="text-xs text-muted-foreground mt-1">Cochez au moins un type de contrat</p>
                )}
              </fieldset>
              {rppsRequis ? (
                <label className="block">
                  <span className="text-sm font-medium text-foreground mb-1.5 block">Numéro RPPS{rppsObligatoireInscription ? ' *' : ''}</span>
                  {!rppsObligatoireInscription && (
                    <p className="text-[11px] text-muted-foreground mb-1.5">
                      Tu ne le connais pas par cœur ? Tu peux laisser vide et le compléter plus tard — la vérification se fera à ce moment-là.
                    </p>
                  )}
                  <div className="relative">
                    <input value={form.rpps} onChange={e => maj('rpps', e.target.value.replace(/\D/g, '').slice(0, 11))} placeholder={rppsObligatoireInscription ? '11 chiffres' : '11 chiffres (optionnel)'} className={`input-base pr-10 ${classeChampErreur('rpps')}`} inputMode="numeric" autoComplete="off" aria-describedby={rppsVerifiant ? 'rpps-status' : undefined} />
                    {rppsVerifiant && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 animate-spin text-primary" aria-hidden="true" />}
                  </div>
                  {rppsVerifiant && <p id="rpps-status" className="text-xs text-primary mt-1" role="status">Vérification en cours...</p>}
                  {rppsResultat && rppsResultat.trouve && rppsMatch === true && (
                    <div className="mt-1.5 space-y-1.5">
                      <div className="flex items-center gap-1.5 text-xs bg-emerald-50 text-emerald-700 rounded-lg px-2 py-1.5">
                        <ShieldCheck className="h-3.5 w-3.5" />
                        ✅ RPPS Vérifié — {rppsResultat.nom_affiche}
                      </div>
                      {rppsResultat.specialite_label && (
                        <div className="flex items-center gap-1.5 text-xs bg-primary/10 text-primary rounded-lg px-2 py-1.5">
                          <ShieldCheck className="h-3.5 w-3.5" />
                          Spécialité récupérée automatiquement : <span className="font-medium">{rppsResultat.specialite_label}</span>
                        </div>
                      )}
                      {rppsResultat.profession_api && form.profession && rppsResultat.profession_correspond === false && (
                        <div className="flex items-center gap-1.5 text-xs bg-destructive/5 text-destructive rounded-lg px-2 py-1.5" role="alert">
                          <ShieldAlert className="h-3.5 w-3.5" />
                          ❌ Ce RPPS correspond à la profession « {rppsResultat.profession_api} », pas à « {getLabelProfession(form.profession)} ». Vérifie ton numéro ou ta profession.
                        </div>
                      )}
                    </div>
                  )}
                  {rppsResultat && rppsResultat.trouve && rppsMatch === false && form.rpps.length === 11 && !rppsVerifManuelle && (
                    <div className="mt-1.5 flex items-center gap-1.5 text-xs bg-destructive/5 text-destructive rounded-lg px-2 py-1.5">
                      <ShieldAlert className="h-3.5 w-3.5" />
                      ❌ Ce RPPS ne correspond pas à ton identité
                    </div>
                  )}
                  {rppsResultat && !rppsResultat.trouve && !rppsResultat.fhir_indisponible && form.rpps.length === 11 && !rppsVerifManuelle && (
                    <div className="mt-1.5 space-y-1.5" role="alert">
                      <div className="flex items-center gap-1.5 text-xs bg-destructive/5 text-destructive rounded-lg px-2 py-1.5">
                        <ShieldAlert className="h-3.5 w-3.5" />
                        ❌ RPPS non trouvé dans l'annuaire
                      </div>
                      <p className="text-[11px] text-muted-foreground">
                        Vérifie le numéro. Si ton RPPS est récent ou mal indexé dans l'annuaire public, tu peux tout de même continuer :
                      </p>
                      <button
                        type="button"
                        onClick={() => setRppsVerifManuelle(true)}
                        className="text-xs font-semibold text-primary border border-primary/40 rounded-lg px-3 py-1.5 hover:bg-primary/10 transition-colors"
                      >
                        Continuer — vérification manuelle sous 24 h
                      </button>
                    </div>
                  )}
                  {rppsVerifManuelle && form.rpps.length === 11 && (
                    <div className="mt-1.5 flex items-center gap-1.5 text-xs bg-amber-50 text-amber-700 rounded-lg px-2 py-1.5">
                      <ShieldCheck className="h-3.5 w-3.5" />
                      Ton RPPS sera vérifié manuellement sous 24 h — tu peux terminer ton inscription.
                    </div>
                  )}
                  {rppsResultat && rppsResultat.fhir_indisponible && form.rpps.length === 11 && (
                    <div className="mt-1.5 flex items-center gap-1.5 text-xs bg-amber-50 text-amber-700 rounded-lg px-2 py-1.5">
                      <ShieldCheck className="h-3.5 w-3.5" />
                      Format RPPS valide. La vérification auprès de l'Annuaire Santé sera effectuée sous 24h.
                    </div>
                  )}
                </label>
              ) : form.profession && (
                <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
                  <p className="text-xs text-foreground">
                    ℹ️ Ta profession ne nécessite pas de numéro d'identification professionnelle. Ton diplôme et ta carte d'identité seront vérifiés à la première mission.
                  </p>
                </div>
              )}
              {/* Question salarié établissement */}
              <ExerciceTypeSection profession={form.profession} estSalarieEtablissement={form.estSalarieEtablissement} onChangeSalarie={(v) => maj('estSalarieEtablissement', v)} />
              {/* Rayon de déplacement + géolocalisation déférés à l'espace
                  personnel (tâche post-inscription) pour alléger le funnel. Un
                  rayon par défaut de 30 km est conservé silencieusement dans le
                  state du formulaire et transmis au backend, qui l'accepte
                  (register-soignant: rayon par défaut = 30 si non numérique). */}
              <CaptchaTurnstile className="flex justify-center pt-2" onVerify={setTurnstileToken} onExpire={() => setTurnstileToken(null)} onError={() => setTurnstileToken(null)} />
              {erreurInscription && etape === 2 && !champsAHighlighter.has('email') && !champsAHighlighter.has('motDePasse') && (
                <ErreurInscription
                  erreur={erreurInscription}
                  onRetry={handleRetry}
                  onSeConnecter={handleSeConnecter}
                />
              )}
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEtape(1)} className="btn-secondary flex-1">Retour</button>
                <button type="submit" disabled={!etape2Valide || submitting} className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2" aria-busy={submitting}>
                  {submitting && <Loader2 className="h-5 w-5 animate-spin" aria-hidden="true" />}
                  {submitting ? 'Création…' : 'Créer mon compte'}
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
