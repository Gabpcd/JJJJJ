import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { handleErrorSilent } from '@/lib/handleError';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CONTRATS, getLabelProfession, getTypesContratSoignant } from '@/lib/constantes';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { MapPin, Loader2, Download, Trash2, MapPinOff } from 'lucide-react';
import { Switch } from '@/components/ui/switch';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function ProfilSoignant() {
  const { user, deconnexion } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [email, setEmail] = useState('');
  const [profession, setProfession] = useState('');
  const [form, setForm] = useState({
    prenom: '', nom: '', telephone: '', dateNaissance: '',
    typeContrat: '', rpps: '', adeli: '',
    lat: '', lng: '', rayon: 30,
  });
  const [typesContrat, setTypesContrat] = useState<string[]>(['CDDU']);
  const [consentementGPS, setConsentementGPS] = useState(true);
  const [gpsToggling, setGpsToggling] = useState(false);

  // RGPD states
  const [exportLoading, setExportLoading] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [deleteLoading, setDeleteLoading] = useState(false);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('prenom, nom, email, telephone, date_naissance, profession, type_contrat, types_contrat_acceptes, numero_rpps, numero_adeli, rpps_verifie, adresse_lat, adresse_lng, rayon_deplacement_km, consentement_gps, score_fiabilite, heures_cumulees, assujetti_tva, numero_tva').eq('id', user.id).single().then(({ data }) => {
      if (data) {
        supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'soignant', p_id_ressource: user.id,
          p_cle_s3: null, p_details: { page: 'profil' },
          p_ip: null, p_navigateur: navigator.userAgent,
        });
        setEmail(data.email);
        setProfession(data.profession);
        setForm({
          prenom: data.prenom, nom: data.nom,
          telephone: data.telephone || '', dateNaissance: data.date_naissance || '',
          typeContrat: data.type_contrat || '', rpps: data.numero_rpps || '',
          adeli: data.numero_adeli || '',
          lat: data.adresse_lat?.toString() || '', lng: data.adresse_lng?.toString() || '',
          rayon: data.rayon_deplacement_km ?? 30,
        });
        setTypesContrat(getTypesContratSoignant(data as any));
        setConsentementGPS((data as any).consentement_gps !== false);
      }
      setLoading(false);
    });
  }, [user]);

  const [geoLoading, setGeoLoading] = useState(false);
  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const toggleContrat = (valeur: string) => {
    setTypesContrat(prev => {
      if (prev.includes(valeur)) {
        if (prev.length <= 1) return prev;
        return prev.filter(v => v !== valeur);
      }
      return [...prev, valeur];
    });
  };

  const demanderGeolocalisation = () => {
    if (!navigator.geolocation) {
      afficherNotification({ type: 'erreur', message: 'La géolocalisation n\'est pas supportée par votre navigateur.' });
      return;
    }
    setGeoLoading(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        maj('lat', position.coords.latitude.toString());
        maj('lng', position.coords.longitude.toString());
        setGeoLoading(false);
        afficherNotification({ type: 'succes', message: 'Position récupérée avec succès !' });
      },
      () => {
        setGeoLoading(false);
        afficherNotification({ type: 'erreur', message: 'Localisation refusée. Vous pouvez saisir votre adresse manuellement.' });
      }
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    setSaving(true);
    const { data: rpcResult, error } = await supabase.rpc('fn_modifier_mon_profil' as any, {
      p_telephone: form.telephone || null,
      p_adresse_rue: null, p_adresse_ville: null, p_adresse_code_postal: null,
      p_rayon_deplacement_km: form.rayon,
      p_prenom: form.prenom || null, p_nom: form.nom || null,
      p_date_naissance: form.dateNaissance || null,
      p_type_contrat: typesContrat[0] || null,
      p_types_contrat_acceptes: JSON.stringify(typesContrat),
      p_numero_rpps: form.rpps || null, p_numero_adeli: form.adeli || null,
      p_adresse_lat: form.lat ? parseFloat(form.lat) : null,
      p_adresse_lng: form.lng ? parseFloat(form.lng) : null,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else if (rpcResult?.error) {
      afficherNotification({ type: 'erreur', message: rpcResult.error });
    } else {
      afficherNotification({ type: 'succes', message: 'Profil mis à jour avec succès !' });
    }
    setSaving(false);
  };

  // B2: Export RGPD
  const handleExportRGPD = async () => {
    setExportLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_exporter_mes_donnees' as any);
      if (error) throw error;
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `mes-donnees-soin-direct-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
      afficherNotification({ type: 'succes', message: 'Données exportées avec succès.' });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setExportLoading(false);
  };

  // B3: Suppression compte
  const handleSupprimerCompte = async () => {
    setDeleteLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_supprimer_mon_compte' as any);
      if (error) throw error;
      if (data?.error) {
        afficherNotification({ type: 'erreur', message: data.error });
        setDeleteLoading(false);
        return;
      }
      afficherNotification({ type: 'succes', message: 'Compte supprimé. Redirection...' });
      await supabase.auth.signOut();
      navigate('/');
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setDeleteLoading(false);
    setShowDeleteModal(false);
  };

  const [noteMoyenne, setNoteMoyenne] = useState<{ moyenne: number; total: number } | null>(null);
  const [evaluations, setEvaluations] = useState<any[]>([]);

  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_note_moyenne' as any, { p_user_id: user.id })
      .then(({ data }: any) => {
        if (data && typeof data === 'object') setNoteMoyenne(data);
        else if (Array.isArray(data) && data[0]) setNoteMoyenne(data[0]);
      });
    supabase.rpc('fn_mes_evaluations_recues' as any)
      .then(({ data }: any) => {
        if (Array.isArray(data)) setEvaluations(data);
      });
  }, [user]);

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-6">Mon profil</h1>

      {noteMoyenne && noteMoyenne.total > 0 && (
        <div className="card-base mb-6">
          <h2 className="text-base font-semibold text-foreground mb-2">Évaluations reçues</h2>
          <p className="text-lg font-bold text-foreground">⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}</p>
          {evaluations.length > 0 && (
            <div className="mt-3 space-y-2">
              {evaluations.slice(0, 5).map((ev: any, i: number) => (
                <div key={i} className="text-sm text-muted-foreground border-t border-border pt-2">
                  <span className="text-foreground font-medium">{'⭐'.repeat(ev.note)}</span>
                  {ev.commentaire && <p className="text-xs mt-0.5">{ev.commentaire}</p>}
                  {ev.cree_le && <p className="text-[10px] text-muted-foreground/60">{format(new Date(ev.cree_le), 'd MMM yyyy', { locale: fr })}</p>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Identité</h2>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Prénom</label><input value={form.prenom} onChange={e => maj('prenom', e.target.value)} className="input-base" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nom</label><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" /></div>
            </div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephone} onChange={e => maj('telephone', e.target.value)} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance</label><input type="date" value={form.dateNaissance} onChange={e => maj('dateNaissance', e.target.value)} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email</label><input value={email} disabled className="input-base bg-muted cursor-not-allowed" /></div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Professionnel</h2>
          <div className="space-y-3">
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Profession</label><input value={getLabelProfession(profession)} disabled className="input-base bg-muted cursor-not-allowed" /></div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Types de contrat acceptés</label>
              <p className="text-xs text-muted-foreground mb-2">Cochez tous les types de contrat que vous acceptez</p>
              <div className="space-y-2">
                {CONTRATS.map(c => (
                  <label key={c.valeur} className="flex items-center gap-3 cursor-pointer group">
                    <input type="checkbox" checked={typesContrat.includes(c.valeur)} onChange={() => toggleContrat(c.valeur)} className="h-4 w-4 rounded border-border text-primary focus:ring-primary accent-primary" />
                    <span className="text-sm text-foreground group-hover:text-primary transition-colors">{c.label}</span>
                  </label>
                ))}
              </div>
              {typesContrat.length === 0 && <p className="text-xs text-destructive mt-1">Sélectionnez au moins un type de contrat</p>}
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">RPPS</label><input value={form.rpps} onChange={e => maj('rpps', e.target.value.replace(/\D/g, '').slice(0, 11))} className="input-base" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">ADELI</label><input value={form.adeli} onChange={e => maj('adeli', e.target.value)} className="input-base" /></div>
            </div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Localisation</h2>
          <div className="space-y-3">
            <button type="button" onClick={demanderGeolocalisation} disabled={geoLoading} className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50">
              {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
              {geoLoading ? 'Récupération en cours…' : '📍 Utiliser ma position actuelle'}
            </button>
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Latitude</label><input type="number" step="any" value={form.lat} onChange={e => maj('lat', e.target.value)} className="input-base" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Longitude</label><input type="number" step="any" value={form.lng} onChange={e => maj('lng', e.target.value)} className="input-base" /></div>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Rayon de déplacement : <span className="text-primary font-bold">{form.rayon} km</span></label>
              <input type="range" min={5} max={100} value={form.rayon} onChange={e => maj('rayon', Number(e.target.value))} className="w-full accent-primary" />
              <div className="flex justify-between text-[10px] text-muted-foreground"><span>5 km</span><span>100 km</span></div>
            </div>
          </div>
        </div>

        {/* Consentement GPS */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Consentement GPS</h2>
          <div className="flex items-center justify-between">
            <div className="flex-1">
              <p className="text-sm text-foreground font-medium">Autoriser la géolocalisation lors des pointages</p>
              <p className="text-xs text-muted-foreground mt-1">
                {consentementGPS
                  ? 'Votre position sera capturée uniquement au moment de l\'arrivée et du départ.'
                  : '⚠️ Sans GPS, vos pointages nécessiteront une vérification manuelle par l\'établissement.'}
              </p>
            </div>
            <Switch
              checked={consentementGPS}
              disabled={gpsToggling}
              onCheckedChange={async (checked) => {
                setGpsToggling(true);
                const { data, error } = await supabase.rpc('fn_consentir_gps' as any, { p_accepte: checked });
                if (error) {
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
                } else if (data && (data as any).error) {
                  afficherNotification({ type: 'erreur', message: (data as any).error });
                } else {
                  setConsentementGPS(checked);
                  afficherNotification({
                    type: checked ? 'succes' : 'avertissement',
                    message: checked ? 'Consentement GPS activé.' : 'Consentement GPS retiré. Vérification manuelle requise.',
                  });
                }
                setGpsToggling(false);
              }}
            />
          </div>
        </div>
        <button type="submit" disabled={saving} className="btn-primary w-full md:w-auto disabled:opacity-50">
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </form>

      {/* RGPD Section */}
      <div className="max-w-2xl mt-12 space-y-4">
        <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">Données personnelles (RGPD)</h2>

        {/* B2: Export RGPD */}
        <button
          onClick={handleExportRGPD}
          disabled={exportLoading}
          className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition disabled:opacity-50"
        >
          <Download className="h-4 w-4" />
          {exportLoading ? 'Export en cours…' : '📥 Télécharger mes données (RGPD)'}
        </button>

        {/* B3: Suppression compte */}
        <button
          onClick={() => setShowDeleteModal(true)}
          className="flex items-center gap-2 text-sm text-destructive hover:text-destructive/80 transition"
        >
          <Trash2 className="h-4 w-4" /> Supprimer mon compte
        </button>
      </div>

      {/* B3: Modal suppression */}
      {showDeleteModal && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center">
          <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={() => setShowDeleteModal(false)} />
          <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full">
            <h3 className="text-lg font-bold text-destructive mb-2">🗑️ Supprimer mon compte</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Cette action est irréversible. Vos données seront anonymisées conformément au RGPD. Tapez <strong>SUPPRIMER</strong> pour confirmer.
            </p>
            <input
              value={deleteConfirmText}
              onChange={e => setDeleteConfirmText(e.target.value)}
              placeholder="Tapez SUPPRIMER"
              className="input-base mb-4"
            />
            <div className="flex gap-3 justify-end">
              <button onClick={() => { setShowDeleteModal(false); setDeleteConfirmText(''); }} className="btn-secondary text-sm px-4 py-2">Annuler</button>
              <button
                onClick={handleSupprimerCompte}
                disabled={deleteConfirmText !== 'SUPPRIMER' || deleteLoading}
                className="btn-danger text-sm px-4 py-2 disabled:opacity-50"
              >
                {deleteLoading ? 'Suppression…' : 'Supprimer définitivement'}
              </button>
            </div>
          </div>
        </div>
      )}
    </LayoutApp>
  );
}
