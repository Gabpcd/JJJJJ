import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, Eye, EyeOff, Check } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { SelectProfession } from '@/components/SelectProfession';
import { CONTRATS } from '@/lib/constantes';

function JaugeForce({ motDePasse }: { motDePasse: string }) {
  let force = 0;
  if (motDePasse.length >= 8) force++;
  if (/[A-Z]/.test(motDePasse)) force++;
  if (/[0-9]/.test(motDePasse)) force++;
  if (/[^A-Za-z0-9]/.test(motDePasse)) force++;
  const labels = ['', 'Faible', 'Moyen', 'Fort', 'Très fort'];
  const colors = ['', 'bg-destructive', 'bg-warning', 'bg-primary', 'bg-success'];
  if (!motDePasse) return null;
  return (
    <div className="mt-1.5">
      <div className="flex gap-1">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className={`h-1 flex-1 rounded-full ${i <= force ? colors[force] : 'bg-muted'}`} />
        ))}
      </div>
      <p className="text-[10px] text-muted-foreground mt-0.5">{labels[force]}</p>
    </div>
  );
}

export default function InscriptionSoignant() {
  const navigate = useNavigate();
  const { inscriptionSoignant } = useAuth();
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState(1);
  const [afficherMdp, setAfficherMdp] = useState(false);
  const [cgu, setCgu] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const [form, setForm] = useState({
    email: '', motDePasse: '', confirmMdp: '',
    prenom: '', nom: '', telephone: '', dateNaissance: '',
    profession: '', typeContrat: '', rpps: '', rayon: 30,
  });

  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));
  const etape1Valide = form.email && form.motDePasse.length >= 8 && form.motDePasse === form.confirmMdp && cgu;
  const etape2Valide = form.prenom && form.nom && form.profession && form.typeContrat;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await inscriptionSoignant(form);
      afficherNotification({ type: 'succes', message: 'Compte créé avec succès ! Bienvenue sur Soin Direct.' });
      navigate('/soignant/tableau-de-bord');
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
        <h1 className="text-xl font-bold text-foreground text-center mb-2">Inscription Soignant</h1>

        {/* Stepper */}
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
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Email *</label>
                <input type="email" value={form.email} onChange={e => maj('email', e.target.value)} className="input-base" required />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Mot de passe *</label>
                <div className="relative">
                  <input type={afficherMdp ? 'text' : 'password'} value={form.motDePasse} onChange={e => maj('motDePasse', e.target.value)} placeholder="Minimum 8 caractères" className="input-base pr-10" required />
                  <button type="button" onClick={() => setAfficherMdp(!afficherMdp)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                    {afficherMdp ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
                <JaugeForce motDePasse={form.motDePasse} />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Confirmer le mot de passe *</label>
                <input type="password" value={form.confirmMdp} onChange={e => maj('confirmMdp', e.target.value)} className="input-base" required />
                {form.confirmMdp && form.confirmMdp !== form.motDePasse && (
                  <p className="text-xs text-destructive mt-1">Les mots de passe ne correspondent pas</p>
                )}
              </div>
              <label className="flex items-start gap-2 cursor-pointer">
                <input type="checkbox" checked={cgu} onChange={e => setCgu(e.target.checked)} className="mt-1 h-4 w-4 rounded border-input text-primary accent-primary" />
                <span className="text-sm text-muted-foreground">J'accepte les <a href="#" className="text-primary hover:underline">CGU</a> et la <a href="#" className="text-primary hover:underline">Politique de confidentialité</a> *</span>
              </label>
              <button type="button" onClick={() => setEtape(2)} disabled={!etape1Valide} className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed">Continuer</button>
            </div>
          )}

          {etape === 2 && (
            <div className="space-y-4">
              <p className="text-sm font-medium text-muted-foreground mb-4">Étape 2 — Votre profil professionnel</p>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">Prénom *</label><input value={form.prenom} onChange={e => maj('prenom', e.target.value)} className="input-base" required /></div>
                <div><label className="text-sm font-medium text-foreground mb-1.5 block">Nom *</label><input value={form.nom} onChange={e => maj('nom', e.target.value)} className="input-base" required /></div>
              </div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephone} onChange={e => maj('telephone', e.target.value)} placeholder="+33 6 ..." className="input-base" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance</label><input type="date" value={form.dateNaissance} onChange={e => maj('dateNaissance', e.target.value)} className="input-base" max={new Date(new Date().setFullYear(new Date().getFullYear() - 18)).toISOString().split('T')[0]} /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Profession *</label><SelectProfession value={form.profession} onChange={v => maj('profession', v)} /></div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Type de contrat *</label>
                <select value={form.typeContrat} onChange={e => maj('typeContrat', e.target.value)} className="input-base">
                  <option value="">Sélectionnez le type</option>
                  {CONTRATS.map(c => <option key={c.valeur} value={c.valeur}>{c.label}</option>)}
                </select>
              </div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Numéro RPPS</label><input value={form.rpps} onChange={e => maj('rpps', e.target.value.replace(/\D/g, '').slice(0, 11))} placeholder="11 chiffres" className="input-base" /></div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Rayon de déplacement : <span className="text-primary font-bold">{form.rayon} km</span></label>
                <input type="range" min={5} max={100} value={form.rayon} onChange={e => maj('rayon', Number(e.target.value))} className="w-full h-2 bg-primary/20 rounded-full appearance-none cursor-pointer accent-primary" />
                <div className="flex justify-between text-[10px] text-muted-foreground"><span>5 km</span><span>100 km</span></div>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEtape(1)} className="btn-secondary flex-1">Retour</button>
                <button type="submit" disabled={!etape2Valide || submitting} className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed">
                  {submitting ? 'Création…' : 'Créer mon compte'}
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
