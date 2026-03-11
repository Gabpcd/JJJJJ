import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CONTRATS, getLabelProfession } from '@/lib/constantes';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';

export default function ProfilSoignant() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [email, setEmail] = useState('');
  const [profession, setProfession] = useState('');
  const [form, setForm] = useState({
    prenom: '', nom: '', telephone: '', dateNaissance: '',
    typeContrat: '', rpps: '', adeli: '',
    lat: '', lng: '', rayon: 30,
  });

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('*').eq('id', user.id).single().then(({ data }) => {
      if (data) {
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
      }
      setLoading(false);
    });
  }, [user]);

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    setSaving(true);
    const { error } = await supabase.from('soignants').update({
      prenom: form.prenom, nom: form.nom,
      telephone: form.telephone || null, date_naissance: form.dateNaissance || null,
      type_contrat: form.typeContrat || null, numero_rpps: form.rpps || null,
      numero_adeli: form.adeli || null, rayon_deplacement_km: form.rayon,
      adresse_lat: form.lat ? parseFloat(form.lat) : null,
      adresse_lng: form.lng ? parseFloat(form.lng) : null,
      modifie_le: new Date().toISOString(),
    } as any).eq('id', user.id);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_MODIFICATION', p_type_ressource: 'soignant',
        p_id_ressource: user.id, p_cle_s3: null,
        p_details: { champs_modifies: Object.keys(form) },
        p_ip: null, p_navigateur: navigator.userAgent,
      }).then(() => {});
      afficherNotification({ type: 'succes', message: 'Profil mis à jour avec succès !' });
    }
    setSaving(false);
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-6">Mon profil</h1>
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
              <label className="text-sm font-medium text-foreground mb-1.5 block">Type de contrat</label>
              <select value={form.typeContrat} onChange={e => maj('typeContrat', e.target.value)} className="input-base">
                {CONTRATS.map(c => <option key={c.valeur} value={c.valeur}>{c.label}</option>)}
              </select>
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
        <button type="submit" disabled={saving} className="btn-primary w-full md:w-auto disabled:opacity-50">
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </form>
    </LayoutApp>
  );
}
