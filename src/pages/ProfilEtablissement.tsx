import React, { useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { MOCK_ETABLISSEMENT } from '@/lib/mock-data';
import { getLabelTypeEtablissement } from '@/lib/constantes';
import { useNotification } from '@/contexts/NotificationContext';
import { Info } from 'lucide-react';

export default function ProfilEtablissement() {
  const { afficherNotification } = useNotification();
  const [form, setForm] = useState({
    nom: MOCK_ETABLISSEMENT.nom,
    finess: MOCK_ETABLISSEMENT.finess || '',
    rue: MOCK_ETABLISSEMENT.adresse_rue || '',
    ville: MOCK_ETABLISSEMENT.adresse_ville || '',
    codePostal: MOCK_ETABLISSEMENT.adresse_code_postal || '',
    departement: MOCK_ETABLISSEMENT.adresse_departement || '',
    emailContact: MOCK_ETABLISSEMENT.email_contact || '',
    telephoneContact: MOCK_ETABLISSEMENT.telephone_contact || '',
    tauxNuit: MOCK_ETABLISSEMENT.taux_majoration_nuit_pourcent || 25,
    tauxDimanche: MOCK_ETABLISSEMENT.taux_majoration_dimanche_pourcent || 50,
    tauxFerie: MOCK_ETABLISSEMENT.taux_majoration_ferie_pourcent || 100,
  });

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    afficherNotification({ type: 'succes', message: 'Informations mises à jour avec succès !' });
  };

  return (
    <LayoutApp role="ETABLISSEMENT">
      <h1 className="text-xl font-bold text-foreground mb-6">Profil de l'établissement</h1>

      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        {/* Informations générales */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Informations générales</h2>
          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Nom</label>
              <input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">SIRET</label>
                <input value={MOCK_ETABLISSEMENT.siret} disabled className="input-base bg-muted cursor-not-allowed" />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">FINESS</label>
                <input value={form.finess} onChange={e => maj('finess', e.target.value)} className="input-base" />
              </div>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Type</label>
              <input value={getLabelTypeEtablissement(MOCK_ETABLISSEMENT.type)} disabled className="input-base bg-muted cursor-not-allowed" />
            </div>
          </div>
        </div>

        {/* Adresse */}
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

        {/* Contact */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Contact</h2>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
              <input type="email" value={form.emailContact} onChange={e => maj('emailContact', e.target.value)} className="input-base" />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label>
              <input value={form.telephoneContact} onChange={e => maj('telephoneContact', e.target.value)} className="input-base" />
            </div>
          </div>
        </div>

        {/* Taux de majoration */}
        <div className="card-base">
          <div className="flex items-start gap-2 rounded-xl bg-primary/5 border border-primary/20 p-3 mb-4">
            <Info className="h-4 w-4 text-primary mt-0.5 flex-shrink-0" />
            <p className="text-xs text-primary">Ces taux s'appliquent automatiquement au calcul de la rémunération. Par défaut : Convention FPH.</p>
          </div>
          <h2 className="text-base font-semibold text-foreground mb-4">Taux de majoration (Convention)</h2>
          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Nuit (21h-06h) — %</label>
              <input type="number" step="0.01" value={form.tauxNuit} onChange={e => maj('tauxNuit', Number(e.target.value))} className="input-base" />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Dimanche — %</label>
              <input type="number" step="0.01" value={form.tauxDimanche} onChange={e => maj('tauxDimanche', Number(e.target.value))} className="input-base" />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Jours fériés — %</label>
              <input type="number" step="0.01" value={form.tauxFerie} onChange={e => maj('tauxFerie', Number(e.target.value))} className="input-base" />
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
