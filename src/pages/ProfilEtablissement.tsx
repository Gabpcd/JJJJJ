import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { Info, MapPin, Loader2 } from 'lucide-react';

export default function ProfilEtablissement() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [siret, setSiret] = useState('');
  const [type, setType] = useState('');
  const [form, setForm] = useState({
    nom: '', finess: '', rue: '', ville: '', codePostal: '', departement: '',
    emailContact: '', telephoneContact: '',
    tauxNuit: 25, tauxDimanche: 50, tauxFerie: 100,
  });

  useEffect(() => {
    if (!user) return;
    supabase.from('etablissements').select('*').eq('id', user.id).single().then(({ data }) => {
      if (data) {
        setSiret(data.siret);
        setType(data.type);
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
  }, [user]);

  const [geoLoading, setGeoLoading] = useState(false);
  const [lat, setLat] = useState('');
  const [lng, setLng] = useState('');

  // Load existing coords
  useEffect(() => {
    if (!user) return;
    supabase.from('etablissements').select('adresse_lat, adresse_lng').eq('id', user.id).single().then(({ data }) => {
      if (data) {
        setLat(data.adresse_lat?.toString() || '');
        setLng(data.adresse_lng?.toString() || '');
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
      (erreur) => {
        console.log('Géolocalisation refusée:', erreur.message);
        setGeoLoading(false);
        afficherNotification({ type: 'erreur', message: 'Localisation refusée. Vous pouvez saisir les coordonnées manuellement.' });
      }
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    setSaving(true);
    const { error } = await supabase.from('etablissements').update({
      nom: form.nom, finess: form.finess || null,
      adresse_rue: form.rue, adresse_ville: form.ville,
      adresse_code_postal: form.codePostal, adresse_departement: form.departement || null,
      email_contact: form.emailContact, telephone_contact: form.telephoneContact || null,
      adresse_lat: lat ? parseFloat(lat) : null,
      adresse_lng: lng ? parseFloat(lng) : null,
      taux_majoration_nuit_pourcent: form.tauxNuit,
      taux_majoration_dimanche_pourcent: form.tauxDimanche,
      taux_majoration_ferie_pourcent: form.tauxFerie,
      modifie_le: new Date().toISOString(),
    } as any).eq('id', user.id);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'DONNEES_PERSO_MODIFICATION', p_type_ressource: 'etablissement',
        p_id_ressource: user.id, p_cle_s3: null,
        p_details: { champs_modifies: Object.keys(form) },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      if (auditError) console.error('Audit failed:', auditError);
      afficherNotification({ type: 'succes', message: 'Informations mises à jour avec succès !' });
    }
    setSaving(false);
  };

  if (loading) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ETABLISSEMENT">
      <h1 className="text-xl font-bold text-foreground mb-6">Profil de l'établissement</h1>
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
        <button type="submit" disabled={saving} className="btn-primary w-full md:w-auto disabled:opacity-50">
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </form>
    </LayoutApp>
  );
}
