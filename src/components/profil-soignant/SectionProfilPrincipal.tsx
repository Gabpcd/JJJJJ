import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2, MapPin, ShieldCheck, AlertCircle, CheckCircle2, ArrowRight, UserCog } from 'lucide-react';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { SelectSpecialiteMedicale } from '@/components/SelectSpecialiteMedicale';
import { SelectProfession } from '@/components/SelectProfession';
import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';
import { reverseGeocode } from '@/lib/geocodage';
import { getCurrentPosition as obtenirGeoloc } from '@/lib/geoloc';
import { CaptchaTurnstile } from '@/components/CaptchaTurnstile';
import { getLabelProfession, PROFESSIONS_SANS_RPPS } from '@/lib/constantes';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { useAffacturageActif } from '@/hooks/useAffacturageActif';
import { estEligibleLiberal, getRegleInstallation } from '@/lib/regles-installation-liberal';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { ResumeCompletion } from '@/lib/profil-soignant';
import { getMotifProfilIncomplet } from '@/lib/profil-soignant';

interface Props {
  userId: string;
  email: string;
  rppsVerifie: boolean;
  rppsVerifieLe: string | null;
  rpps: string;
  setRpps: (v: string) => void;
  prenom: string;
  setPrenom: (v: string) => void;
  nom: string;
  setNom: (v: string) => void;
  dateNaissance: string;
  setDateNaissance: (v: string) => void;
  telephone: string;
  setTelephone: (v: string) => void;
  profession: string;
  specialiteMedicale: string;
  setSpecialiteMedicale: (v: string) => void;
  specialiteVerifiee: boolean;
  specialiteSource: string;
  lat: string;
  setLat: (v: string) => void;
  lng: string;
  setLng: (v: string) => void;
  rayon: number;
  villeRecherche: string;
  setVilleRecherche: (v: string) => void;
  typeExercice: string;
  setTypeExercice: (v: string) => void;
  attestationCumul: boolean;
  setAttestationCumul: (v: boolean) => void;
  statutLiberal: string;
  heuresCumulees: number;
  tousDocumentsValides: boolean;
  resumeCompletion: ResumeCompletion;
  onRefresh: () => void;
  onSave: () => Promise<void>;
  saving: boolean;
}

function BandeauCompletionProfil({ resume }: { resume: ResumeCompletion }) {
  const motif = getMotifProfilIncomplet(resume);
  if (resume.est_complet) {
    return (
      <div className="card-base bg-success/5 border-success/30">
        <div className="flex items-center gap-3">
          <CheckCircle2 className="h-5 w-5 text-success shrink-0" />
          <div>
            <p className="text-sm font-semibold text-success">Profil complet à 100%</p>
            <p className="text-xs text-muted-foreground">Toutes les informations sont renseignées.</p>
          </div>
        </div>
      </div>
    );
  }
  // Audit soignant fix : Tailwind ne compile pas les classes dynamiques.
  // Map statique pour que les classes existent au build.
  // Ton encourageant, jamais punitif : vert dès que le soignant peut candidater,
  // sinon couleur de marque (nudge vers l'étape suivante) — pas de rouge « échec ».
  const couleurClasses = resume.peut_candidater
    ? { card: 'bg-success/5 border-success/30', icon: 'text-success', text: 'text-success', bar: 'bg-success' }
    : { card: 'bg-primary/5 border-primary/30', icon: 'text-primary', text: 'text-primary', bar: 'bg-primary' };
  return (
    <div className={`card-base ${couleurClasses.card}`}>
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex items-start gap-3">
          <AlertCircle className={`h-5 w-5 ${couleurClasses.icon} shrink-0 mt-0.5`} />
          <div>
            <p className={`text-sm font-semibold ${couleurClasses.text}`}>
              Profil complété à {resume.pourcentage}%
            </p>
            {motif && <p className="text-xs text-muted-foreground mt-0.5">{motif}</p>}
          </div>
        </div>
        <span className="text-xs text-muted-foreground">
          {resume.items_remplis}/{resume.total_items}
        </span>
      </div>
      <div className="h-2 bg-muted rounded-full overflow-hidden">
        <div
          className={`h-full ${couleurClasses.bar} transition-all`}
          style={{ width: `${resume.pourcentage}%` }}
        />
      </div>
    </div>
  );
}

function RppsVerifierInline(props: {
  userId: string;
  rpps: string;
  setRpps: (v: string) => void;
  prenom: string;
  setPrenom: (v: string) => void;
  nom: string;
  setNom: (v: string) => void;
  dateNaissance: string;
  setDateNaissance: (v: string) => void;
  onVerified: () => void;
}) {
  const { userId, rpps, setRpps, prenom, setPrenom, nom, setNom, dateNaissance, setDateNaissance, onVerified } = props;
  const { afficherNotification } = useNotification();
  const [verifying, setVerifying] = useState(false);
  const [resultat, setResultat] = useState<null | { trouve: boolean; correspond?: boolean; nom_api?: string; prenom_api?: string; profession_api?: string }>(null);
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);

  const peutVerifier = rpps.length === 11 && !!prenom && !!nom;

  const verifier = async () => {
    if (!peutVerifier) return;
    setVerifying(true);
    setResultat(null);
    try {
      // 1) Persister prénom, nom, date naissance, RPPS sur le profil
      const { error: errSave } = await supabase.rpc('fn_modifier_mon_profil' as any, {
        p_prenom: prenom || null,
        p_nom: nom || null,
        p_date_naissance: dateNaissance || null,
        p_numero_rpps: rpps || null,
      });
      if (errSave) {
        afficherNotification({
          type: 'erreur',
          message: `Impossible d'enregistrer tes informations : ${extraireMessageErreur(errSave)}`,
        });
        setVerifying(false);
        return;
      }

      // 2) Vérifier via l'edge function (qui écrit rpps_verifie=true si correspond)
      const { data: { session } } = await supabase.auth.getSession();
      const accessToken = session?.access_token || SUPABASE_PUBLISHABLE_KEY;
      const response = await fetch(`${SUPABASE_URL}/functions/v1/verify-rpps`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
          'apikey': SUPABASE_PUBLISHABLE_KEY,
        },
        body: JSON.stringify({
          rpps,
          numero_rpps: rpps,
          prenom,
          nom,
          soignant_id: userId,
          turnstileToken,
        }),
      });
      const data = await response.json();
      setResultat({
        trouve: !!data.trouve,
        correspond: !!data.correspond,
        nom_api: data.nom_api,
        prenom_api: data.prenom_api,
        profession_api: data.profession_api,
      });

      if (data.trouve && data.correspond) {
        afficherNotification({ type: 'succes', message: 'RPPS vérifié avec succès !' });
        onVerified();
      } else if (data.trouve && !data.correspond) {
        afficherNotification({
          type: 'erreur',
          message: `Les informations ne correspondent pas. API : ${data.prenom_api || ''} ${data.nom_api || ''}`,
        });
      } else {
        afficherNotification({ type: 'erreur', message: 'RPPS introuvable dans l\'Annuaire Santé.' });
      }
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: 'Erreur serveur lors de la vérification.' });
    }
    setVerifying(false);
  };

  return (
    <div className="card-base">
      <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
        <ShieldCheck className="h-4 w-4 text-primary" /> Vérification RPPS
      </h2>
      <p className="text-xs text-muted-foreground mb-4">
        Saisis ton numéro RPPS, prénom et nom tels qu'ils apparaissent dans l'Annuaire Santé.
      </p>
      <div className="space-y-3">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label htmlFor="rpps-prenom" className="text-sm font-medium text-foreground mb-1.5 block">Prénom *</label>
            <input
              id="rpps-prenom"
              value={prenom}
              onChange={(e) => setPrenom(e.target.value)}
              className="input-base"
              placeholder="Tel qu'à l'état civil"
            />
          </div>
          <div>
            <label htmlFor="rpps-nom" className="text-sm font-medium text-foreground mb-1.5 block">Nom *</label>
            <input
              id="rpps-nom"
              value={nom}
              onChange={(e) => setNom(e.target.value)}
              className="input-base"
              placeholder="Tel qu'à l'état civil"
            />
          </div>
        </div>
        <div>
          <label htmlFor="rpps-date-naissance" className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance</label>
          <input
            id="rpps-date-naissance"
            type="date"
            value={dateNaissance}
            onChange={(e) => setDateNaissance(e.target.value)}
            className="input-base"
          />
        </div>
        <div>
          <label htmlFor="rpps-numero" className="text-sm font-medium text-foreground mb-1.5 block">Numéro RPPS *</label>
          <input
            id="rpps-numero"
            value={rpps}
            onChange={(e) => setRpps(e.target.value.replace(/\D/g, '').slice(0, 11))}
            placeholder="11 chiffres"
            className="input-base"
            inputMode="numeric"
            autoComplete="off"
          />
          {rpps.length > 0 && rpps.length < 11 && (
            <p className="text-[10px] text-warning mt-1">
              {rpps.length}/11 chiffres
            </p>
          )}
          <p className="text-[10px] text-muted-foreground mt-1">
            Numéro à 11 chiffres délivré par l'ARS et inscrit sur ta carte CPS. La validation se fait via l'Annuaire Santé (ANS).
          </p>
        </div>

        <CaptchaTurnstile className="flex justify-center" onVerify={setTurnstileToken} onExpire={() => setTurnstileToken(null)} onError={() => setTurnstileToken(null)} />

        <button
          type="button"
          onClick={verifier}
          disabled={!peutVerifier || verifying}
          className="btn-primary text-sm py-2 px-4 inline-flex items-center gap-2 disabled:opacity-50"
        >
          {verifying ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}
          {verifying ? 'Vérification…' : 'Vérifier mon RPPS'}
        </button>

        {resultat && resultat.trouve && resultat.correspond && (
          <div className="p-3 rounded-xl border border-success/30 bg-success/5">
            <p className="text-sm font-semibold text-success flex items-center gap-2">
              <ShieldCheck className="h-4 w-4" /> RPPS vérifié — {resultat.prenom_api} {resultat.nom_api}
            </p>
            {resultat.profession_api && (
              <p className="text-xs text-muted-foreground mt-1">Profession : {resultat.profession_api}</p>
            )}
          </div>
        )}
        {resultat && resultat.trouve && !resultat.correspond && (
          <div className="p-3 rounded-xl border border-destructive/30 bg-destructive/5">
            <p className="text-sm font-semibold text-destructive">Les données ne correspondent pas</p>
            <p className="text-xs text-muted-foreground mt-1">
              API : <strong>{resultat.prenom_api} {resultat.nom_api}</strong>. Vérifie l'orthographe.
            </p>
          </div>
        )}
        {resultat && !resultat.trouve && (
          <div className="p-3 rounded-xl border border-destructive/30 bg-destructive/5">
            <p className="text-sm font-semibold text-destructive">RPPS introuvable</p>
            <p className="text-xs text-muted-foreground mt-1">
              Le numéro saisi n'est pas dans l'Annuaire Santé. Vérifie les chiffres.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function ChoixProfessionInline(props: { onChosen: () => void }) {
  const { onChosen } = props;
  const { afficherNotification } = useNotification();
  const [profession, setProfessionLocal] = useState('');
  const [saving, setSaving] = useState(false);

  const enregistrer = async () => {
    if (!profession) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('fn_modifier_mon_profil' as any, {
      p_profession: profession,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
      setSaving(false);
      return;
    }
    if ((data as any)?.error) {
      afficherNotification({ type: 'erreur', message: (data as any).error });
      setSaving(false);
      return;
    }
    afficherNotification({ type: 'succes', message: 'Profession enregistrée.' });
    setSaving(false);
    onChosen();
  };

  return (
    <div className="card-base">
      <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
        <UserCog className="h-4 w-4 text-primary" /> Choisis ta profession
      </h2>
      <p className="text-sm text-muted-foreground mb-4">
        Pour finaliser ton profil et accéder aux missions, sélectionne ta profession.
        Le formulaire s'adaptera ensuite (vérification RPPS pour les professions à numéro,
        ou identification par diplôme pour les aides-soignants).
      </p>
      <div className="space-y-3">
        <SelectProfession value={profession} onChange={setProfessionLocal} placeholder="Sélectionne ta profession" />
        <button
          type="button"
          onClick={enregistrer}
          disabled={!profession || saving}
          className="btn-primary text-sm py-2 px-4 inline-flex items-center gap-2 disabled:opacity-50"
        >
          {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <ArrowRight className="h-4 w-4" />}
          {saving ? 'Enregistrement…' : 'Continuer'}
        </button>
      </div>
    </div>
  );
}

function BoutonModifierProfession({ rppsVerifie, tousDocumentsValides, onChanged }: {
  rppsVerifie: boolean;
  tousDocumentsValides: boolean;
  onChanged: () => void;
}) {
  const { afficherNotification } = useNotification();
  const [showConfirm, setShowConfirm] = useState(false);
  const [resetting, setResetting] = useState(false);

  // Caché dès qu'un RPPS est vérifié OU qu'un document a été validé
  if (rppsVerifie || tousDocumentsValides) return null;

  const reset = async () => {
    setResetting(true);
    const { data, error } = await supabase.rpc('fn_reinitialiser_ma_profession' as any);
    const resultat = data as { success?: boolean; error?: string; error_code?: string } | null;
    if (error || !resultat?.success) {
      afficherNotification({
        type: 'erreur',
        message: resultat?.error || (error ? extraireMessageErreur(error) : 'La profession ne peut pas être réinitialisée.'),
      });
      setResetting(false);
      setShowConfirm(false);
      return;
    }
    afficherNotification({ type: 'succes', message: 'Profession réinitialisée. Choisis ta profession.' });
    setResetting(false);
    setShowConfirm(false);
    onChanged();
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setShowConfirm(true)}
        className="text-xs text-muted-foreground hover:text-foreground hover:underline mt-3 inline-flex items-center gap-1"
      >
        ← Modifier ma profession
      </button>
      {showConfirm && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center">
          <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={() => !resetting && setShowConfirm(false)} />
          <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full">
            <h3 className="text-base font-bold text-foreground mb-2">Changer de profession ?</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Tu vas réinitialiser ta profession et revenir au sélecteur. Tu pourras choisir une nouvelle profession.
            </p>
            <div className="flex gap-3 justify-end">
              <button
                onClick={() => setShowConfirm(false)}
                disabled={resetting}
                className="btn-secondary text-sm px-4 py-2"
              >
                Annuler
              </button>
              <button
                onClick={reset}
                disabled={resetting}
                className="btn-primary text-sm px-4 py-2 disabled:opacity-50"
              >
                {resetting ? 'Réinitialisation…' : 'Continuer'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

function BlocPaieFacturation({ typeExercice, userId }: { typeExercice: string; userId: string }) {
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [nir, setNir] = useState('');
  const [nirInitial, setNirInitial] = useState('');
  const [savingNir, setSavingNir] = useState(false);
  const [defactoOptIn, setDefactoOptIn] = useState(false);
  const [savingOptIn, setSavingOptIn] = useState(false);
  // Toggle Defacto masqué tant que l'affacturage n'est pas activé (feature flag).
  const affacturageActif = useAffacturageActif();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('soignants')
        .select('numero_securite_sociale, defacto_opt_in')
        .eq('id', userId)
        .maybeSingle();
      if (cancelled) return;
      const v = ((data as any)?.numero_securite_sociale ?? '') as string;
      setNir(v);
      setNirInitial(v);
      setDefactoOptIn(!!(data as any)?.defacto_opt_in);
    })();
    return () => { cancelled = true; };
  }, [userId]);

  const toggleDefactoOptIn = async () => {
    setSavingOptIn(true);
    const newVal = !defactoOptIn;
    const { error } = await supabase.from('soignants').update({ defacto_opt_in: newVal } as any).eq('id', userId);
    setSavingOptIn(false);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    setDefactoOptIn(newVal);
    afficherNotification({ type: 'succes', message: newVal ? 'Paiement rapide J+2 activé' : 'Paiement rapide J+2 désactivé' });
  };

  const enregistrerNir = async () => {
    setSavingNir(true);
    const cleaned = nir.replace(/[^0-9]/g, '');
    const { data, error } = await supabase.rpc('fn_modifier_mon_nir' as any, { p_nir: cleaned || null });
    setSavingNir(false);
    if (error || (data as any)?.success === false) {
      afficherNotification({
        type: 'erreur',
        message: (data as any)?.error || error?.message || 'Erreur lors de l\'enregistrement du NIR',
      });
      return;
    }
    setNirInitial(cleaned);
    afficherNotification({ type: 'succes', message: 'Numéro de sécurité sociale enregistré' });
  };

  const peutLiberal = typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';
  const peutSalarie = typeExercice === 'SALARIE' || typeExercice === 'MIXTE';

  return (
    <div className="card-base">
      <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
        <ShieldCheck className="h-4 w-4 text-primary" /> Paie et facturation
      </h2>
      <div className="space-y-3">
        <div>
          <label htmlFor="profil-nir" className="text-sm font-medium text-foreground mb-1.5 block">
            Numéro de sécurité sociale (NIR)
            {peutSalarie && <span className="text-xs text-warning ml-2">requis pour le bulletin de paie</span>}
          </label>
          <div className="flex gap-2">
            <input
              id="profil-nir"
              value={nir}
              onChange={(e) => setNir(e.target.value)}
              placeholder="13 ou 15 chiffres"
              className="input-base flex-1"
              inputMode="numeric"
              autoComplete="off"
            />
            <button
              type="button"
              onClick={enregistrerNir}
              disabled={savingNir || nir === nirInitial}
              className="btn-primary text-sm px-4 disabled:opacity-50"
            >
              {savingNir ? '...' : 'Enregistrer'}
            </button>
          </div>
          <p className="text-[10px] text-muted-foreground mt-1">
            Mention obligatoire art. R3243-1 CTW. Donnée chiffrée et accessible
            uniquement à toi + l'admin Jolene. 13 chiffres (sans clé) ou 15 (avec clé).
          </p>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pt-2">
          {peutLiberal && (
            <button
              type="button"
              onClick={() => navigate('/soignant/mandat-facturation')}
              className="text-left rounded-xl border border-border hover:border-primary/40 bg-muted/30 hover:bg-muted/50 p-3 transition-colors"
            >
              <p className="text-xs font-bold text-primary mb-0.5">Mandat de facturation</p>
              <p className="text-xs text-muted-foreground">
                Signe ou révoque ton mandat (LIBERAL — art. 289 I-2 CGI).
              </p>
              <span className="text-[11px] text-primary font-medium mt-1.5 inline-block">Ouvrir →</span>
            </button>
          )}
          {peutSalarie && (
            <button
              type="button"
              onClick={() => navigate('/soignant/mes-gains?tab=bulletins')}
              className="text-left rounded-xl border border-border hover:border-primary/40 bg-muted/30 hover:bg-muted/50 p-3 transition-colors"
            >
              <p className="text-xs font-bold text-primary mb-0.5">Mes bulletins de paie</p>
              <p className="text-xs text-muted-foreground">
                Bulletins SALARIE émis par Jolene à chaque mission terminée.
              </p>
              <span className="text-[11px] text-primary font-medium mt-1.5 inline-block">Ouvrir →</span>
            </button>
          )}
          {peutLiberal && (
            <button
              type="button"
              onClick={() => navigate('/soignant/mes-gains?tab=factures')}
              className="text-left rounded-xl border border-border hover:border-primary/40 bg-muted/30 hover:bg-muted/50 p-3 transition-colors"
            >
              <p className="text-xs font-bold text-primary mb-0.5">Mes factures d'honoraires</p>
              <p className="text-xs text-muted-foreground">
                Factures émises par Jolene en ton nom (LIBERAL).
              </p>
              <span className="text-[11px] text-primary font-medium mt-1.5 inline-block">Ouvrir →</span>
            </button>
          )}
        </div>

        {peutLiberal && affacturageActif && (
          <div className="pt-3 border-t border-border mt-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-medium text-foreground">Paiement rapide J+2 (Defacto)</p>
                <p className="text-[10px] text-muted-foreground">
                  {defactoOptIn
                    ? 'Activé — chaque facture émise est automatiquement cédée pour paiement sous 48h (frais ~1-3 %).'
                    : 'Désactivé — tes factures sont payées par l\'établissement selon ses délais habituels (30-60 jours).'}
                </p>
              </div>
              <button
                type="button"
                onClick={toggleDefactoOptIn}
                disabled={savingOptIn}
                className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${defactoOptIn ? 'bg-primary' : 'bg-muted-foreground/30'} disabled:opacity-50`}
              >
                <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${defactoOptIn ? 'translate-x-5' : 'translate-x-0'}`} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export function SectionProfilPrincipal(props: Props) {
  const {
    userId, email,
    rppsVerifie, rppsVerifieLe, rpps, setRpps,
    prenom, setPrenom, nom, setNom, dateNaissance, setDateNaissance,
    telephone, setTelephone,
    profession, specialiteMedicale, setSpecialiteMedicale,
    specialiteVerifiee, specialiteSource,
    lat, setLat, lng, setLng, villeRecherche, setVilleRecherche,
    typeExercice, setTypeExercice, attestationCumul, setAttestationCumul,
    statutLiberal, heuresCumulees,
    tousDocumentsValides,
    resumeCompletion, onRefresh, onSave, saving,
  } = props;

  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const { typesAutorises, uniqueType } = useTypesExerciceAutorises(profession);
  const [geoLoading, setGeoLoading] = useState(false);

  useEffect(() => {
    if (uniqueType) setTypeExercice(uniqueType);
  }, [uniqueType, setTypeExercice]);

  const demanderGeolocalisation = async () => {
    setGeoLoading(true);
    try {
      const position = await obtenirGeoloc({ enableHighAccuracy: true, timeout: 15_000 });
      const la = position.coords.latitude, lo = position.coords.longitude;
      setLat(la.toString());
      setLng(lo.toString());
      const adr = await reverseGeocode(la, lo);
      if (adr) {
        if (adr.ville) setVilleRecherche(adr.ville);
        afficherNotification({ type: 'succes', message: `📍 ${adr.label}` });
      } else {
        afficherNotification({ type: 'succes', message: 'Position récupérée.' });
      }
    } catch {
      afficherNotification({ type: 'erreur', message: 'Localisation refusée ou indisponible. Tu peux saisir ton adresse manuellement.' });
    } finally {
      setGeoLoading(false);
    }
  };

  const sansRPPS = profession && PROFESSIONS_SANS_RPPS.includes(profession);

  return (
    <div className="space-y-4">
      <BandeauCompletionProfil resume={resumeCompletion} />

      {/* Identification professionnelle — en TÊTE */}
      {!profession ? (
        <ChoixProfessionInline onChosen={onRefresh} />
      ) : sansRPPS ? (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
            <ShieldCheck className="h-4 w-4 text-primary" /> Identification professionnelle
          </h2>
          <p className="text-sm text-foreground mb-3">
            Ta profession (<strong>{getLabelProfession(profession)}</strong>) ne nécessite pas de numéro RPPS. Ton identification professionnelle se fait par ton diplôme et ta carte d'identité.
          </p>
          <button
            type="button"
            onClick={() => navigate('/soignant/mes-documents')}
            className="btn-primary text-sm py-2 px-4 inline-flex items-center gap-2"
          >
            Téléverser mes documents <ArrowRight className="h-3.5 w-3.5" />
          </button>
          <BoutonModifierProfession
            rppsVerifie={rppsVerifie}
            tousDocumentsValides={tousDocumentsValides}
            onChanged={onRefresh}
          />
        </div>
      ) : !rppsVerifie ? (
        <div>
          <RppsVerifierInline
            userId={userId}
            rpps={rpps}
            setRpps={setRpps}
            prenom={prenom}
            setPrenom={setPrenom}
            nom={nom}
            setNom={setNom}
            dateNaissance={dateNaissance}
            setDateNaissance={setDateNaissance}
            onVerified={onRefresh}
          />
          <div className="px-4 mt-1">
            <BoutonModifierProfession
              rppsVerifie={rppsVerifie}
              tousDocumentsValides={tousDocumentsValides}
              onChanged={onRefresh}
            />
          </div>
        </div>
      ) : (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
            <ShieldCheck className="h-4 w-4 text-success" /> Identité professionnelle
          </h2>
          <div className="p-3 rounded-xl border border-success/30 bg-success/5 mb-3">
            <p className="text-sm font-semibold text-success flex items-center gap-2">
              <ShieldCheck className="h-4 w-4" /> RPPS vérifié
              {rppsVerifieLe && (
                <span className="text-xs font-normal text-muted-foreground">
                  · le {new Date(rppsVerifieLe).toLocaleDateString('fr-FR')}
                </span>
              )}
            </p>
            <p className="text-xs text-muted-foreground mt-1">Source : Annuaire Santé (ANS).</p>
          </div>
          <div className="space-y-3">
            <div>
              <label htmlFor="profil-profession" className="text-sm font-medium text-foreground mb-1.5 block">
                Profession <span className="text-xs text-muted-foreground">(vérifiée RPPS — non modifiable)</span>
              </label>
              <input
                id="profil-profession"
                value={profession ? getLabelProfession(profession) : '—'}
                disabled
                className="input-base bg-muted cursor-not-allowed"
              />
              {(() => {
                if (!profession || !estEligibleLiberal(profession) || statutLiberal === 'ACTIF') return null;
                const regle = getRegleInstallation(profession);
                const seuil = regle?.heures_requises;
                if (!seuil || heuresCumulees >= seuil) return null;
                return (
                  <p className="text-xs text-muted-foreground mt-1">
                    🔒 Passage en libéral disponible à {seuil.toLocaleString('fr-FR')}h — actuellement{' '}
                    <span className="font-semibold text-primary">{heuresCumulees}h</span>/{seuil.toLocaleString('fr-FR')}h
                  </p>
                );
              })()}
            </div>
            {(profession === 'MEDECIN' || profession === 'IDE') && (
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 flex items-center gap-2">
                  <span>Spécialité {profession === 'IDE' ? '(IPA uniquement)' : ''}</span>
                  {specialiteVerifiee && specialiteSource === 'RPPS' && (
                    <span className="inline-flex items-center gap-1 text-[10px] text-success font-semibold">
                      <ShieldCheck className="h-3 w-3" /> Vérifiée RPPS
                    </span>
                  )}
                </label>
                <SelectSpecialiteMedicale
                  value={specialiteMedicale}
                  onChange={setSpecialiteMedicale}
                  professionParent={profession === 'IDE' ? 'IDE' : 'MEDECIN'}
                  disabled={specialiteVerifiee && specialiteSource === 'RPPS'}
                  placeholder={profession === 'IDE' ? 'IPA uniquement (optionnel)' : 'Sélectionne ta spécialité'}
                />
                {!specialiteVerifiee && specialiteMedicale && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Vérifiable lors de la prochaine vérification RPPS
                  </p>
                )}
              </div>
            )}
            <div>
              <label htmlFor="profil-rpps" className="text-sm font-medium text-foreground mb-1.5 block">
                RPPS <span className="text-xs text-muted-foreground">(vérifié — non modifiable)</span>
              </label>
              <input id="profil-rpps" value={rpps} readOnly className="input-base bg-muted cursor-not-allowed" />
            </div>
          </div>
        </div>
      )}

      {/* Informations personnelles */}
      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4">Informations personnelles</h2>
        <div className="space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label htmlFor="profil-prenom" className="text-sm font-medium text-foreground mb-1.5 block">
                Prénom{' '}
                {rppsVerifie && (
                  <span className="text-xs text-muted-foreground">(vérifié RPPS — non modifiable)</span>
                )}
              </label>
              <input
                id="profil-prenom"
                value={prenom}
                onChange={(e) => setPrenom(e.target.value)}
                readOnly={rppsVerifie}
                className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`}
              />
            </div>
            <div>
              <label htmlFor="profil-nom" className="text-sm font-medium text-foreground mb-1.5 block">
                Nom{' '}
                {rppsVerifie && (
                  <span className="text-xs text-muted-foreground">(vérifié RPPS — non modifiable)</span>
                )}
              </label>
              <input
                id="profil-nom"
                value={nom}
                onChange={(e) => setNom(e.target.value)}
                readOnly={rppsVerifie}
                className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`}
              />
            </div>
          </div>
          <div>
            <label htmlFor="profil-telephone" className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label>
            <input
              id="profil-telephone"
              value={telephone}
              onChange={(e) => setTelephone(e.target.value)}
              className="input-base"
            />
          </div>
          <div>
            <label htmlFor="profil-date-naissance" className="text-sm font-medium text-foreground mb-1.5 block">
              Date de naissance{' '}
              {rppsVerifie && (
                <span className="text-xs text-muted-foreground">(vérifiée — non modifiable)</span>
              )}
            </label>
            <input
              id="profil-date-naissance"
              type="date"
              value={dateNaissance}
              onChange={(e) => setDateNaissance(e.target.value)}
              readOnly={rppsVerifie}
              className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`}
            />
          </div>
          <div>
            <label htmlFor="profil-email" className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
            <input id="profil-email" value={email} disabled className="input-base bg-muted cursor-not-allowed" />
          </div>
        </div>
      </div>

      <BlocPaieFacturation typeExercice={typeExercice} userId={userId} />

      {/* Adresse */}
      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
          <MapPin className="h-4 w-4 text-primary" /> Adresse
        </h2>
        <div className="space-y-3">
          <button
            type="button"
            onClick={demanderGeolocalisation}
            disabled={geoLoading}
            className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50"
          >
            {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
            {geoLoading ? 'Récupération en cours…' : 'Utiliser ma position actuelle'}
          </button>
          <p className="text-xs text-muted-foreground mt-2">
            {lat && lng
              ? <>📍 Position enregistrée — ta ville est renseignée ci-dessous. <span className="opacity-60">(coordonnées techniques : {Number(lat).toFixed(4)}, {Number(lng).toFixed(4)})</span></>
              : "Utilise ta position pour renseigner automatiquement ta ville."}
          </p>
          <div className="pt-2 border-t border-border">
            <label htmlFor="profil-ville-recherche" className="text-sm font-medium text-foreground mb-1.5 block">🏙️ Ville de recherche</label>
            <p className="text-xs text-muted-foreground mb-2">
              Indique la ville où tu cherches des missions. Utile si tu es en déplacement ou en vacances.
            </p>
            <input
              id="profil-ville-recherche"
              value={villeRecherche}
              onChange={(e) => setVilleRecherche(e.target.value)}
              placeholder="Ex : Lyon, Paris..."
              className="input-base"
            />
          </div>
        </div>
      </div>

      {/* Type d'exercice */}
      {profession && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Type d'exercice</h2>
          {uniqueType ? (
            <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
              <p className="text-sm text-foreground">
                En tant que <strong>{getLabelProfession(profession)}</strong>, ton type d'exercice est automatiquement défini comme{' '}
                <strong>
                  {uniqueType === 'SALARIE' ? 'salarié' : uniqueType === 'LIBERAL' ? 'libéral' : 'mixte'}
                </strong>
                .
              </p>
            </div>
          ) : (
            <RadioGroup
              value={typeExercice}
              onValueChange={(v) => {
                setTypeExercice(v);
                if (v === 'SALARIE') setAttestationCumul(false);
              }}
              className="space-y-3"
            >
              {(!typesAutorises || typesAutorises.includes('SALARIE')) && (
                <label className="flex items-start gap-3 cursor-pointer rounded-lg border border-input px-4 py-3 hover:bg-accent/50 transition-colors has-[:checked]:border-primary has-[:checked]:bg-primary/5">
                  <RadioGroupItem value="SALARIE" id="ex-salarie" className="mt-0.5" />
                  <div>
                    <Label htmlFor="ex-salarie" className="font-medium cursor-pointer">Salarié(e)</Label>
                    <p className="text-xs text-muted-foreground mt-0.5">Je suis salarié(e) dans un établissement</p>
                  </div>
                </label>
              )}
              {(!typesAutorises || typesAutorises.includes('LIBERAL')) && (
                <label
                  className={`flex items-start gap-3 rounded-lg border border-input px-4 py-3 transition-colors ${
                    statutLiberal === 'ACTIF' ? 'cursor-pointer hover:bg-accent/50 has-[:checked]:border-primary has-[:checked]:bg-primary/5' : 'opacity-50 cursor-not-allowed'
                  }`}
                >
                  <RadioGroupItem value="LIBERAL" id="ex-liberal" className="mt-0.5" disabled={statutLiberal !== 'ACTIF'} />
                  <div>
                    <Label htmlFor="ex-liberal" className={`font-medium ${statutLiberal !== 'ACTIF' ? 'cursor-not-allowed' : 'cursor-pointer'}`}>
                      Libéral
                    </Label>
                    <p className="text-xs text-muted-foreground mt-0.5">J'exerce en libéral</p>
                    {statutLiberal !== 'ACTIF' && (
                      <p className="text-xs text-destructive mt-1">
                        ⚠️ Tu dois d'abord finaliser ton passage en libéral.{' '}
                        <button
                          type="button"
                          onClick={() => navigate('/soignant/passer-en-liberal')}
                          className="text-primary underline"
                        >
                          Accéder au parcours →
                        </button>
                      </p>
                    )}
                  </div>
                </label>
              )}
              {(!typesAutorises || typesAutorises.includes('MIXTE')) && (
                <label
                  className={`flex items-start gap-3 rounded-lg border border-input px-4 py-3 transition-colors ${
                    statutLiberal === 'ACTIF' ? 'cursor-pointer hover:bg-accent/50 has-[:checked]:border-primary has-[:checked]:bg-primary/5' : 'opacity-50 cursor-not-allowed'
                  }`}
                >
                  <RadioGroupItem value="MIXTE" id="ex-mixte" className="mt-0.5" disabled={statutLiberal !== 'ACTIF'} />
                  <div>
                    <Label htmlFor="ex-mixte" className={`font-medium ${statutLiberal !== 'ACTIF' ? 'cursor-not-allowed' : 'cursor-pointer'}`}>
                      Mixte
                    </Label>
                    <p className="text-xs text-muted-foreground mt-0.5">Je cumule salarié et libéral</p>
                    {statutLiberal !== 'ACTIF' && (
                      <p className="text-xs text-destructive mt-1">
                        ⚠️ Validation parcours libéral requise.{' '}
                        <button
                          type="button"
                          onClick={() => navigate('/soignant/passer-en-liberal')}
                          className="text-primary underline"
                        >
                          Parcours →
                        </button>
                      </p>
                    )}
                  </div>
                </label>
              )}
            </RadioGroup>
          )}

          {(typeExercice === 'MIXTE' || typeExercice === 'LIBERAL') && !uniqueType && (
            <div className="mt-4 p-3 bg-warning/5 border border-warning/20 rounded-xl">
              <label className="flex items-start gap-3 cursor-pointer">
                <Checkbox
                  aria-label="J’atteste que mon contrat autorise le cumul d’activités"
                  checked={attestationCumul}
                  onCheckedChange={(v) => setAttestationCumul(!!v)}
                  className="mt-0.5"
                />
                <span className="text-sm text-foreground">
                  J'atteste avoir vérifié que mon contrat de travail actuel autorise le cumul d'activités conformément à l'article L1222-5 du Code du travail.
                </span>
              </label>
            </div>
          )}
        </div>
      )}

      {/* Save button */}
      <div className="flex justify-end pt-2">
        <button
          type="button"
          onClick={onSave}
          disabled={saving}
          className="btn-primary disabled:opacity-50"
        >
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </div>
    </div>
  );
}
