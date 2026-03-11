import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Eye, EyeOff, Check } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { SelectTypeEtablissement } from '@/components/SelectTypeEtablissement';

export default function InscriptionEtablissement() {
  const navigate = useNavigate();
  const { inscriptionEtablissement } = useAuth();
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState(1);
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [cgu, setCgu] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const [form, setForm] = useState({
    email: '', motDePasse: '', confirmMdp: '',
    nom: '', siret: '', finess: '', type: '',
    rue: '', ville: '', codePostal: '', departement: '',
    emailContact: '', telephoneContact: '',
    lat: null as number | null, lng: null as number | null,
  });

  const maj = (champ: string, valeur: string) => setForm(prev => ({ ...prev, [champ]: valeur }));
  const etape1Valide = form.email && form.motDePasse.length >= 8 && form.motDePasse === form.confirmMdp && cgu;
  const etape2Valide = form.nom && form.siret.length === 14 && form.type && form.ville;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await inscriptionEtablissement(form);
      afficherNotification({ type: 'succes', message: 'Établissement créé avec succès !' });
      navigate('/etablissement/tableau-de-bord');
    } catch (err) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen gradient-hero flex items-center justify-center px-4 py-8">
      <div className="card-base max-w-lg w-full">
        <div className="flex items-center justify-center gap-2 mb-6">
          <HeartPulse className="h-7 w-7 text-primary" />
          <span className="text-xl font-bold text-primary-dark">Soin Direct</span>
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
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email *</label><input type="email" value={form.email} onChange={e => maj('email', e.target.value)} className="input-base" required /></div>
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
                <span className="text-sm text-muted-foreground">J'accepte les <a href="#" className="text-primary hover:underline">CGU</a> *</span>
              </label>
              <button type="button" onClick={() => setEtape(2)} disabled={!etape1Valide} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed">Continuer</button>
            </div>
          )}

          {etape === 2 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 2 — Votre établissement</p>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nom de l'établissement *</label><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" required /></div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">SIRET * (14 chiffres)</label><input value={form.siret} onChange={e => maj('siret', e.target.value.replace(/\D/g, '').slice(0, 14))} className="input-base" required /></div>
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">FINESS (9 chiffres)</label><input value={form.finess} onChange={e => maj('finess', e.target.value.replace(/\D/g, '').slice(0, 9))} className="input-base" /></div>
              </div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Type d'établissement *</label><SelectTypeEtablissement value={form.type} onChange={v => maj('type', v)} /></div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Adresse</label>
                <input value={form.rue} onChange={e => maj('rue', e.target.value)} placeholder="Rue" className="input-base mb-2" />
                <div className="grid grid-cols-3 gap-2">
                  <input value={form.ville} onChange={e => maj('ville', e.target.value)} placeholder="Ville *" className="input-base" required />
                  <input value={form.codePostal} onChange={e => maj('codePostal', e.target.value.replace(/\D/g, '').slice(0, 5))} placeholder="Code postal" className="input-base" />
                  <input value={form.departement} onChange={e => maj('departement', e.target.value)} placeholder="Dép." className="input-base" />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email contact</label><input type="email" value={form.emailContact} onChange={e => maj('emailContact', e.target.value)} className="input-base" /></div>
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephoneContact} onChange={e => maj('telephoneContact', e.target.value)} className="input-base" /></div>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEtape(1)} className="btn-secondary flex-1">Retour</button>
                <button type="submit" disabled={!etape2Valide || submitting} className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed">
                  {submitting ? 'Création…' : 'Créer le compte'}
                </button>
              </div>
            </div>
          )}
        </form>

        <p className="text-center mt-6 text-sm text-muted-foreground">
          Déjà un compte ? <a href="/connexion" className="text-primary hover:underline font-medium">Se connecter</a>
        </p>
      </div>
    </div>
  );
}
