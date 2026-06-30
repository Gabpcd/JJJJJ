import React, { useState, useEffect } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { handleErrorSilent } from '@/lib/handleError';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { reverseGeocode } from '@/lib/geocodage';
import { capturerErreurSentry } from '@/lib/sentry';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { Info, MapPin, Loader2, Download, Trash2, Palette, Building2, Upload, FileCheck, Clock, AlertTriangle, LogOut } from 'lucide-react';
import { AvatarUpload } from '@/components/AvatarUpload';
import { Switch } from '@/components/ui/switch';
import { Elements, IbanElement, useStripe, useElements } from '@stripe/react-stripe-js';
import { stripePromise } from '@/lib/stripe';

// SEPA IBAN Form (inside Stripe Elements)
function SepaIbanForm({ onSuccess }: { onSuccess: (last4: string) => void }) {
  const stripe = useStripe();
  const elements = useElements();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    if (!stripe || !elements) return;
    setSubmitting(true);
    setError('');

    const ibanElement = elements.getElement(IbanElement);
    if (!ibanElement) { setSubmitting(false); return; }

    const { error: stripeErr, paymentMethod } = await stripe.createPaymentMethod({
      type: 'sepa_debit',
      sepa_debit: ibanElement as any,
      billing_details: { name: 'Établissement' },
    } as any);

    if (stripeErr) {
      setError(stripeErr.message || 'Erreur IBAN');
      setSubmitting(false);
      return;
    }

    const { data: session } = await supabase.auth.getSession();
    const token = session?.session?.access_token;
    const res = await fetch(
      `${SUPABASE_URL}/functions/v1/setup-sepa`,
      {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'confirm_sepa', payment_method_id: paymentMethod?.id }),
      }
    );
    const data = await res.json();
    if (data.success) {
      onSuccess(data.last4);
    } else {
      setError(data.error || 'Erreur lors de la configuration SEPA');
    }
    setSubmitting(false);
  };

  return (
    <div className="space-y-3">
      <div className="p-3 border border-border rounded-xl bg-background">
        <IbanElement
          options={{
            supportedCountries: ['SEPA'],
            style: {
              base: { fontSize: '16px', color: '#333', '::placeholder': { color: '#aab7c4' } },
            },
          }}
        />
      </div>
      {error && <p className="text-xs text-destructive">{error}</p>}
      <button
        type="button"
        onClick={handleSubmit}
        disabled={submitting || !stripe}
        className="btn-primary text-sm w-full disabled:opacity-50"
      >
        {submitting ? 'Validation…' : !stripe ? '⏳ Chargement Stripe…' : '🏦 Valider le mandat SEPA'}
      </button>
      {!stripe && <p className="text-[10px] text-warning">Le module de paiement charge. Patientez quelques secondes…</p>}
      <p className="text-[10px] text-muted-foreground">
        En fournissant votre IBAN, vous autorisez Jolene à envoyer des instructions à votre banque pour débiter votre compte conformément au mandat SEPA.
      </p>
    </div>
  );
}

// SEPA Setup Section wrapper
function SepaSetupSection({ userId }: { userId?: string }) {
  const [sepaStatus, setSepaStatus] = useState<{ has_sepa: boolean; last4?: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);

  useEffect(() => {
    if (!userId) return;
    (async () => {
      const { data: session } = await supabase.auth.getSession();
      const token = session?.session?.access_token;
      try {
        const res = await fetch(
          `${SUPABASE_URL}/functions/v1/setup-sepa`,
          {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'get_sepa_status' }),
          }
        );
        const data = await res.json();
        setSepaStatus(data);
      } catch {
        setSepaStatus({ has_sepa: false });
      }
      setLoading(false);
    })();
  }, [userId]);

  if (loading) return <div className="mt-4 text-sm text-muted-foreground">Chargement…</div>;

  if (sepaStatus?.has_sepa && !showForm) {
    return (
      <div className="mt-4 p-3 rounded-xl bg-success/10 border border-success/20">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Building2 className="h-4 w-4 text-success" />
            <span className="text-sm font-medium text-success">IBAN enregistré : FR76 •••• •••• {sepaStatus.last4}</span>
          </div>
          <button
            type="button"
            onClick={() => setShowForm(true)}
            className="text-xs text-primary hover:underline"
          >
            Modifier
          </button>
        </div>
      </div>
    );
  }

  if (!stripePromise) {
    return (
      <div className="mt-4 p-3 rounded-xl bg-warning/10 border border-warning/20">
        <p className="text-xs text-warning">Configuration Stripe manquante. Contactez le support.</p>
      </div>
    );
  }

  return (
    <div className="mt-4">
      <Elements stripe={stripePromise} options={{ locale: 'fr' }}>
        <SepaIbanForm onSuccess={(last4) => { setSepaStatus({ has_sepa: true, last4 }); setShowForm(false); }} />
      </Elements>
    </div>
  );
}

const CONVENTIONS_COLLECTIVES = [
  { valeur: 'CCN_51_FEHAP', label: 'CCN 51 (FEHAP)' },
  { valeur: 'CCN_66_SOCIAL', label: 'CCN 66 (Social)' },
  { valeur: 'CCN_FHP_PRIVE', label: 'CCN FHP (Privé)' },
  { valeur: 'CCN_PHARMACIE', label: 'CCN Pharmacie' },
  { valeur: 'FPH', label: 'Fonction Publique Hospitalière' },
  { valeur: 'AUTRE', label: 'Autre' },
];

export default function ProfilEtablissement() {
  usePageTitle('Profil');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <ProfilEtablissementContent />
    </LayoutApp>
  );
}

export function ProfilEtablissementContent() {
  const { user, deconnexion } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [exportingRgpd, setExportingRgpd] = useState(false);
  const [siret, setSiret] = useState('');
  const [type, setType] = useState('');
  const [conventionCollective, setConventionCollective] = useState('');
  const [modePaiement, setModePaiement] = useState('FACTURE_MENSUELLE');
  const [contratValide, setContratValide] = useState(false);
  const [contratUrl, setContratUrl] = useState<string | null>(null);
  const [contratUploadeLe, setContratUploadeLe] = useState<string | null>(null);
  const [uploadingContrat, setUploadingContrat] = useState(false);
  const contratInputRef = React.useRef<HTMLInputElement>(null);
  const [form, setForm] = useState({
    nom: '', finess: '', rue: '', ville: '', codePostal: '', departement: '',
    emailContact: '', telephoneContact: '',
    tauxNuit: 25, tauxDimanche: 50, tauxFerie: 100,
  });

  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_mon_etablissement_complet' as any).then(({ data }: any) => {
      if (data) {
        setSiret(data.siret);
        setType(data.type);
        setConventionCollective(data.convention_collective || '');
        setModePaiement((data as any).mode_paiement_commission || 'FACTURE_MENSUELLE');
        setContratValide(!!data.contrat_valide);
        setContratUrl(data.contrat_url || null);
        setContratUploadeLe(data.contrat_uploade_le || null);
        (setForm as any)(prev => ({ ...prev, logoUrl: (data as any).logo_url || '' }));
        setForm({
          nom: data.nom, finess: data.finess || '',
          rue: data.adresse_rue || '', ville: data.adresse_ville || '',
          codePostal: data.adresse_code_postal || '', departement: data.adresse_departement || '',
          emailContact: data.email_contact || '', telephoneContact: data.telephone_contact || '',
          tauxNuit: data.taux_majoration_nuit_pourcent ?? 25,
          tauxDimanche: data.taux_majoration_dimanche_pourcent ?? 50,
          tauxFerie: data.taux_majoration_ferie_pourcent ?? 100,
        });
        setLat(data.adresse_lat?.toString() || '');
        setLng(data.adresse_lng?.toString() || '');
        setCouleurTheme(data.couleur_theme || '#E04590');
        setConsentementSMS(data.sms_actif === true);
      }
      setLoading(false);
    });
    // L2: Audit consultation profil établissement
    supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'DONNEES_PERSO_CONSULTATION', p_type_ressource: 'etablissement',
      p_id_ressource: user.id, p_cle_s3: null,
      p_details: { page: 'profil_etablissement' },
      p_ip: null, p_navigateur: navigator.userAgent,
    });
  }, [user]);

  const [geoLoading, setGeoLoading] = useState(false);
  const [lat, setLat] = useState('');
  const [lng, setLng] = useState('');
  const [couleurTheme, setCouleurTheme] = useState('#E04590');
  const [consentementSMS, setConsentementSMS] = useState(false);
  const [smsToggling, setSmsToggling] = useState(false);

  // adresse_lat, adresse_lng, couleur_theme are loaded from the RPC in the main useEffect above

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const demanderGeolocalisation = () => {
    if (!navigator.geolocation) {
      afficherNotification({ type: 'erreur', message: 'La géolocalisation n\'est pas supportée par votre navigateur.' });
      return;
    }
    setGeoLoading(true);
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const la = position.coords.latitude, lo = position.coords.longitude;
        setLat(la.toString());
        setLng(lo.toString());
        const adr = await reverseGeocode(la, lo);
        if (adr) {
          setForm((prev: any) => ({ ...prev, rue: adr.rue || prev.rue, ville: adr.ville || prev.ville, codePostal: adr.codePostal || prev.codePostal }));
          afficherNotification({ type: 'succes', message: `📍 ${adr.label}` });
        } else {
          afficherNotification({ type: 'succes', message: 'Position récupérée.' });
        }
        setGeoLoading(false);
      },
      () => {
        setGeoLoading(false);
        afficherNotification({ type: 'erreur', message: 'Localisation refusée. Vous pouvez saisir les coordonnées manuellement.' });
      }
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    setSaving(true);

    // C3: Validate couleur_theme format before saving
    const hexRegex = /^#[0-9a-fA-F]{6}$/;
    if (!hexRegex.test(couleurTheme)) {
      afficherNotification({ type: 'erreur', message: 'Couleur invalide. Format attendu : #RRGGBB' });
      setSaving(false);
      return;
    }

    const { error } = await supabase.rpc('fn_modifier_mon_etablissement' as any, {
      p_couleur_theme: couleurTheme,
      p_convention_collective: conventionCollective || null,
      p_nom: form.nom,
      p_finess: form.finess || null,
      p_adresse_rue: form.rue,
      p_adresse_ville: form.ville,
      p_adresse_code_postal: form.codePostal,
      p_adresse_departement: form.departement || null,
      p_email_contact: form.emailContact,
      p_telephone: form.telephoneContact || null,
      p_adresse_lat: lat ? parseFloat(lat) : null,
      p_adresse_lng: lng ? parseFloat(lng) : null,
      p_taux_majoration_nuit: form.tauxNuit,
      p_taux_majoration_dimanche: form.tauxDimanche,
      p_taux_majoration_ferie: form.tauxFerie,
      p_mode_paiement_commission: modePaiement,
    });

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'DONNEES_PERSO_MODIFICATION', p_type_ressource: 'etablissement',
        p_id_ressource: user.id, p_cle_s3: null,
        p_details: { champs_modifies: Object.keys(form) },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      if (auditError) handleErrorSilent(auditError, 'Audit modification établissement');
      afficherNotification({ type: 'succes', message: 'Informations mises à jour avec succès !' });
    }
    setSaving(false);
  };

  const [noteMoyenne, setNoteMoyenne] = useState<{ moyenne: number; total: number } | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_note_moyenne' as any, { p_user_id: user.id })
      .then(({ data }: any) => {
        if (data && typeof data === 'object') setNoteMoyenne(data);
        else if (Array.isArray(data) && data[0]) setNoteMoyenne(data[0]);
      });
  }, [user]);

  if (loading) return <ChargementPage />;

  return (
    <>
      <div className="flex items-center gap-4 mb-6">
        <AvatarUpload
          src={(form as any).logoUrl}
          prenom={form.nom}
          nom=""
          size={96}
          mode="etablissement"
          onUploaded={(url) => setForm(prev => ({ ...prev, logoUrl: url } as any))}
        />
        <h2 className="text-lg font-bold text-foreground">Profil de l'établissement</h2>
      </div>

      {noteMoyenne && noteMoyenne.total > 0 && (
        <div className="card-base mb-6">
          <p className="text-lg font-bold text-foreground">⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}</p>
        </div>
      )}

      {/* Bandeau contrat non validé */}
      {!contratValide && (
        <div className="max-w-2xl mb-6 rounded-xl border border-warning/30 bg-warning/10 p-4 flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-warning mt-0.5 flex-shrink-0" />
          <div>
            <p className="text-sm font-semibold text-foreground">Contrat de service non validé</p>
            <p className="text-xs text-muted-foreground mt-1">
              {contratUrl
                ? 'Votre contrat a été téléversé et est en attente de validation par Jolene. Vous ne pouvez pas publier de missions tant qu\'il n\'est pas validé.'
                : 'Téléversez votre contrat de service signé pour pouvoir publier des missions.'}
            </p>
          </div>
        </div>
      )}

      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Informations générales</h2>
          <div className="space-y-3">
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nom</label><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" /></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">SIRET</label><input value={siret} disabled className="input-base bg-muted cursor-not-allowed" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">FINESS</label><input value={form.finess} onChange={e => maj('finess', e.target.value)} className="input-base" /></div>
            </div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Type</label><input value={getLabelTypeEtablissement(type)} disabled className="input-base bg-muted cursor-not-allowed" /></div>
            {/* A2: Convention collective */}
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Convention collective</label>
              <select
                value={conventionCollective}
                onChange={e => setConventionCollective(e.target.value)}
                className="input-base"
              >
                <option value="">— Sélectionner —</option>
                {CONVENTIONS_COLLECTIVES.map(c => (
                  <option key={c.valeur} value={c.valeur}>{c.label}</option>
                ))}
              </select>
            </div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Adresse</h2>
          <div className="space-y-3">
            <input aria-label="Rue" value={form.rue} onChange={e => maj('rue', e.target.value)} placeholder="Rue" className="input-base" />
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
              <input aria-label="Ville" value={form.ville} onChange={e => maj('ville', e.target.value)} placeholder="Ville" className="input-base" />
              <input aria-label="Code postal" value={form.codePostal} onChange={e => maj('codePostal', e.target.value)} placeholder="Code postal" className="input-base" />
              <input aria-label="Département" value={form.departement} onChange={e => maj('departement', e.target.value)} placeholder="Département" className="input-base" />
            </div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Contact</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email</label><input type="email" value={form.emailContact} onChange={e => maj('emailContact', e.target.value)} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephoneContact} onChange={e => maj('telephoneContact', e.target.value)} className="input-base" /></div>
          </div>
          {/* SMS notifications toggle */}
          <div className="flex items-center justify-between mt-4 pt-4 border-t border-border">
            <div className="flex-1">
              <p className="text-sm text-foreground font-medium">Notifications SMS</p>
              <p className="text-xs text-muted-foreground mt-1">
                {consentementSMS
                  ? 'Vous recevrez un SMS en cas d\'annulation tardive ou d\'alerte critique.'
                  : 'Activez pour recevoir les alertes critiques par SMS.'}
              </p>
            </div>
            <Switch
              checked={consentementSMS}
              disabled={smsToggling}
              onCheckedChange={async (checked) => {
                setSmsToggling(true);
                const { error } = await supabase
                  .from('etablissements')
                  .update({ sms_actif: checked, sms_consent_le: checked ? new Date().toISOString() : null })
                  .eq('id', user!.id);
                if (error) {
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
                } else {
                  setConsentementSMS(checked);
                  await supabase.rpc('fn_ecrire_audit_safe', {
                    p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
                    p_action: checked ? 'SMS_CONSENTEMENT_ACTIVE' : 'SMS_CONSENTEMENT_RETIRE',
                    p_type_ressource: 'etablissement', p_id_ressource: user!.id,
                    p_cle_s3: null, p_details: { sms_actif: checked },
                    p_ip: null, p_navigateur: navigator.userAgent,
                  });
                  afficherNotification({
                    type: checked ? 'succes' : 'avertissement',
                    message: checked ? 'Notifications SMS activées.' : 'Notifications SMS désactivées.',
                  });
                }
                setSmsToggling(false);
              }}
            />
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Géolocalisation</h2>
          <div className="space-y-3">
            <button type="button" onClick={demanderGeolocalisation} disabled={geoLoading} className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50">
              {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
              {geoLoading ? 'Récupération en cours…' : '📍 Localiser mon établissement'}
            </button>
            <p className="text-xs text-muted-foreground mt-2">
              {lat && lng
                ? <>📍 Position enregistrée — l'adresse est renseignée automatiquement dans les champs ci-dessus. <span className="opacity-60">(coordonnées techniques : {Number(lat).toFixed(4)}, {Number(lng).toFixed(4)})</span></>
                : "Cliquez sur « Localiser » pour positionner votre établissement (l'adresse sera remplie automatiquement)."}
            </p>
          </div>
        </div>
        <div className="card-base">
          <div className="flex items-start gap-2 rounded-xl bg-primary/5 border border-primary/20 p-3 mb-4">
            <Info className="h-4 w-4 text-primary mt-0.5 flex-shrink-0" />
            <p className="text-xs text-primary">Ces taux s'appliquent automatiquement au calcul de la rémunération. Par défaut : Convention FPH.</p>
          </div>
          <h2 className="text-base font-semibold text-foreground mb-4">Taux de majoration (Convention)</h2>
          <div className="space-y-3">
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nuit (21h-06h) — %</label><input type="number" step="0.01" value={form.tauxNuit} onChange={e => maj('tauxNuit', Number(e.target.value))} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Dimanche — %</label><input type="number" step="0.01" value={form.tauxDimanche} onChange={e => maj('tauxDimanche', Number(e.target.value))} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Jours fériés — %</label><input type="number" step="0.01" value={form.tauxFerie} onChange={e => maj('tauxFerie', Number(e.target.value))} className="input-base" /></div>
          </div>
        </div>
        {/* Mode de paiement commission */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">💳 Mode de paiement de la commission</h2>
          <div className="space-y-3">
            {[
              { value: 'STRIPE_RESERVATION', icon: '💳', label: 'Carte bancaire', desc: 'Commission prélevée à chaque mission (autorisée à la réservation, capturée à la fin)' },
              { value: 'SEPA_DEBIT', icon: '🏦', label: 'Prélèvement SEPA automatique', desc: '', isSEPA: true },
              { value: 'FACTURE_MENSUELLE', icon: '📄', label: 'Facture mensuelle par virement', desc: 'Facture de commission émise chaque mois, à régler par virement sous 30 jours' },
              ...(['HOPITAL_PUBLIC', 'CHU', 'CENTRE_SANTE', 'HAD'].includes(type)
                ? [{ value: 'CHORUS_PRO', icon: '🏛️', label: 'Chorus Pro', desc: 'Dépôt automatique pour les établissements publics' }]
                : []),
            ].map(opt => (
              <label
                key={opt.value}
                className={`flex items-start gap-3 p-3 rounded-xl border-2 cursor-pointer transition ${
                  modePaiement === opt.value
                    ? 'border-primary bg-primary/5'
                    : 'border-border hover:border-primary/30'
                }`}
              >
                <input
                  type="radio"
                  name="modePaiement"
                  value={opt.value}
                  checked={modePaiement === opt.value}
                  onChange={() => setModePaiement(opt.value)}
                  className="mt-1 accent-primary"
                />
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">{opt.icon} {opt.label}</p>
                  {opt.isSEPA ? (
                    <p className="text-xs text-success mt-0.5">✅ Prélèvement automatique — votre facture mensuelle de commission est prélevée sans action de votre part. Plus rien à régler manuellement.</p>
                  ) : (
                    <p className="text-xs text-muted-foreground mt-0.5">{opt.desc}</p>
                  )}
                </div>
              </label>
            ))}
          </div>

          {/* SEPA IBAN setup section */}
          {modePaiement === 'SEPA_DEBIT' && (
            <SepaSetupSection userId={user?.id} />
          )}
        </div>

        {/* Couleur de thème */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
            <Palette className="h-5 w-5 text-primary" /> Couleur de votre établissement
          </h2>
          <div className="flex items-center gap-4">
            <input
              type="color"
              value={couleurTheme}
              onChange={e => setCouleurTheme(e.target.value)}
              className="w-12 h-12 rounded-xl border border-border cursor-pointer"
              aria-label="Choisir la couleur de l'établissement"
            />
            <div className="flex-1">
              <p className="text-sm text-muted-foreground">Cette couleur apparaît sur vos cartes mission.</p>
              <div className="mt-2 rounded-xl border border-border overflow-hidden">
                <div className="h-1" style={{ backgroundColor: couleurTheme }} />
                <div className="p-3 text-xs text-muted-foreground">Aperçu de la bande colorée</div>
              </div>
            </div>
          </div>
        </div>

        {/* Contrat de service Jolene */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
            <FileCheck className="h-5 w-5 text-primary" /> Contrat de service Jolene
          </h2>

          {contratValide ? (
            <div className="flex items-center gap-2 p-3 rounded-xl bg-success/10 border border-success/20">
              <FileCheck className="h-4 w-4 text-success" />
              <span className="text-sm font-medium text-success">✅ Contrat validé par Jolene</span>
            </div>
          ) : contratUrl ? (
            <div className="flex items-center gap-2 p-3 rounded-xl bg-warning/10 border border-warning/20">
              <Clock className="h-4 w-4 text-warning" />
              <div>
                <span className="text-sm font-medium text-foreground">⏳ En attente de validation</span>
                {contratUploadeLe && <p className="text-xs text-muted-foreground mt-0.5">Téléversé le {new Date(contratUploadeLe).toLocaleDateString('fr-FR')}</p>}
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2 p-3 rounded-xl bg-muted border border-border">
              <AlertTriangle className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm font-medium text-muted-foreground">Non fourni</span>
            </div>
          )}

          <div className="mt-4">
            <input
              ref={contratInputRef}
              type="file"
              accept="application/pdf"
              className="hidden"
              onChange={async (e) => {
                const file = e.target.files?.[0];
                if (!file || !user) return;
                if (file.type !== 'application/pdf') {
                  afficherNotification({ type: 'erreur', message: 'Seuls les fichiers PDF sont acceptés.' });
                  return;
                }
                if (file.size > 20 * 1024 * 1024) {
                  afficherNotification({ type: 'erreur', message: 'Le fichier ne doit pas dépasser 20 Mo.' });
                  return;
                }
                setUploadingContrat(true);
                const fileName = `${user.id}/contrat-service-${Date.now()}.pdf`;
                const { error: uploadErr } = await supabase.storage.from('jolene-documents').upload(fileName, file, { upsert: true });
                if (uploadErr) {
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(uploadErr) });
                  setUploadingContrat(false);
                  return;
                }
                const { data: urlData } = await supabase.storage.from('jolene-documents').createSignedUrl(fileName, 300);
                const contratSignedUrl = urlData?.signedUrl || '';
                const { error: updateErr } = await supabase.rpc('fn_modifier_mon_etablissement' as any, {
                  p_contrat_url: fileName, // Store path, not public URL
                });
                if (updateErr) {
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(updateErr) });
                } else {
                  setContratUrl(fileName);
                  setContratUploadeLe(new Date().toISOString());
                  setContratValide(false);
                  // Re-vérification IA à chaque re-upload (type + SIRET + identité signataire).
                  supabase.functions.invoke('verify-contrat-etablissement', {
                    body: { etablissement_id: user.id },
                  }).catch(() => { /* best-effort */ });
                  afficherNotification({ type: 'succes', message: 'Contrat téléversé. Vérification IA en cours, puis validation par Jolene.' });
                }
                setUploadingContrat(false);
              }}
            />
            <button
              type="button"
              onClick={() => contratInputRef.current?.click()}
              disabled={uploadingContrat}
              className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50"
            >
              {uploadingContrat ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
              {uploadingContrat ? 'Envoi en cours…' : contratUrl ? 'Remplacer le contrat' : 'Téléverser votre contrat signé (PDF)'}
            </button>
          </div>
        </div>

        <button type="submit" disabled={saving} className="btn-primary w-full md:w-auto disabled:opacity-50">
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </form>

      {/* Widget embarquable */}
      <div className="max-w-2xl mt-8">
        <div className="card-base space-y-3">
          <h2 className="text-base font-semibold text-foreground">Widget recrutement</h2>
          <p className="text-xs text-muted-foreground">Intégrez vos missions ouvertes sur votre site web :</p>
          <div className="bg-muted rounded-lg p-3 font-mono text-xs text-foreground break-all select-all">
            {`<iframe src="${window.location.origin}/widget-recrutement?etab=${user?.id}" width="100%" height="500" frameborder="0"></iframe>`}
          </div>
          <button
            type="button"
            onClick={() => {
              navigator.clipboard.writeText(`<iframe src="${window.location.origin}/widget-recrutement?etab=${user?.id}" width="100%" height="500" frameborder="0"></iframe>`);
              afficherNotification({ type: 'succes', message: 'Snippet copié !' });
            }}
            className="text-sm font-medium text-primary hover:underline"
          >
            📋 Copier le snippet
          </button>
        </div>
      </div>

      {/* RGPD / Suppression compte (obligation Apple) */}
      <div className="max-w-2xl mt-12 space-y-4">
        <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">Données personnelles (RGPD)</h2>
        <button
          disabled={exportingRgpd}
          onClick={async () => {
            if (exportingRgpd) return;
            setExportingRgpd(true);
            try {
              const { data, error } = await supabase.rpc('fn_exporter_rgpd_etablissement' as any);
              if (error) throw error;
              if (data && typeof data === 'object' && (data as any).error) {
                afficherNotification({ type: 'erreur', message: (data as any).error });
                return;
              }
              await telechargerOuPartager(JSON.stringify(data, null, 2), `mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.json`, 'application/json');
              // C3: Audit RGPD export for establishments
              await supabase.rpc('fn_ecrire_audit_safe', {
                p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
                p_action: 'RGPD_EXPORT_DONNEES', p_type_ressource: 'etablissement',
                p_id_ressource: user!.id, p_cle_s3: null,
                p_details: { source: 'profil_etablissement' },
                p_ip: null, p_navigateur: navigator.userAgent,
              });
              afficherNotification({ type: 'succes', message: 'Données exportées.' });
            } catch (err: any) {
              capturerErreurSentry(err, 'ProfilEtablissement', 'export_rgpd');
              afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
            } finally {
              setExportingRgpd(false);
            }
          }}
          className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition disabled:opacity-50"
        >
          <Download className="h-4 w-4" /> {exportingRgpd ? 'Export en cours…' : '📥 Télécharger mes données (RGPD)'}
        </button>
        <button
          onClick={() => setShowDeleteModal(true)}
          className="flex items-center gap-2 text-sm text-destructive hover:text-destructive/80 transition"
        >
          <Trash2 className="h-4 w-4" /> Supprimer mon compte
        </button>
      </div>

      {/* Modale de confirmation de suppression */}
      {showDeleteModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-background rounded-2xl p-6 max-w-md w-full shadow-xl space-y-4">
            <h3 className="text-lg font-bold text-destructive">⚠️ Suppression définitive</h3>
            <p className="text-sm text-muted-foreground">
              Cette action est irréversible. Toutes vos données seront supprimées conformément au RGPD.
            </p>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Tapez <span className="font-bold text-destructive">SUPPRIMER</span> pour confirmer
              </label>
              <input
                value={deleteConfirmText}
                onChange={e => setDeleteConfirmText(e.target.value)}
                placeholder="SUPPRIMER"
                className="input-base"
                autoFocus
              />
            </div>
            <div className="flex gap-3 justify-end">
              <button
                type="button"
                onClick={() => { setShowDeleteModal(false); setDeleteConfirmText(''); }}
                className="px-4 py-2 text-sm rounded-xl border border-border text-foreground hover:bg-muted transition"
              >
                Annuler
              </button>
              <button
                type="button"
                disabled={deleteConfirmText !== 'SUPPRIMER' || deleting}
                onClick={async () => {
                  setDeleting(true);
                  try {
                    const { data, error } = await supabase.rpc('fn_supprimer_compte_etablissement_rate_limited' as any);
                    if (error) throw error;
                    if (data?.error) { afficherNotification({ type: 'erreur', message: data.error }); setDeleting(false); return; }
                    afficherNotification({ type: 'succes', message: 'Compte supprimé. Redirection…' });
                    await supabase.auth.signOut();
                    navigate('/');
                  } catch (err: any) {
                    capturerErreurSentry(err, 'ProfilEtablissement', 'supprimer_compte');
                    afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
                    setDeleting(false);
                  }
                }}
                className="px-4 py-2 text-sm rounded-xl bg-destructive text-destructive-foreground font-semibold disabled:opacity-40 transition"
              >
                {deleting ? 'Suppression…' : 'Confirmer la suppression'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Déconnexion — visible uniquement sur mobile */}
      <div className="md:hidden mt-6 pt-6 border-t border-border">
        <button
          onClick={async () => { await deconnexion(); navigate('/'); }}
          className="btn-secondary w-full flex items-center justify-center gap-2 text-destructive border-destructive/30 hover:bg-destructive/5"
        >
          <LogOut className="h-4 w-4" /> Se déconnecter
        </button>
      </div>
    </>
  );
}
