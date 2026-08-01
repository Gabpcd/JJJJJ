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
import { extraireMessageErreur, messageErreurEdgeFn } from '@/lib/erreurs';
import { reverseGeocode } from '@/lib/geocodage';
import { getCurrentPosition as obtenirGeoloc } from '@/lib/geoloc';
import { capturerErreurSentry } from '@/lib/sentry';
import { verifierFichierDocument } from '@/lib/documentUpload';
import { supabase } from '@/integrations/supabase/client';
import { Info, MapPin, Loader2, Download, Trash2, Palette, Building2, Upload, FileCheck, Clock, AlertTriangle, Lock } from 'lucide-react';
import { AvatarUpload } from '@/components/AvatarUpload';
import { Switch } from '@/components/ui/switch';
import { Elements, IbanElement, useStripe, useElements } from '@stripe/react-stripe-js';
import { isStripeConfigured, stripePromise } from '@/lib/stripe';
import { contratServiceEstSigne } from '@/lib/contratEtablissement';

interface DeleteAccountResponse {
  success?: boolean;
  error?: string;
}

type SepaSetupResponse = {
  client_secret?: string;
  billing_name?: string;
  billing_email?: string;
  success?: boolean;
  has_sepa?: boolean;
  last4?: string;
  error?: string;
};

async function appelerSetupSepa(body: Record<string, unknown>): Promise<SepaSetupResponse> {
  const { data, error } = await supabase.functions.invoke('setup-sepa', { body });
  if (error) {
    throw new Error(await messageErreurEdgeFn(error, 'Le service de paiement est temporairement indisponible.'));
  }
  const response = (data || {}) as SepaSetupResponse;
  if (response.error) throw new Error(response.error);
  return response;
}

// SEPA IBAN Form (inside Stripe Elements)
function SepaIbanForm({
  onSuccess,
  onCancel,
}: {
  onSuccess: (last4: string) => void;
  onCancel?: () => void;
}) {
  const stripe = useStripe();
  const elements = useElements();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [ibanComplete, setIbanComplete] = useState(false);
  const [mandateAccepted, setMandateAccepted] = useState(false);
  const [pendingSetupIntentId, setPendingSetupIntentId] = useState<string | null>(null);

  const finaliserMandat = async (setupIntentId: string) => {
    const result = await appelerSetupSepa({
      action: 'finalize_setup_intent',
      setup_intent_id: setupIntentId,
    });
    if (!result.success || !result.last4) {
      throw new Error("Le mandat SEPA n'a pas pu être enregistré. Réessayez.");
    }
    setPendingSetupIntentId(null);
    onSuccess(result.last4);
  };

  const handleSubmit = async () => {
    if (!stripe || !elements) return;
    setSubmitting(true);
    setError('');
    try {
      if (pendingSetupIntentId) {
        await finaliserMandat(pendingSetupIntentId);
        return;
      }
      if (!mandateAccepted) {
        throw new Error('Confirmez votre habilitation et le mandat SEPA avant de continuer.');
      }

      const ibanElement = elements.getElement(IbanElement);
      if (!ibanElement || !ibanComplete) {
        throw new Error('Saisissez un IBAN SEPA complet et valide.');
      }

      const setup = await appelerSetupSepa({ action: 'create_setup_intent' });
      if (!setup.client_secret || !setup.billing_name || !setup.billing_email) {
        throw new Error("Le mandat SEPA n'a pas pu être initialisé. Réessayez.");
      }

      const { error: stripeError, setupIntent } = await stripe.confirmSepaDebitSetup(
        setup.client_secret,
        {
          payment_method: {
            sepa_debit: ibanElement,
            billing_details: {
              name: setup.billing_name,
              email: setup.billing_email,
            },
          },
        },
      );
      if (stripeError) {
        throw new Error(stripeError.message || "Stripe n'a pas pu confirmer le mandat SEPA.");
      }
      if (!setupIntent?.id) {
        throw new Error("Stripe n'a pas renvoyé le mandat confirmé. Réessayez.");
      }

      // Conserver uniquement l'identifiant non secret permet de relancer la
      // finalisation après une coupure réseau sans ressaisir ni exposer l'IBAN.
      setPendingSetupIntentId(setupIntent.id);
      if (setupIntent.status !== 'succeeded') {
        throw new Error('Le mandat est encore en cours de confirmation. Réessayez dans quelques instants.');
      }
      await finaliserMandat(setupIntent.id);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Erreur lors de la configuration SEPA');
    } finally {
      setSubmitting(false);
    }
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
          onChange={(event) => {
            setIbanComplete(event.complete);
            if (event.error?.message) setError(event.error.message);
          }}
        />
      </div>
      {error && <p className="text-xs text-destructive" role="alert" aria-live="polite">{error}</p>}
      <label className="flex items-start gap-2 text-xs text-foreground cursor-pointer">
        <input
          type="checkbox"
          checked={mandateAccepted}
          onChange={(event) => setMandateAccepted(event.target.checked)}
          disabled={submitting || !!pendingSetupIntentId}
          className="mt-0.5 accent-primary"
        />
        <span>Je confirme être habilité(e) à engager cet établissement et j'accepte le mandat de prélèvement SEPA.</span>
      </label>
      <button
        type="button"
        onClick={handleSubmit}
        disabled={submitting || !stripe || (!pendingSetupIntentId && (!ibanComplete || !mandateAccepted))}
        className="btn-primary text-sm w-full disabled:opacity-50"
      >
        {submitting
          ? 'Validation…'
          : !stripe
            ? '⏳ Chargement Stripe…'
            : pendingSetupIntentId
              ? 'Réessayer la finalisation du mandat'
              : '🏦 Confirmer le mandat SEPA'}
      </button>
      {onCancel && !submitting && !pendingSetupIntentId && (
        <button type="button" onClick={onCancel} className="btn-secondary text-sm w-full">
          Annuler
        </button>
      )}
      {!stripe && <p className="text-[10px] text-warning">Le module de paiement charge. Patientez quelques secondes…</p>}
      <p className="text-[10px] text-muted-foreground">
        En fournissant votre IBAN et en confirmant, vous autorisez Jolene à envoyer des instructions à votre banque pour débiter votre compte conformément au mandat SEPA. Vous bénéficiez d'un droit au remboursement selon votre convention bancaire ; la demande doit être présentée dans les 8 semaines suivant le débit.
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
    if (!userId) {
      setLoading(false);
      return;
    }
    (async () => {
      try {
        const data = await appelerSetupSepa({ action: 'get_sepa_status' });
        setSepaStatus({ has_sepa: data.has_sepa === true, last4: data.last4 });
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
            <span className="text-sm font-medium text-success">Mandat SEPA actif · IBAN •••• {sepaStatus.last4}</span>
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

  if (!isStripeConfigured) {
    return (
      <div className="mt-4 p-3 rounded-xl bg-warning/10 border border-warning/20">
        <p className="text-xs text-warning">Configuration Stripe manquante. Contactez le support.</p>
      </div>
    );
  }

  return (
    <div className="mt-4">
      <Elements stripe={stripePromise} options={{ locale: 'fr' }}>
        <SepaIbanForm
          onSuccess={(last4) => { setSepaStatus({ has_sepa: true, last4 }); setShowForm(false); }}
          onCancel={sepaStatus?.has_sepa ? () => setShowForm(false) : undefined}
        />
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

// Lot 11 : convention PROPOSÉE d'après le type d'établissement — une clinique
// privée ne doit jamais hériter de la FPH par défaut (fausse les majorations).
// L'établissement confirme avant d'enregistrer, rien n'est imposé.
const CONVENTION_PAR_TYPE: Record<string, string> = {
  HOPITAL_PUBLIC: 'FPH', CHU: 'FPH', CENTRE_SANTE: 'FPH', HAD: 'FPH',
  CLINIQUE_PRIVEE: 'CCN_FHP_PRIVE', EHPAD_PRIVE: 'CCN_51_FEHAP',
  PHARMACIE_OFFICINE: 'CCN_PHARMACIE',
};

export default function ProfilEtablissement() {
  usePageTitle('Profil');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <ProfilEtablissementContent />
    </LayoutApp>
  );
}

// Lot 12 : sections affichables — permet de redistribuer les blocs de ce
// composant entre les onglets de Paramètres (Profil / Facturation /
// Opérations / Sécurité & RGPD) sans dupliquer états ni handlers.
export type SectionProfilEtab = 'profil' | 'facturation' | 'geoloc' | 'securite';

export function ProfilEtablissementContent({ sections }: { sections?: SectionProfilEtab[] } = {}) {
  const { user, deconnexion } = useAuth();
  // Défaut (prop absente) : tout est visible — rétro-compatibilité totale.
  const visible = (s: SectionProfilEtab) => !sections || sections.includes(s);
  // Le <form> + « Enregistrer » ne se rendent que si au moins une section
  // formulaire est visible (la section sécurité n'a pas de formulaire).
  const formVisible = visible('profil') || visible('geoloc') || visible('facturation');
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
  const [conventionSuggeree, setConventionSuggeree] = useState(false);
  const [modePaiement, setModePaiement] = useState('FACTURE_MENSUELLE');
  const [etablissementId, setEtablissementId] = useState<string | null>(null);
  const [ribKey, setRibKey] = useState<string | null>(null);
  const [ribCoherent, setRibCoherent] = useState<boolean | null>(null);
  const [ribLast4, setRibLast4] = useState<string | null>(null);
  const [uploadingRib, setUploadingRib] = useState(false);
  const ribInputRef = React.useRef<HTMLInputElement>(null);
  const [contratValide, setContratValide] = useState(false);
  const [contratServiceSigne, setContratServiceSigne] = useState(false);
  const [contratServiceSigneLe, setContratServiceSigneLe] = useState<string | null>(null);
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
        setEtablissementId(data.id || user.id);
        setSiret(data.siret);
        setType(data.type);
        if (data.convention_collective) {
          setConventionCollective(data.convention_collective);
        } else {
          // Pas encore choisie : proposer celle du type d'établissement (à confirmer).
          setConventionCollective(CONVENTION_PAR_TYPE[data.type] || '');
          setConventionSuggeree(!!CONVENTION_PAR_TYPE[data.type]);
        }
        setModePaiement((data as any).mode_paiement_commission || 'FACTURE_MENSUELLE');
        setContratValide(!!data.contrat_valide);
        setContratServiceSigne(contratServiceEstSigne(data));
        setContratServiceSigneLe(data.contrat_service_signe_le || null);
        setContratUrl(data.contrat_url || null);
        setContratUploadeLe(data.contrat_uploade_le || null);
        setRibKey(data.rib_s3_key || null);
        setRibCoherent(data.rib_ia_coherent ?? null);
        setRibLast4(data.iban_last4 || null);
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

  const televerserRibEtablissement = async (file: File) => {
    const cibleId = etablissementId || user?.id;
    if (!user || !cibleId) return;
    const validation = await verifierFichierDocument(file);
    if (validation.ok === false) {
      afficherNotification({ type: 'erreur', message: validation.message });
      return;
    }
    const path = `${cibleId}/rib-etablissement-${Date.now()}-${globalThis.crypto.randomUUID()}.${validation.extension}`;
    const ancienRibKey = ribKey;
    setUploadingRib(true);
    try {
      const { error: uploadError } = await supabase.storage
        .from('jolene-documents')
        .upload(path, file, { contentType: validation.mime, upsert: false });
      if (uploadError) throw uploadError;

      const { data: updated, error: updateError } = await supabase
        .from('etablissements')
        .update({ rib_s3_key: path })
        .eq('id', cibleId)
        .select('id')
        .maybeSingle();
      if (updateError || !updated) {
        await supabase.functions.invoke('verify-rib-etablissement', {
          body: { action: 'cleanup_orphan', etablissement_id: cibleId, rib_s3_key: path },
        });
        throw updateError || new Error('Établissement introuvable');
      }

      if (ancienRibKey && ancienRibKey !== path) {
        void supabase.functions.invoke('verify-rib-etablissement', {
          body: { action: 'cleanup_orphan', etablissement_id: cibleId, rib_s3_key: ancienRibKey },
        });
      }

      const { data, error } = await supabase.functions.invoke('verify-rib-etablissement', {
        body: { etablissement_id: cibleId },
      });
      setRibKey(path);
      if (error) {
        setRibCoherent(null);
        setRibLast4(null);
        afficherNotification({ type: 'avertissement', message: await messageErreurEdgeFn(error, 'RIB enregistré. Sa vérification reste en attente.') });
        return;
      }
      setRibCoherent(data?.coherent ?? null);
      setRibLast4(data?.analysis?.iban_last4 || null);
      if (data?.coherent === true) {
        afficherNotification({ type: 'succes', message: 'RIB vérifié : titulaire et IBAN concordants.' });
      } else if (data?.coherent === false) {
        afficherNotification({ type: 'erreur', message: data?.motif || 'Ce RIB ne correspond pas à l’établissement.' });
      } else {
        afficherNotification({ type: 'avertissement', message: data?.motif || 'RIB reçu — une revue manuelle est nécessaire.' });
      }
    } catch (error) {
      afficherNotification({ type: 'erreur', message: error instanceof Error ? error.message : extraireMessageErreur(error) });
    } finally {
      setUploadingRib(false);
      if (ribInputRef.current) ribInputRef.current.value = '';
    }
  };

  // Lot 11 : la position de l'établissement (socle du géofencing F1) se pose
  // par GÉOCODAGE DE L'ADRESSE (BAN) — pas par le GPS du téléphone de la
  // personne qui remplit le profil. Toute nouvelle position (BAN ou GPS de
  // secours) passe par une CONFIRMATION explicite avant d'écraser l'existante.
  const [positionEnAttente, setPositionEnAttente] = useState<{ lat: number; lng: number; label: string; source: 'adresse' | 'gps' } | null>(null);

  const localiserDepuisAdresse = async () => {
    const q = [form.rue, form.codePostal, form.ville].filter(Boolean).join(' ').trim();
    if (q.length < 6) {
      afficherNotification({ type: 'erreur', message: 'Renseignez d\'abord l\'adresse (rue, code postal, ville) ci-dessus.' });
      return;
    }
    setGeoLoading(true);
    try {
      const res = await fetch(`https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(q)}&limit=1`);
      const json = await res.json();
      const f = json?.features?.[0];
      if (f?.geometry?.coordinates) {
        const [lo, la] = f.geometry.coordinates as [number, number];
        setPositionEnAttente({ lat: la, lng: lo, label: f.properties?.label || q, source: 'adresse' });
      } else {
        afficherNotification({ type: 'erreur', message: 'Adresse introuvable dans la Base Adresse Nationale — vérifiez la saisie.' });
      }
    } catch {
      afficherNotification({ type: 'erreur', message: 'Géocodage indisponible pour le moment. Réessayez.' });
    }
    setGeoLoading(false);
  };

  const demanderGeolocalisation = async () => {
    setGeoLoading(true);
    try {
      const position = await obtenirGeoloc({ enableHighAccuracy: true, timeout: 15_000 });
      const la = position.coords.latitude, lo = position.coords.longitude;
      const adr = await reverseGeocode(la, lo);
      // Jamais d'écrasement direct : la position part en confirmation.
      setPositionEnAttente({ lat: la, lng: lo, label: adr?.label || `${la.toFixed(4)}, ${lo.toFixed(4)}`, source: 'gps' });
    } catch {
      afficherNotification({ type: 'erreur', message: 'Localisation refusée ou indisponible. Utilisez « Localiser depuis l\'adresse ».' });
    } finally {
      setGeoLoading(false);
    }
  };

  const confirmerPosition = async () => {
    if (!positionEnAttente) return;
    setLat(positionEnAttente.lat.toString());
    setLng(positionEnAttente.lng.toString());
    if (positionEnAttente.source === 'gps') {
      const adr = await reverseGeocode(positionEnAttente.lat, positionEnAttente.lng);
      if (adr) setForm((prev: any) => ({ ...prev, rue: adr.rue || prev.rue, ville: adr.ville || prev.ville, codePostal: adr.codePostal || prev.codePostal }));
    }
    setPositionEnAttente(null);
    afficherNotification({ type: 'succes', message: 'Position confirmée — pensez à enregistrer le profil.' });
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    // Lot 11 : FINESS = 9 chiffres, taux de majoration bornes 0-200 %.
    if (form.finess && !/^\d{9}$/.test(form.finess)) {
      afficherNotification({ type: 'erreur', message: 'Le numéro FINESS comporte exactement 9 chiffres.' });
      return;
    }
    if ([form.tauxNuit, form.tauxDimanche, form.tauxFerie].some(t => t < 0 || t > 200 || Number.isNaN(t))) {
      afficherNotification({ type: 'erreur', message: 'Les taux de majoration doivent être compris entre 0 et 200 %.' });
      return;
    }
    setSaving(true);

    // C3: Validate couleur_theme format before saving
    const hexRegex = /^#[0-9a-fA-F]{6}$/;
    if (!hexRegex.test(couleurTheme)) {
      afficherNotification({ type: 'erreur', message: 'Couleur invalide. Format attendu : #RRGGBB' });
      setSaving(false);
      return;
    }

    const { data: saveResult, error } = await supabase.rpc('fn_modifier_mon_etablissement' as any, {
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

    const saveBusinessError = saveResult && typeof saveResult === 'object'
      && 'error' in saveResult && typeof saveResult.error === 'string'
      ? saveResult.error
      : null;
    if (error || saveBusinessError) {
      afficherNotification({
        type: 'erreur',
        message: saveBusinessError || extraireMessageErreur(error),
      });
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
      {visible('profil') && (
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
      )}

      {visible('profil') && noteMoyenne && noteMoyenne.total > 0 && (
        <div className="card-base mb-6">
          <p className="text-lg font-bold text-foreground">⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}</p>
        </div>
      )}

      {/* Même verrou canonique que la publication de mission. */}
      {visible('facturation') && !contratServiceSigne && (
        <div className="max-w-2xl mb-6 rounded-xl border border-warning/30 bg-warning/10 p-4 flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-warning mt-0.5 flex-shrink-0" />
          <div>
            <p className="text-sm font-semibold text-foreground">Contrat de service à signer</p>
            <p className="text-xs text-muted-foreground mt-1">
              La signature électronique du contrat de service est obligatoire avant de publier une mission.
            </p>
            <button
              type="button"
              onClick={() => navigate('/etablissement/activer')}
              className="mt-2 text-xs font-semibold text-primary hover:underline"
            >
              Signer le contrat →
            </button>
          </div>
        </div>
      )}

      {formVisible && (
      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        {visible('profil') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Informations générales</h2>
          <div className="space-y-3">
            <div><label htmlFor="etablissement-nom" className="text-sm font-medium text-foreground mb-1.5 block">Nom</label><input id="etablissement-nom" value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" /></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label htmlFor="etablissement-siret" className="text-sm font-medium text-foreground mb-1.5 flex items-center gap-1">SIRET <Lock aria-hidden="true" className="h-3 w-3 text-muted-foreground" /></label>
                <input id="etablissement-siret" value={siret} disabled className="input-base bg-muted cursor-not-allowed" aria-describedby="siret-lock" />
                <p id="siret-lock" className="text-[10px] text-muted-foreground mt-1">Verrouillé : identifiant légal vérifié à l'inscription.</p>
              </div>
              <div>
                <label htmlFor="etablissement-finess" className="text-sm font-medium text-foreground mb-1.5 block">FINESS</label>
                <input
                  id="etablissement-finess"
                  value={form.finess}
                  onChange={e => maj('finess', e.target.value.replace(/\D/g, '').slice(0, 9))}
                  inputMode="numeric"
                  placeholder="9 chiffres"
                  className={`input-base ${form.finess && form.finess.length !== 9 ? 'border-destructive' : ''}`}
                />
                {form.finess && form.finess.length !== 9 && (
                  <p className="text-[10px] text-destructive mt-1">Le numéro FINESS comporte 9 chiffres.</p>
                )}
              </div>
            </div>
            <div><label htmlFor="etablissement-type" className="text-sm font-medium text-foreground mb-1.5 block">Type</label><input id="etablissement-type" value={getLabelTypeEtablissement(type)} disabled className="input-base bg-muted cursor-not-allowed" /></div>
            {/* A2: Convention collective */}
            <div>
              <label htmlFor="etablissement-convention" className="text-sm font-medium text-foreground mb-1.5 block">Convention collective</label>
              <select
                id="etablissement-convention"
                value={conventionCollective}
                onChange={e => { setConventionCollective(e.target.value); setConventionSuggeree(false); }}
                className="input-base"
              >
                <option value="">— Sélectionner —</option>
                {CONVENTIONS_COLLECTIVES.map(c => (
                  <option key={c.valeur} value={c.valeur}>{c.label}</option>
                ))}
              </select>
              {conventionSuggeree && (
                <p className="text-[10px] text-primary mt-1">
                  Proposée d'après votre type d'établissement — vérifiez qu'elle correspond bien avant d'enregistrer.
                </p>
              )}
            </div>
          </div>
        </div>
        )}
        {visible('profil') && (
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
        )}
        {visible('profil') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Contact</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div><label htmlFor="etablissement-email-contact" className="text-sm font-medium text-foreground mb-1.5 block">Email</label><input id="etablissement-email-contact" type="email" value={form.emailContact} onChange={e => maj('emailContact', e.target.value)} className="input-base" /></div>
            <div><label htmlFor="etablissement-telephone-contact" className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input id="etablissement-telephone-contact" value={form.telephoneContact} onChange={e => maj('telephoneContact', e.target.value)} className="input-base" /></div>
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
              aria-label="Recevoir les notifications SMS critiques"
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
        )}
        {visible('geoloc') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Géolocalisation</h2>
          <div className="space-y-3">
            <button type="button" onClick={localiserDepuisAdresse} disabled={geoLoading} className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50">
              {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" aria-hidden="true" />}
              {geoLoading ? 'Recherche en cours…' : 'Localiser depuis l\'adresse'}
            </button>
            <button type="button" onClick={demanderGeolocalisation} disabled={geoLoading} className="w-full text-xs text-muted-foreground underline underline-offset-2 disabled:opacity-50">
              Ou utiliser la position de cet appareil (moins fiable)
            </button>

            {positionEnAttente && (
              <div className="rounded-xl border border-primary/30 bg-primary/5 p-3 space-y-2">
                <p className="text-sm font-medium text-foreground">Confirmer cette position ?</p>
                <p className="text-xs text-muted-foreground">{positionEnAttente.label}</p>
                <a
                  href={`https://www.openstreetmap.org/?mlat=${positionEnAttente.lat}&mlon=${positionEnAttente.lng}#map=18/${positionEnAttente.lat}/${positionEnAttente.lng}`}
                  target="_blank" rel="noopener noreferrer"
                  className="text-xs text-primary underline"
                >
                  Vérifier sur la carte →
                </a>
                <div className="flex gap-2 pt-1">
                  <button type="button" onClick={confirmerPosition} className="btn-primary text-xs flex-1">Confirmer la position</button>
                  <button type="button" onClick={() => setPositionEnAttente(null)} className="btn-secondary text-xs flex-1">Annuler</button>
                </div>
              </div>
            )}

            <p className="text-xs text-muted-foreground mt-2">
              {lat && lng
                ? <>Position enregistrée <span className="opacity-60">(coordonnées : {Number(lat).toFixed(4)}, {Number(lng).toFixed(4)})</span>. Elle sert au pointage géolocalisé des soignants.</>
                : 'La position se calcule depuis votre adresse (Base Adresse Nationale) et sert au pointage géolocalisé des soignants.'}
            </p>
          </div>
        </div>
        )}
        {visible('profil') && (
        <div className="card-base">
          <div className="flex items-start gap-2 rounded-xl bg-primary/5 border border-primary/20 p-3 mb-4">
            <Info className="h-4 w-4 text-primary mt-0.5 flex-shrink-0" />
            <p className="text-xs text-primary">Ces taux s'appliquent automatiquement au calcul de la rémunération, selon la convention collective choisie ci-dessus.</p>
          </div>
          <h2 className="text-base font-semibold text-foreground mb-4">Taux de majoration (Convention)</h2>
          <div className="space-y-3">
            <div><label htmlFor="etablissement-taux-nuit" className="text-sm font-medium text-foreground mb-1.5 block">Nuit (21h-06h) — %</label><input id="etablissement-taux-nuit" type="number" step="0.01" min={0} max={200} value={form.tauxNuit} onChange={e => maj('tauxNuit', Number(e.target.value))} className="input-base" /></div>
            <div><label htmlFor="etablissement-taux-dimanche" className="text-sm font-medium text-foreground mb-1.5 block">Dimanche — %</label><input id="etablissement-taux-dimanche" type="number" step="0.01" min={0} max={200} value={form.tauxDimanche} onChange={e => maj('tauxDimanche', Number(e.target.value))} className="input-base" /></div>
            <div><label htmlFor="etablissement-taux-ferie" className="text-sm font-medium text-foreground mb-1.5 block">Jours fériés — %</label><input id="etablissement-taux-ferie" type="number" step="0.01" min={0} max={200} value={form.tauxFerie} onChange={e => maj('tauxFerie', Number(e.target.value))} className="input-base" /></div>
            {[form.tauxNuit, form.tauxDimanche, form.tauxFerie].some(t => t < 0 || t > 200) && (
              <p className="text-[10px] text-destructive">Un taux de majoration se situe entre 0 et 200 %.</p>
            )}
          </div>
        </div>
        )}
        {/* Mode de paiement commission */}
        {visible('facturation') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">💳 Mode de paiement de la commission</h2>
          <div className="space-y-3">
            {[
              { value: 'SEPA_DEBIT', icon: '🏦', label: 'Prélèvement SEPA automatique', desc: '', isSEPA: true },
              { value: 'FACTURE_MENSUELLE', icon: '📄', label: 'Factures par virement', desc: 'Chaque facture de commission indique sa propre échéance et se règle par virement' },
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
                    <p className="text-xs text-success mt-0.5">✅ Prélèvement automatique — les factures éligibles sont présentées au prélèvement après leur émission, lors du prochain traitement automatique.</p>
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
        )}

        {/* RIB de facturation : vérification distincte du mandat SEPA. */}
        {visible('facturation') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
            <Building2 className="h-5 w-5 text-primary" aria-hidden="true" /> RIB de l’établissement
          </h2>
          <p className="text-xs text-muted-foreground mb-4">
            Le titulaire et l’IBAN sont contrôlés par rapport à l’identité juridique de l’établissement. L’IBAN complet n’est jamais affiché après vérification.
          </p>

          <div aria-live="polite" className={`flex items-start gap-2 p-3 rounded-xl border ${
            ribCoherent === true
              ? 'bg-success/10 border-success/20'
              : ribCoherent === false
                ? 'bg-destructive/5 border-destructive/20'
                : ribKey
                  ? 'bg-warning/10 border-warning/20'
                  : 'bg-muted border-border'
          }`}>
            {ribCoherent === true ? (
              <FileCheck className="h-4 w-4 text-success shrink-0 mt-0.5" aria-hidden="true" />
            ) : ribCoherent === false ? (
              <AlertTriangle className="h-4 w-4 text-destructive shrink-0 mt-0.5" aria-hidden="true" />
            ) : ribKey ? (
              <Clock className="h-4 w-4 text-warning shrink-0 mt-0.5" aria-hidden="true" />
            ) : (
              <AlertTriangle className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" aria-hidden="true" />
            )}
            <div>
              <p className="text-sm font-medium text-foreground">
                {ribCoherent === true
                  ? `RIB vérifié${ribLast4 ? ` — IBAN se terminant par ${ribLast4}` : ''}`
                  : ribCoherent === false
                    ? 'RIB non concordant — remplacez-le ou contactez le support'
                    : ribKey
                      ? 'RIB reçu — revue manuelle nécessaire'
                      : 'Aucun RIB fourni'}
              </p>
              {ribCoherent === false && (
                <p className="text-xs text-muted-foreground mt-0.5">Le document ne permet pas de confirmer à la fois le titulaire et un IBAN valide.</p>
              )}
            </div>
          </div>

          <input
            ref={ribInputRef}
            type="file"
            accept="application/pdf,image/jpeg,image/png,image/webp"
            className="hidden"
            aria-label="Choisir le RIB de l’établissement"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) void televerserRibEtablissement(file);
            }}
          />
          <button
            type="button"
            onClick={() => ribInputRef.current?.click()}
            disabled={uploadingRib}
            className="mt-4 w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50"
          >
            {uploadingRib ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Upload className="h-4 w-4" aria-hidden="true" />}
            {uploadingRib ? 'Vérification en cours…' : ribKey ? 'Remplacer le RIB' : 'Téléverser un RIB'}
          </button>
        </div>
        )}

        {/* Couleur de thème */}
        {visible('profil') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
            <Palette className="h-5 w-5 text-primary" /> Couleur de votre établissement
          </h2>
          <div className="flex items-center gap-4">
            {/* Lot 11 : palette curatée — pas de rouge/orange (réservés aux états
                sémantiques erreur/warning des cartes). */}
            <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Couleur de l'établissement">
              {['#E04590', '#8B5CF6', '#06B6D4', '#2563EB', '#059669', '#0D9488', '#4F46E5', '#475569'].map((c) => (
                <button
                  key={c}
                  type="button"
                  role="radio"
                  aria-checked={couleurTheme.toLowerCase() === c.toLowerCase()}
                  aria-label={`Couleur ${c}`}
                  onClick={() => setCouleurTheme(c)}
                  className={`h-9 w-9 rounded-full border-2 transition-transform ${couleurTheme.toLowerCase() === c.toLowerCase() ? 'border-foreground scale-110' : 'border-transparent hover:scale-105'}`}
                  style={{ backgroundColor: c }}
                />
              ))}
            </div>
            <div className="flex-1">
              <p className="text-sm text-muted-foreground">Cette couleur apparaît sur vos cartes mission.</p>
              <div className="mt-2 rounded-xl border border-border overflow-hidden">
                <div className="h-1" style={{ backgroundColor: couleurTheme }} />
                <div className="p-3 text-xs text-muted-foreground">Aperçu de la bande colorée</div>
              </div>
            </div>
          </div>
        </div>
        )}

        {/* Contrat de service Jolene */}
        {visible('facturation') && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
            <FileCheck className="h-5 w-5 text-primary" /> Contrat de service Jolene
          </h2>

          {contratServiceSigne ? (
            <div className="flex items-center gap-2 p-3 rounded-xl bg-success/10 border border-success/20">
              <FileCheck className="h-4 w-4 text-success" />
              <div>
                <span className="text-sm font-medium text-success">Contrat de service signé</span>
                {contratServiceSigneLe && (
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Signé le {new Date(contratServiceSigneLe).toLocaleDateString('fr-FR')}
                  </p>
                )}
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2 p-3 rounded-xl bg-warning/10 border border-warning/20">
              <AlertTriangle className="h-4 w-4 text-warning" />
              <div>
                <span className="text-sm font-medium text-foreground">Contrat de service à signer</span>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Cette signature est obligatoire avant de publier une mission.
                </p>
                <button
                  type="button"
                  onClick={() => navigate('/etablissement/activer')}
                  className="mt-2 text-xs font-semibold text-primary hover:underline"
                >
                  Signer le contrat →
                </button>
              </div>
            </div>
          )}

          <div className="mt-4 border-t border-border pt-4">
            <p className="mb-2 text-xs text-muted-foreground">
              Document contractuel PDF complémentaire
              {contratValide ? ' — contrôlé par Jolene' : contratUrl ? ' — en cours de contrôle' : ''}
              {contratUploadeLe ? ` (téléversé le ${new Date(contratUploadeLe).toLocaleDateString('fr-FR')})` : ''}
            </p>
            <input
              ref={contratInputRef}
              type="file"
              accept="application/pdf"
              className="hidden"
              onChange={async (e) => {
                const file = e.target.files?.[0];
                if (!file || !user) return;
                const validation = await verifierFichierDocument(file, {
                  allowedMimes: ['application/pdf'],
                });
                if (validation.ok === false) {
                  afficherNotification({ type: 'erreur', message: validation.message });
                  e.target.value = '';
                  return;
                }
                setUploadingContrat(true);
                const cibleId = etablissementId || user.id;
                const fileName = `${cibleId}/contrat-service-${Date.now()}.pdf`;
                const ancienContratUrl = contratUrl;
                const { error: uploadErr } = await supabase.storage.from('jolene-documents').upload(fileName, file, {
                  contentType: validation.mime,
                  upsert: false,
                });
                if (uploadErr) {
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(uploadErr) });
                  setUploadingContrat(false);
                  e.target.value = '';
                  return;
                }
                const { error: updateErr } = await supabase.rpc('fn_modifier_mon_etablissement' as any, {
                  p_contrat_url: fileName, // Store path, not public URL
                });
                if (updateErr) {
                  await supabase.functions.invoke('verify-contrat-etablissement', {
                    body: { action: 'cleanup_orphan', etablissement_id: cibleId, contrat_url: fileName },
                  });
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(updateErr) });
                } else {
                  setContratUrl(fileName);
                  setContratUploadeLe(new Date().toISOString());
                  setContratValide(false);
                  // Re-vérification IA à chaque re-upload (type + SIRET + identité signataire).
                  supabase.functions.invoke('verify-contrat-etablissement', {
                    body: { etablissement_id: cibleId },
                  }).catch(() => { /* best-effort */ });
                  if (ancienContratUrl && ancienContratUrl !== fileName) {
                    void supabase.functions.invoke('verify-contrat-etablissement', {
                      body: { action: 'cleanup_orphan', etablissement_id: cibleId, contrat_url: ancienContratUrl },
                    });
                  }
                  afficherNotification({ type: 'succes', message: 'Contrat téléversé. Vérification IA en cours, puis validation par Jolene.' });
                }
                setUploadingContrat(false);
                e.target.value = '';
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
        )}

        {/* Lot 11 : Enregistrer sticky — toujours accessible sur un long formulaire mobile */}
        <div className="sticky bottom-4 z-10">
          <button type="submit" disabled={saving} className="btn-primary w-full md:w-auto disabled:opacity-50 shadow-lg">
            {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
          </button>
        </div>
      </form>
      )}

      {/* Widget embarquable */}
      {visible('profil') && (
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
      )}

      {/* RGPD / Suppression compte (obligation Apple) */}
      {visible('securite') && (
      <div id="suppression-compte" className="scroll-mt-24">
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
      </div>
      )}

      {/* Modale de confirmation de suppression */}
      {visible('securite') && showDeleteModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-background rounded-2xl p-6 max-w-md w-full shadow-xl space-y-4">
            <h3 className="text-lg font-bold text-destructive">⚠️ Suppression définitive</h3>
            <p className="text-sm text-muted-foreground">
              Cette action est irréversible. Toutes vos données seront supprimées conformément au RGPD.
            </p>
            <div>
              <label htmlFor="etablissement-confirmation-suppression" className="text-sm font-medium text-foreground mb-1.5 block">
                Tapez <span className="font-bold text-destructive">SUPPRIMER</span> pour confirmer
              </label>
              <input
                id="etablissement-confirmation-suppression"
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
                    const { data, error } = await supabase.functions.invoke<DeleteAccountResponse>('delete-account', { body: {} });
                    if (error) throw error;
                    if (data?.error || data?.success !== true) { afficherNotification({ type: 'erreur', message: data?.error || 'Suppression impossible.' }); setDeleting(false); return; }
                    afficherNotification({ type: 'succes', message: 'Compte supprimé. Redirection…' });
                    await supabase.auth.signOut({ scope: 'local' });
                    navigate('/');
                  } catch (err: unknown) {
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

      {/* Lot 11 : Se déconnecter unique — il vit en fin de Mon compte
          (le doublon mobile de cet onglet est retiré). */}
    </>
  );
}
