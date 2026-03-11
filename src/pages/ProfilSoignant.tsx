import React, { useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { SelectProfession } from '@/components/SelectProfession';
import { CONTRATS, getLabelProfession } from '@/lib/constantes';
import { MOCK_SOIGNANT } from '@/lib/mock-data';
import { useNotification } from '@/contexts/NotificationContext';

export default function ProfilSoignant() {
  const { afficherNotification } = useNotification();
  const [form, setForm] = useState({
    prenom: MOCK_SOIGNANT.prenom,
    nom: MOCK_SOIGNANT.nom,
    telephone: MOCK_SOIGNANT.telephone || '',
    dateNaissance: MOCK_SOIGNANT.date_naissance || '',
    profession: MOCK_SOIGNANT.profession,
    typeContrat: MOCK_SOIGNANT.type_contrat,
    rpps: MOCK_SOIGNANT.numero_rpps || '',
    adeli: MOCK_SOIGNANT.numero_adeli || '',
    lat: MOCK_SOIGNANT.adresse_lat?.toString() || '',
    lng: MOCK_SOIGNANT.adresse_lng?.toString() || '',
    rayon: MOCK_SOIGNANT.rayon_deplacement_km,
  });

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    afficherNotification({ type: 'succes', message: 'Profil mis à jour avec succès !' });
  };

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-6">Mon profil</h1>

      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        {/* Identité */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Identité</h2>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Prénom</label>
                <input value={form.prenom} onChange={e => maj('prenom', e.target.value)} className="input-base" />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Nom</label>
                <input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" />
              </div>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label>
              <input value={form.telephone} onChange={e => maj('telephone', e.target.value)} className="input-base" />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance</label>
              <input type="date" value={form.dateNaissance} onChange={e => maj('dateNaissance', e.target.value)} className="input-base" />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
              <input value={MOCK_SOIGNANT.email} disabled className="input-base bg-muted cursor-not-allowed" />
            </div>
          </div>
        </div>

        {/* Professionnel */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Professionnel</h2>
          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Profession</label>
              <input value={getLabelProfession(form.profession)} disabled className="input-base bg-muted cursor-not-allowed" />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Type de contrat</label>
              <select value={form.typeContrat} onChange={e => maj('typeContrat', e.target.value)} className="input-base">
                {CONTRATS.map(c => <option key={c.valeur} value={c.valeur}>{c.label}</option>)}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">RPPS</label>
                <input value={form.rpps} onChange={e => maj('rpps', e.target.value.replace(/\D/g, '').slice(0, 11))} className="input-base" />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">ADELI</label>
                <input value={form.adeli} onChange={e => maj('adeli', e.target.value)} className="input-base" />
              </div>
            </div>
          </div>
        </div>

        {/* Localisation */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Localisation</h2>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Latitude</label>
                <input type="number" step="any" value={form.lat} onChange={e => maj('lat', e.target.value)} className="input-base" />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Longitude</label>
                <input type="number" step="any" value={form.lng} onChange={e => maj('lng', e.target.value)} className="input-base" />
              </div>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Rayon de déplacement : <span className="text-primary font-bold">{form.rayon} km</span>
              </label>
              <input type="range" min={5} max={100} value={form.rayon} onChange={e => maj('rayon', Number(e.target.value))} className="w-full accent-primary" />
              <div className="flex justify-between text-[10px] text-muted-foreground">
                <span>5 km</span><span>100 km</span>
              </div>
            </div>
          </div>
        </div>

        <button type="submit" className="btn-primary w-full md:w-auto">
          Enregistrer les modifications
        </button>
      </form>
    </LayoutApp>
  );
}
