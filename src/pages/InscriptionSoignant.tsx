import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Eye, EyeOff, Check, Loader2, ShieldCheck, ShieldAlert } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { getLabelProfession } from '@/lib/constantes';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';
import { CaptchaTurnstile, TURNSTILE_REQUIRED } from '@/components/CaptchaTurnstile';
import { SelectProfession } from '@/components/SelectProfession';
import { FooterLegal } from '@/components/FooterLegal';
import { CONTRATS, PROFESSIONS_SANS_RPPS, PROFESSIONS_NON_LIBERAL } from '@/lib/constantes';
import { Checkbox } from '@/components/ui/checkbox';
import { logger } from '@/lib/logger';
import { BoutonProSanteConnect } from '@/components/BoutonProSanteConnect';


function GeoAutoRequest({ onResult, onRefused }: { onResult: (lat: number, lng: number) => void; onRefused?: () => void }) {
  const [asked, setAsked] = useState(false);
  useEffect(() => {
    if (asked) return;
    setAsked(true);
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => onResult(pos.coords.latitude, pos.coords.longitude),
      () => { onRefused?.(); }
    );
  }, [asked, onResult, onRefused]);
  return null;
}

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
            En tant que <strong>{getLabelProfession(profession)}</strong>, votre type d'exercice est automatiquement défini comme <strong>{uniqueType === 'SALARIE' ? 'salarié' : uniqueType === 'LIBERAL' ? 'libéral' : 'mixte'}</strong>.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div>
      <label className="text-sm font-medium text-foreground mb-1.5 block">Êtes-vous actuellement salarié(e) d'un établissement de santé ?</label>
      <div className="flex gap-3 mt-1">
        <button type="button" onClick={() => onChangeSalarie(true)} className={`flex-1 py-2.5 px-4 rounded-xl border text-sm font-medium transition-colors ${estSalarieEtablissement === true ? 'border-primary bg-primary/5 text-primary' : 'border-input text-muted-foreground hover:bg-accent/50'}`}>Oui</button>
        <button type="button" onClick={() => onChangeSalarie(false)} className={`flex-1 py-2.5 px-4 rounded-xl border text-sm font-medium transition-colors ${estSalarieEtablissement === false ? 'border-primary bg-primary/5 text-primary' : 'border-input text-muted-foreground hover:bg-accent/50'}`}>Non</button>
      </div>
      {estSalarieEtablissement === true && (
        <div className="mt-3 p-3 bg-primary/5 border border-primary/20 rounded-xl">
          <p className="text-xs text-foreground">ℹ️ Vous pourrez effectuer des missions sur Jolene en complément de votre activité salariée. Vérifiez que votre contrat de travail n'inclut pas de clause d'exclusivité.</p>
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
      const ref = new URLSearchParams(window.location.search).get('ref');
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

  const [form, setForm] = useState({
    email: '', motDePasse: '', confirmMdp: '',
    prenom: '', nom: '', telephone: '', dateNaissance: '',
    profession: '', typesContrat: [] as string[], rpps: '', rayon: 30,
    lat: null as number | null, lng: null as number | null,
    estSalarieEtablissement: null as boolean | null,
  });

  // RPPS verification state
  const [rppsVerifiant, setRppsVerifiant] = useState(false);
  const [rppsResultat, setRppsResultat] = useState<{ trouve: boolean; nom_affiche?: string; specialite_code?: string | null; specialite_label?: string | null } | null>(null);

  const normaliser = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().trim();

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
  const rppsMatch = rppsCorrespond();
  const rppsBloquant = rppsRequis && form.rpps.length === 11 && rppsResultat && (!rppsResultat.trouve || rppsMatch === false);
  const etape2Valide = form.prenom && form.nom && form.profession && form.typesContrat.length > 0 && !rppsBloquant && !dateNaissanceRequise && dateNaissanceMajeur && (!TURNSTILE_REQUIRED || !!turnstileToken);

  // Verify RPPS when 11 digits entered
  useEffect(() => {
    if (form.rpps.length !== 11 || !form.prenom || !form.nom) {
      setRppsResultat(null);
      return;
    }
    const controller = new AbortController();
    const timeout = setTimeout(async () => {
      setRppsVerifiant(true);
      try {
        const rppsValue = form.rpps;
        const response = await fetch(
          'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/verify-rpps',
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
              turnstileToken,
            }),
            signal: controller.signal,
          }
        );

        const data = await response.json();
        if (controller.signal.aborted) return;
        logger.debug('RPPS response:', data);

        if (!response.ok) {
          logger.error('verify-rpps fetch error', data);
          setRppsResultat(data?.trouve === false ? { trouve: false } : null);
        } else if (data) {
          const nomAffiche = data.nom_api || data.nom || '';
          const prenomAffiche = data.prenom || '';
          const label = [prenomAffiche, nomAffiche].filter(Boolean).join(' ') || nomAffiche;
          setRppsResultat({
            trouve: !!data.trouve,
            nom_affiche: label,
            specialite_code: data.specialite_code ?? null,
            specialite_label: data.specialite_label ?? null,
          });
        } else {
          setRppsResultat({ trouve: false });
        }
      } catch (err: any) {
        if (err?.name === 'AbortError') return; // re-render cancellation, normal
        logger.error('verify-rpps fetch exception', err);
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
    try {
      await inscriptionSoignant({ ...form, turnstileToken });
      // PII (email) hors URL : sessionStorage évite leak via historique/referer
      try { sessionStorage.setItem('inscription_email', form.email); } catch { /* sessionStorage indisponible */ }
      navigate('/inscription/succes?role=soignant');
    } catch (err) {
      if (!gererErreurSupabase(err, () => handleSubmit(e))) {
        afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen gradient-hero flex flex-col">
      <div className="flex-1 flex items-center justify-center px-4 py-8">
      <div className="card-base max-w-lg w-full">
        <div className="flex items-center justify-center gap-2 mb-6">
          <HeartPulse className="h-7 w-7 text-rose" />
          <span className="text-xl font-bold text-rose">Jolene</span>
        </div>
        <h1 className="text-xl font-bold text-foreground text-center mb-2">Inscription Soignant</h1>

        {/* Stepper */}
        <div className="flex items-center justify-center gap-0 mb-8">
          <div className={`h-9 w-9 rounded-full flex items-center justify-center text-sm font-bold ${etape >= 1 ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>
            {etape > 1 ? <Check className="h-4 w-4" /> : '1'}
          </div>
          <div className={`h-1 w-16 mx-1 rounded-full ${etape > 1 ? 'bg-primary' : 'bg-muted'}`} />
          <div className={`h-9 w-9 rounded-full flex items-center justify-center text-sm font-bold ${etape >= 2 ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>2</div>
        </div>

        {/* Pro Santé Connect — inscription rapide avec carte CPS/e-CPS */}
        {etape === 1 && (
          <div className="mb-6">
            <BoutonProSanteConnect intention="signup" />
            <p className="text-[10px] text-muted-foreground text-center mt-1.5">
              Avec une carte CPS/e-CPS, votre inscription est automatique et votre RPPS vérifié instantanément
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
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 1 — Vos identifiants</p>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Email *</span>
                <input type="email" autoComplete="email" value={form.email} onChange={e => maj('email', e.target.value)} className="input-base" required aria-invalid={form.email.length > 0 && !emailValide} aria-describedby={form.email.length > 0 && !emailValide ? 'email-err' : undefined} />
                {form.email.length > 0 && !emailValide && (
                  <p id="email-err" className="text-xs text-destructive mt-1 break-words" role="alert">Format d'email invalide</p>
                )}
              </label>
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe *</span>
                <div className="relative">
                  <input type={afficherMdp ? 'text' : 'password'} value={form.motDePasse} onChange={e => maj('motDePasse', e.target.value)} placeholder="Minimum 8 caractères" className="input-base pr-10" required minLength={8} />
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
              <button type="button" onClick={() => setEtape(2)} disabled={!etape1Valide} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed">Continuer</button>
            </div>
          )}

          {etape === 2 && (
            <div className="space-y-4">
              <GeoAutoRequest
                onResult={(lat, lng) => { maj('lat', lat); maj('lng', lng); }}
                onRefused={() => afficherNotification({ type: 'info', message: 'Géolocalisation refusée — vous pourrez la réactiver depuis votre profil pour voir les missions près de chez vous.' })}
              />
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 2 — Votre profil professionnel</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <label className="block"><span className="text-sm font-medium text-foreground mb-1.5 block">Prénom *</span><input value={form.prenom} onChange={e => maj('prenom', e.target.value)} className="input-base" required autoComplete="given-name" /></label>
                <label className="block"><span className="text-sm font-medium text-foreground mb-1.5 block">Nom *</span><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" required autoComplete="family-name" /></label>
              </div>
              <label className="block"><span className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</span><input value={form.telephone} onChange={e => maj('telephone', e.target.value)} type="tel" inputMode="tel" autoComplete="tel" placeholder="+33 6 ..." className="input-base" pattern="[\+]?[0-9\s]{8,15}" /></label>
              <label className="block"><span className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance *</span><input type="date" value={form.dateNaissance} onChange={e => maj('dateNaissance', e.target.value)} className="input-base" max={new Date(new Date().setFullYear(new Date().getFullYear() - 18)).toISOString().split('T')[0]} required aria-invalid={!!form.dateNaissance && !dateNaissanceMajeur} aria-describedby={form.dateNaissance && !dateNaissanceMajeur ? 'date-err' : undefined} />
                {dateNaissanceRequise && <p className="text-xs text-destructive mt-1 break-words">La date de naissance est obligatoire</p>}
                {form.dateNaissance && !dateNaissanceMajeur && <p id="date-err" className="text-xs text-destructive mt-1 break-words" role="alert">Vous devez avoir 18 ans révolus pour vous inscrire</p>}
              </label>
              <div>
                <label htmlFor="profession-select" className="text-sm font-medium text-foreground mb-1.5 block">Profession *</label>
                <SelectProfession value={form.profession} onChange={v => maj('profession', v)} triggerId="profession-select" />
              </div>
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
                    Votre profession ne peut pas exercer en libéral. Seuls CDDU et Salarié sont disponibles.
                  </p>
                )}
                {form.typesContrat.length === 0 && (
                  <p className="text-xs text-muted-foreground mt-1">Cochez au moins un type de contrat</p>
                )}
              </fieldset>
              {rppsRequis ? (
                <label className="block">
                  <span className="text-sm font-medium text-foreground mb-1.5 block">Numéro RPPS *</span>
                  <div className="relative">
                    <input value={form.rpps} onChange={e => maj('rpps', e.target.value.replace(/\D/g, '').slice(0, 11))} placeholder="11 chiffres" className="input-base pr-10" inputMode="numeric" autoComplete="off" aria-describedby={rppsVerifiant ? 'rpps-status' : undefined} />
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
                    </div>
                  )}
                  {rppsResultat && rppsResultat.trouve && rppsMatch === false && form.rpps.length === 11 && (
                    <div className="mt-1.5 flex items-center gap-1.5 text-xs bg-destructive/5 text-destructive rounded-lg px-2 py-1.5">
                      <ShieldAlert className="h-3.5 w-3.5" />
                      ❌ Ce RPPS ne correspond pas à votre identité
                    </div>
                  )}
                  {rppsResultat && !rppsResultat.trouve && form.rpps.length === 11 && (
                    <div className="mt-1.5 flex items-center gap-1.5 text-xs bg-destructive/5 text-destructive rounded-lg px-2 py-1.5" role="alert">
                      <ShieldAlert className="h-3.5 w-3.5" />
                      ❌ RPPS non trouvé dans l'annuaire
                    </div>
                  )}
                </label>
              ) : form.profession && (
                <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
                  <p className="text-xs text-foreground">
                    ℹ️ Votre profession ne nécessite pas de numéro d'identification professionnelle. Votre diplôme et votre carte d'identité seront vérifiés à la première mission.
                  </p>
                </div>
              )}
              {/* Question salarié établissement */}
              <ExerciceTypeSection profession={form.profession} estSalarieEtablissement={form.estSalarieEtablissement} onChangeSalarie={(v) => maj('estSalarieEtablissement', v)} />
              <label className="block">
                <span className="text-sm font-medium text-foreground mb-1.5 block">Rayon de déplacement : <span className="text-primary font-bold">{form.rayon} km</span></span>
                <input type="range" min={5} max={100} value={form.rayon} onChange={e => maj('rayon', Number(e.target.value))} className="w-full h-2 bg-primary/20 rounded-full appearance-none cursor-pointer accent-primary" aria-valuemin={5} aria-valuemax={100} aria-valuenow={form.rayon} aria-label="Rayon de déplacement en kilomètres" />
                <div className="flex justify-between text-[10px] text-muted-foreground"><span>5 km</span><span>100 km</span></div>
              </label>
              <CaptchaTurnstile className="flex justify-center pt-2" onVerify={setTurnstileToken} onExpire={() => setTurnstileToken(null)} onError={() => setTurnstileToken(null)} />
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
      </div>
      <FooterLegal />
    </div>
  );
}
