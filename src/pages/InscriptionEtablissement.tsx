import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect, useCallback } from 'react';
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

function GeoAutoEtab({ onResult }: { onResult: (lat: number, lng: number) => void }) {
  const [asked, setAsked] = useState(false);
  useEffect(() => {
    if (asked) return;
    setAsked(true);
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => onResult(pos.coords.latitude, pos.coords.longitude),
      () => { /* géolocalisation refusée — silencieux */ }
    );
  }, [asked, onResult]);
  return null;
}

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
  const [etape, setEtape] = useState(1);
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [cgu, setCgu] = useState(false);
  const [cgv, setCgv] = useState(false);
  const [submitting, setSubmitting] = useState(false);

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
  const etape2Valide = form.nom && siretEstValide && form.type && form.ville;

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
      console.warn('Vérification INSEE échouée:', err);
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
      await inscriptionEtablissement(form);
      const autoVerifie = inseeCheck?.statut === 'VERIFIE';
      if (autoVerifie) {
        afficherNotification({ type: 'succes', message: 'Établissement créé et vérifié automatiquement ! Vous pouvez publier des missions.' });
      } else {
        afficherNotification({ type: 'info', message: 'Inscription réussie ! Votre compte est en attente de validation par Jolene (24-48h).', duree: 10000 });
      }
      navigate('/etablissement/tableau-de-bord');
    } catch (err) {
      if (!gererErreurSupabase(err, () => handleSubmit(e))) {
        handleError(err, 'inscription établissement');
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
        <h1 className="text-xl font-bold text-foreground text-center mb-2">Inscription Établissement</h1>

        <div className="flex items-center justify-center gap-0 mb-8">
          <div className={`h-9 w-9 rounded-full flex items-center justify-center text-sm font-bold ${etape >= 1 ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>
            {etape > 1 ? <Check className="h-4 w-4" /> : '1'}
          </div>
          <div className={`h-1 w-16 mx-1 rounded-full ${etape > 1 ? 'bg-primary' : 'bg-muted'}`} />
          <div className={`h-9 w-9 rounded-full flex items-center justify-center text-sm font-bold ${etape >= 2 ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>2</div>
        </div>

        <form onSubmit={handleSubmit}>
          {etape === 1 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 1 — Vos identifiants</p>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email *</label><input type="email" autoComplete="email" value={form.email} onChange={e => maj('email', e.target.value)} className="input-base" required /></div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe *</label>
                <div className="relative">
                  <input type={afficherMdp ? 'text' : 'password'} value={form.motDePasse} onChange={e => maj('motDePasse', e.target.value)} placeholder="Minimum 8 caractères" className="input-base pr-10" required />
                  <button type="button" onClick={() => setAfficherMdp(!afficherMdp)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                    {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Confirmer *</label><input type="password" value={form.confirmMdp} onChange={e => maj('confirmMdp', e.target.value)} className="input-base" required />
                {form.confirmMdp && form.confirmMdp !== form.motDePasse && <p className="text-xs text-destructive mt-1">Les mots de passe ne correspondent pas</p>}
              </div>
              <label className="flex items-start gap-2 cursor-pointer">
                <input type="checkbox" checked={cgu} onChange={e => setCgu(e.target.checked)} className="mt-1 h-4 w-4 rounded accent-primary" />
                <span className="text-sm text-muted-foreground">J'accepte les <a href="/cgu" target="_blank" className="text-primary hover:underline">Conditions Générales d'Utilisation</a> et la <a href="/confidentialite" target="_blank" className="text-primary hover:underline">Politique de confidentialité</a> *</span>
              </label>
              <label className="flex items-start gap-2 cursor-pointer">
                <input type="checkbox" checked={cgv} onChange={e => setCgv(e.target.checked)} className="mt-1 h-4 w-4 rounded accent-primary" />
                <span className="text-sm text-muted-foreground">J'accepte les <a href="/cgv" target="_blank" className="text-primary hover:underline">Conditions Générales de Vente</a> *</span>
              </label>
              <button type="button" onClick={() => setEtape(2)} disabled={!etape1Valide} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed">Continuer</button>
            </div>
          )}

          {etape === 2 && (
            <>
            <GeoAutoEtab onResult={(lat, lng) => { maj('lat', lat); maj('lng', lng); }} />
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 2 — Votre établissement</p>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nom de l'établissement *</label><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" required /></div>
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
                <p className="text-xs text-muted-foreground">ℹ️ Le plafond Loi Rist s'applique aux taux horaires en CDDU.</p>
              )}
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Adresse</label>
                <input value={form.rue} onChange={e => maj('rue', e.target.value)} placeholder="Rue" className="input-base mb-2" />
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  <input value={form.ville} onChange={e => maj('ville', e.target.value)} placeholder="Ville *" className="input-base" required />
                  <input value={form.codePostal} onChange={e => maj('codePostal', e.target.value.replace(/\D/g, '').slice(0, 5))} placeholder="Code postal" className="input-base" />
                  <input value={form.departement} onChange={e => maj('departement', e.target.value)} placeholder="Dép." className="input-base" />
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email contact</label><input type="email" value={form.emailContact} onChange={e => maj('emailContact', e.target.value)} className="input-base" /></div>
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephoneContact} onChange={e => maj('telephoneContact', e.target.value)} className="input-base" /></div>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEtape(1)} className="btn-secondary flex-1">Retour</button>
                <button type="submit" disabled={!etape2Valide || submitting} className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2">
                  {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
                  {submitting ? 'Création…' : 'Créer le compte'}
                </button>
              </div>
            </div>
            </>
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
