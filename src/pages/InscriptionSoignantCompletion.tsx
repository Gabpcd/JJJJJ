import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Check, Loader2, ShieldCheck, Eye, EyeOff } from 'lucide-react';
import { LogoJolene } from '@/components/LogoJolene';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { CONTRATS } from '@/lib/constantes';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { Checkbox } from '@/components/ui/checkbox';
import { FooterLegal } from '@/components/FooterLegal';
import { logger } from '@/lib/logger';

// Étapes du parcours d'inscription PSC : 1. Identité (PSC ✓) → 2. Compléter profil → 3. Documents → 4. Compte vérifié
function StepperCompletion() {
  return (
    <div className="flex items-center justify-center gap-0 mb-6">
      <div className="flex flex-col items-center gap-1">
        <div className="h-9 w-9 rounded-full bg-success text-success-foreground flex items-center justify-center">
          <Check className="h-4 w-4" />
        </div>
        <span className="text-[10px] text-success font-semibold">Identité PSC</span>
      </div>
      <div className="h-1 w-10 mx-1 rounded-full bg-primary" />
      <div className="flex flex-col items-center gap-1">
        <div className="h-9 w-9 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-bold">2</div>
        <span className="text-[10px] text-primary font-semibold">Profil</span>
      </div>
      <div className="h-1 w-10 mx-1 rounded-full bg-muted" />
      <div className="flex flex-col items-center gap-1">
        <div className="h-9 w-9 rounded-full bg-muted text-muted-foreground flex items-center justify-center text-sm font-bold">3</div>
        <span className="text-[10px] text-muted-foreground">Documents</span>
      </div>
      <div className="h-1 w-10 mx-1 rounded-full bg-muted" />
      <div className="flex flex-col items-center gap-1">
        <div className="h-9 w-9 rounded-full bg-muted text-muted-foreground flex items-center justify-center text-sm font-bold">4</div>
        <span className="text-[10px] text-muted-foreground">Vérifié</span>
      </div>
    </div>
  );
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
      <div className="flex gap-1">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className={`h-1 flex-1 rounded-full ${i <= force ? colors[force] : 'bg-muted'}`} />
        ))}
      </div>
      <p className="text-[10px] text-muted-foreground mt-0.5">{labels[force]}</p>
    </div>
  );
}

export default function InscriptionSoignantCompletion() {
  usePageTitle('Compléter mon profil');
  const navigate = useNavigate();
  const { user, loading: authLoading } = useAuth();
  const { afficherNotification } = useNotification();

  const [identite, setIdentite] = useState<{ prenom: string; nom: string; profession: string; numero_rpps: string | null } | null>(null);
  const [chargement, setChargement] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [afficherMdp, setAfficherMdp] = useState(false);

  const [form, setForm] = useState({
    telephone: '',
    motDePasse: '',
    villeRecherche: '',
    typesContrat: [] as string[],
    rayonKm: 30,
    cgu: false,
  });

  // Récupérer les infos déjà connues (renseignées par PSC)
  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      navigate('/connexion');
      return;
    }
    (async () => {
      const { data, error } = await supabase
        .from('soignants')
        .select('prenom, nom, profession, numero_rpps, telephone, type_contrat, types_contrat_acceptes')
        .eq('id', user.id)
        .maybeSingle();

      if (error || !data) {
        logger.error('[COMPLETION] Profil soignant introuvable', error);
        afficherNotification({ type: 'erreur', message: 'Profil introuvable. Veuillez vous reconnecter.' });
        navigate('/connexion');
        return;
      }

      setIdentite({
        prenom: data.prenom || '',
        nom: data.nom || '',
        profession: data.profession || '',
        numero_rpps: data.numero_rpps,
      });
      // Pré-remplir si l'utilisateur a déjà passé partiellement par le formulaire
      setForm(prev => ({
        ...prev,
        telephone: data.telephone || prev.telephone,
      }));
      setChargement(false);
    })();
  }, [user, authLoading, navigate, afficherNotification]);

  const maj = (champ: keyof typeof form, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const toggleContrat = (valeur: string) => {
    setForm(prev => {
      const next = prev.typesContrat.includes(valeur)
        ? prev.typesContrat.filter(v => v !== valeur)
        : [...prev.typesContrat, valeur];
      return { ...prev, typesContrat: next };
    });
  };

  // Session E-1 : téléphone optionnel (harmonisé avec le flow email — il est
  // redemandé au bon moment, p.ex. à l'activation des alertes SMS pool urgence).
  const formValide =
    (form.telephone.trim() === '' || form.telephone.trim().length >= 8) &&
    form.typesContrat.length > 0 &&
    form.cgu &&
    (form.motDePasse === '' || form.motDePasse.length >= 8);

  // Règle de PROFIL issue du référentiel DB, indépendante des règles de mission.
  const {
    typesAutorises: typesExerciceProfil,
    loading: typesExerciceChargement,
    indisponible: typesExerciceIndisponibles,
  } = useTypesExerciceAutorises(identite?.profession || '');
  const typesExerciceConnus = Array.isArray(typesExerciceProfil);
  const peutEtreLiberal = !!identite?.profession
    && !!typesExerciceProfil?.some((type) => type === 'LIBERAL' || type === 'MIXTE');
  const contratsAffiches = CONTRATS.filter(c => peutEtreLiberal || (c.valeur !== 'LIBERAL' && c.valeur !== 'VACATION'));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formValide || !user) return;
    setSubmitting(true);
    try {
      // 1. Mettre à jour le profil soignant avec les champs complémentaires
      const { error: updErr } = await supabase
        .from('soignants')
        .update({
          ...(form.telephone.trim() ? { telephone: form.telephone.trim() } : {}),
          types_contrat_acceptes: form.typesContrat.join(','),
          rayon_deplacement_km: form.rayonKm,
          ...(form.villeRecherche.trim() ? { ville_recherche: form.villeRecherche.trim() } : {}),
        })
        .eq('id', user.id);

      if (updErr) throw updErr;

      // 2. Définir un mot de passe (optionnel) pour permettre login email/password en plus de PSC
      if (form.motDePasse) {
        const { error: pwErr } = await supabase.auth.updateUser({ password: form.motDePasse });
        if (pwErr) {
          logger.warn('[COMPLETION] Impossible de définir le mot de passe', pwErr);
          afficherNotification({ type: 'avertissement', message: 'Profil enregistré, mais impossible de définir le mot de passe. Vous pourrez le faire plus tard depuis votre profil.' });
        }
      }

      afficherNotification({ type: 'succes', message: 'Profil complété ! Passons à vos documents.' });
      navigate('/soignant/documents');
    } catch (err) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setSubmitting(false);
    }
  };

  if (chargement) {
    return (
      <div className="min-h-[100dvh] gradient-hero flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="min-h-[100dvh] gradient-hero flex flex-col">
      <div className="flex-1 flex items-center justify-center px-4 py-8">
        <div className="card-base max-w-lg w-full">
          <LogoJolene
            className="mx-auto mb-4 flex w-fit"
            imageClassName="h-7 w-7"
            nomClassName="text-xl text-rose"
          />

          <StepperCompletion />

          <h1 className="text-xl font-bold text-foreground text-center mb-1">Compléter votre profil</h1>
          <p className="text-sm text-muted-foreground text-center mb-6">
            Quelques informations supplémentaires pour finaliser votre inscription.
          </p>

          {/* Récap identité PSC */}
          {identite && (
            <div className="mb-6 p-3 bg-success/5 border border-success/30 rounded-xl flex items-start gap-3">
              <ShieldCheck className="h-5 w-5 text-success shrink-0 mt-0.5" />
              <div className="text-sm">
                <p className="font-semibold text-foreground">Identité vérifiée par Pro Santé Connect</p>
                <p className="text-muted-foreground">
                  {identite.prenom} {identite.nom} · {identite.profession}
                  {identite.numero_rpps && ` · RPPS ${identite.numero_rpps}`}
                </p>
              </div>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone mobile</label>
              <input
                type="tel"
                inputMode="tel"
                autoComplete="tel"
                value={form.telephone}
                onChange={e => maj('telephone', e.target.value)}
                placeholder="+33 6 ..."
                className="input-base"
                pattern="[\+]?[0-9\s]{8,15}"
              />
              <p className="text-[10px] text-muted-foreground mt-1">Optionnel — utile pour être alerté·e en premier des missions urgentes.</p>
            </div>

            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Types de contrat acceptés <span className="text-destructive">*</span>
              </label>
              <div className="grid grid-cols-2 gap-2">
                {contratsAffiches.map(c => (
                  <label key={c.valeur} className={`flex items-center gap-2 p-2.5 rounded-xl border cursor-pointer text-sm ${form.typesContrat.includes(c.valeur) ? 'border-primary bg-primary/5' : 'border-input'}`}>
                    <Checkbox
                      checked={form.typesContrat.includes(c.valeur)}
                      onCheckedChange={() => toggleContrat(c.valeur)}
                    />
                    <span>{c.label}</span>
                  </label>
                ))}
              </div>
              {identite?.profession && typesExerciceChargement && (
                <p className="text-[10px] text-muted-foreground mt-1.5" role="status">
                  Vérification des types de contrat autorisés…
                </p>
              )}
              {identite?.profession && typesExerciceIndisponibles && (
                <p className="text-[10px] text-amber-700 mt-1.5" role="status">
                  Vérification temporairement indisponible. Vous pouvez poursuivre en CDD ou salarié et activer le libéral plus tard après contrôle.
                </p>
              )}
              {identite?.profession && typesExerciceConnus && !peutEtreLiberal && (
                <p className="text-[10px] text-muted-foreground mt-1.5">
                  Votre profession ne peut pas exercer en libéral. Seuls CDD et Salarié sont disponibles.
                </p>
              )}
            </div>

            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Ville de recherche (optionnel)</label>
              <input
                type="text"
                value={form.villeRecherche}
                onChange={e => maj('villeRecherche', e.target.value)}
                placeholder="Ex : Paris"
                className="input-base"
              />
              <p className="text-[10px] text-muted-foreground mt-1">Centre du rayon de recherche. Vous pourrez l'affiner plus tard depuis votre profil.</p>
            </div>

            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Rayon de déplacement : <span className="text-primary font-bold">{form.rayonKm} km</span>
              </label>
              <input
                type="range"
                min={5}
                max={100}
                value={Math.min(form.rayonKm, 100)}
                onChange={e => maj('rayonKm', Number(e.target.value))}
                className="w-full h-2 bg-primary/20 rounded-full appearance-none cursor-pointer accent-primary"
                aria-valuemin={5}
                aria-valuemax={100}
                aria-valuenow={form.rayonKm}
                aria-label="Rayon de déplacement en kilomètres"
              />
              <div className="flex justify-between text-[10px] text-muted-foreground"><span>5 km</span><span>100 km</span></div>
            </div>

            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe (optionnel)</label>
              <div className="relative">
                <input
                  type={afficherMdp ? 'text' : 'password'}
                  value={form.motDePasse}
                  onChange={e => maj('motDePasse', e.target.value)}
                  placeholder="Minimum 8 caractères — pour login email/mdp en complément de PSC"
                  className="input-base pr-10"
                />
                <button type="button" onClick={() => setAfficherMdp(!afficherMdp)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                  {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              <JaugeForce motDePasse={form.motDePasse} />
              <p className="text-[10px] text-muted-foreground mt-1">Vous pourrez toujours vous connecter avec votre carte CPS/e-CPS. Le mot de passe est utile pour les appareils sans lecteur de carte.</p>
            </div>

            <label className="flex items-start gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={form.cgu}
                onChange={e => maj('cgu', e.target.checked)}
                className="mt-1 h-4 w-4 rounded border-input text-primary accent-primary"
                required
              />
              <span className="text-sm text-muted-foreground">
                J'accepte les <a href="/cgu" target="_blank" className="text-primary hover:underline">Conditions Générales d'Utilisation</a> et la <a href="/confidentialite" target="_blank" className="text-primary hover:underline">Politique de confidentialité</a> <span className="text-destructive">*</span>
              </span>
            </label>

            <button
              type="submit"
              disabled={!formValide || submitting}
              className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
            >
              {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
              {submitting ? 'Enregistrement…' : 'Continuer vers les documents'}
            </button>
          </form>
        </div>
      </div>
      <FooterLegal />
    </div>
  );
}
