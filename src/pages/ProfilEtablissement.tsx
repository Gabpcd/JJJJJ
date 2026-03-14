import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { handleErrorSilent } from '@/lib/handleError';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { Info, MapPin, Loader2, Download, Trash2, Palette } from 'lucide-react';
import { AvatarUpload } from '@/components/AvatarUpload';

const CONVENTIONS_COLLECTIVES = [
  { valeur: 'CCN_51_FEHAP', label: 'CCN 51 (FEHAP)' },
  { valeur: 'CCN_66_SOCIAL', label: 'CCN 66 (Social)' },
  { valeur: 'CCN_FHP_PRIVE', label: 'CCN FHP (Privé)' },
  { valeur: 'CCN_PHARMACIE', label: 'CCN Pharmacie' },
  { valeur: 'FPH', label: 'Fonction Publique Hospitalière' },
  { valeur: 'AUTRE', label: 'Autre' },
];

export default function ProfilEtablissement() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [siret, setSiret] = useState('');
  const [type, setType] = useState('');
  const [conventionCollective, setConventionCollective] = useState('');
  const [form, setForm] = useState({
    nom: '', finess: '', rue: '', ville: '', codePostal: '', departement: '',
    emailContact: '', telephoneContact: '',
    tauxNuit: 25, tauxDimanche: 50, tauxFerie: 100,
  });

  useEffect(() => {
    if (!user) return;
    supabase.from('etablissements').select('nom, siret, finess, type, convention_collective, adresse_rue, adresse_ville, adresse_code_postal, adresse_departement, email_contact, telephone_contact, taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent, taux_majoration_ferie_pourcent, logo_url').eq('id', user.id).single().then(({ data }) => {
      if (data) {
        setSiret(data.siret);
        setType(data.type);
        setConventionCollective(data.convention_collective || '');
        setForm({
          nom: data.nom, finess: data.finess || '',
          rue: data.adresse_rue || '', ville: data.adresse_ville || '',
          codePostal: data.adresse_code_postal || '', departement: data.adresse_departement || '',
          emailContact: data.email_contact || '', telephoneContact: data.telephone_contact || '',
          tauxNuit: data.taux_majoration_nuit_pourcent ?? 25,
          tauxDimanche: data.taux_majoration_dimanche_pourcent ?? 50,
          tauxFerie: data.taux_majoration_ferie_pourcent ?? 100,
        });
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
  const [couleurTheme, setCouleurTheme] = useState('#17A2B8');

  useEffect(() => {
    if (!user) return;
    supabase.from('etablissements').select('adresse_lat, adresse_lng, couleur_theme').eq('id', user.id).single().then(({ data }) => {
      if (data) {
        setLat(data.adresse_lat?.toString() || '');
        setLng(data.adresse_lng?.toString() || '');
        setCouleurTheme(data.couleur_theme || '#17A2B8');
      }
    });
  }, [user]);

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const demanderGeolocalisation = () => {
    if (!navigator.geolocation) {
      afficherNotification({ type: 'erreur', message: 'La géolocalisation n\'est pas supportée par votre navigateur.' });
      return;
    }
    setGeoLoading(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLat(position.coords.latitude.toString());
        setLng(position.coords.longitude.toString());
        setGeoLoading(false);
        afficherNotification({ type: 'succes', message: 'Position récupérée avec succès !' });
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
      p_telephone_contact: form.telephoneContact || null,
      p_adresse_lat: lat ? parseFloat(lat) : null,
      p_adresse_lng: lng ? parseFloat(lng) : null,
      p_taux_majoration_nuit: form.tauxNuit,
      p_taux_majoration_dimanche: form.tauxDimanche,
      p_taux_majoration_ferie: form.tauxFerie,
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

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex items-center gap-4 mb-6">
        <AvatarUpload
          src={(form as any).logoUrl}
          prenom={form.nom}
          nom=""
          size={96}
          mode="etablissement"
          onUploaded={(url) => setForm(prev => ({ ...prev, logoUrl: url } as any))}
        />
        <h1 className="text-xl font-bold text-foreground">Profil de l'établissement</h1>
      </div>

      {noteMoyenne && noteMoyenne.total > 0 && (
        <div className="card-base mb-6">
          <p className="text-lg font-bold text-foreground">⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}</p>
        </div>
      )}
      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Informations générales</h2>
          <div className="space-y-3">
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nom</label><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" /></div>
            <div className="grid grid-cols-2 gap-3">
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
            <input value={form.rue} onChange={e => maj('rue', e.target.value)} placeholder="Rue" className="input-base" />
            <div className="grid grid-cols-3 gap-2">
              <input value={form.ville} onChange={e => maj('ville', e.target.value)} placeholder="Ville" className="input-base" />
              <input value={form.codePostal} onChange={e => maj('codePostal', e.target.value)} placeholder="Code postal" className="input-base" />
              <input value={form.departement} onChange={e => maj('departement', e.target.value)} placeholder="Département" className="input-base" />
            </div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Contact</h2>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email</label><input type="email" value={form.emailContact} onChange={e => maj('emailContact', e.target.value)} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephoneContact} onChange={e => maj('telephoneContact', e.target.value)} className="input-base" /></div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Géolocalisation</h2>
          <div className="space-y-3">
            <button type="button" onClick={demanderGeolocalisation} disabled={geoLoading} className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50">
              {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
              {geoLoading ? 'Récupération en cours…' : '📍 Localiser mon établissement'}
            </button>
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Latitude</label><input type="number" step="any" value={lat} onChange={e => setLat(e.target.value)} className="input-base" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Longitude</label><input type="number" step="any" value={lng} onChange={e => setLng(e.target.value)} className="input-base" /></div>
            </div>
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
          onClick={async () => {
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
              afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
            }
          }}
          className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition"
        >
          <Download className="h-4 w-4" /> 📥 Télécharger mes données (RGPD)
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
                    const { data, error } = await supabase.rpc('fn_supprimer_mon_compte' as any);
                    if (error) throw error;
                    if (data?.error) { afficherNotification({ type: 'erreur', message: data.error }); setDeleting(false); return; }
                    afficherNotification({ type: 'succes', message: 'Compte supprimé. Redirection…' });
                    await supabase.auth.signOut();
                    navigate('/');
                  } catch (err: any) {
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
    </LayoutApp>
  );
}
