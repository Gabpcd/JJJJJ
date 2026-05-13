import { useMemo, useState } from 'react';
import { Loader2, Eye, EyeOff, CheckCircle2, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { useAuth } from '@/contexts/AuthContext';

/**
 * Formulaire changement mot de passe avec vérification ancien + force nouveau (Sprint 5.5 PR 6).
 *
 * Critères nouveau MDP :
 *  - 12 caractères minimum
 *  - 1 majuscule
 *  - 1 minuscule
 *  - 1 chiffre
 *  - 1 caractère spécial
 *
 * Workflow :
 *  1. Vérifie l'ancien mot de passe via signInWithPassword (silencieux)
 *  2. Appelle supabase.auth.updateUser({ password })
 *  3. Audit trail action DONNEES_PERSO_MODIFICATION via fn_ecrire_audit_safe
 *     (l'enum journaux_audit_action_check ne contient pas MOT_DE_PASSE_MODIFIE,
 *      DONNEES_PERSO_MODIFICATION est l'équivalent générique adapté)
 */
export function ChangementMotDePasse() {
  const { afficherNotification } = useNotification();
  const { user } = useAuth();
  const [ancienMdp, setAncienMdp] = useState('');
  const [nouveauMdp, setNouveauMdp] = useState('');
  const [confirmationMdp, setConfirmationMdp] = useState('');
  const [showAncien, setShowAncien] = useState(false);
  const [showNouveau, setShowNouveau] = useState(false);
  const [loading, setLoading] = useState(false);

  const force = useMemo(() => calculerForce(nouveauMdp), [nouveauMdp]);
  const motDePasseValide = force.score === 5;
  const correspond = nouveauMdp.length > 0 && nouveauMdp === confirmationMdp;
  const formValide = ancienMdp.length > 0 && motDePasseValide && correspond;

  async function soumettre(e: React.FormEvent) {
    e.preventDefault();
    if (!formValide || !user?.email) return;

    setLoading(true);
    try {
      // Étape 1 : Vérifier l'ancien mot de passe (signInWithPassword silencieux)
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: user.email,
        password: ancienMdp,
      });
      if (signInError) {
        afficherNotification({
          type: 'erreur',
          message: 'Ancien mot de passe incorrect.',
        });
        setLoading(false);
        return;
      }

      // Étape 2 : Mettre à jour le mot de passe
      const { error: updateError } = await supabase.auth.updateUser({
        password: nouveauMdp,
      });
      if (updateError) {
        afficherNotification({
          type: 'erreur',
          message: updateError.message || 'Erreur lors de la mise à jour.',
        });
        setLoading(false);
        return;
      }

      // Étape 3 : Audit trail (best-effort, ne bloque pas)
      try {
        await supabase.rpc('fn_ecrire_audit_safe' as any, {
          p_acteur_id: user.id,
          p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_MODIFICATION',
          p_type_ressource: 'utilisateur',
          p_id_ressource: user.id,
          p_details: { champ: 'mot_de_passe', horodatage: new Date().toISOString() },
        });
      } catch { /* audit best-effort */ }

      afficherNotification({
        type: 'succes',
        message: 'Mot de passe modifié avec succès.',
      });
      setAncienMdp('');
      setNouveauMdp('');
      setConfirmationMdp('');
    } catch (err: any) {
      afficherNotification({
        type: 'erreur',
        message: err?.message || 'Erreur réseau.',
      });
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={soumettre} className="space-y-4">
      <label className="block">
        <span className="text-xs font-medium text-foreground mb-1 block">Mot de passe actuel</span>
        <div className="relative">
          <input
            type={showAncien ? 'text' : 'password'}
            value={ancienMdp}
            onChange={(e) => setAncienMdp(e.target.value)}
            className="input-base pr-10"
            autoComplete="current-password"
            required
          />
          <button
            type="button"
            onClick={() => setShowAncien(!showAncien)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground p-1"
            aria-label={showAncien ? 'Cacher' : 'Afficher'}
          >
            {showAncien ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>
      </label>

      <label className="block">
        <span className="text-xs font-medium text-foreground mb-1 block">Nouveau mot de passe</span>
        <div className="relative">
          <input
            type={showNouveau ? 'text' : 'password'}
            value={nouveauMdp}
            onChange={(e) => setNouveauMdp(e.target.value)}
            className="input-base pr-10"
            autoComplete="new-password"
            required
          />
          <button
            type="button"
            onClick={() => setShowNouveau(!showNouveau)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground p-1"
            aria-label={showNouveau ? 'Cacher' : 'Afficher'}
          >
            {showNouveau ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>
        {nouveauMdp.length > 0 && <JaugeForce force={force} />}
      </label>

      <label className="block">
        <span className="text-xs font-medium text-foreground mb-1 block">Confirmer le nouveau mot de passe</span>
        <input
          type="password"
          value={confirmationMdp}
          onChange={(e) => setConfirmationMdp(e.target.value)}
          className="input-base"
          autoComplete="new-password"
          required
        />
        {confirmationMdp.length > 0 && !correspond && (
          <p className="text-xs text-destructive mt-1 inline-flex items-center gap-1">
            <AlertCircle className="h-3 w-3" /> Les mots de passe ne correspondent pas.
          </p>
        )}
        {correspond && (
          <p className="text-xs text-success mt-1 inline-flex items-center gap-1">
            <CheckCircle2 className="h-3 w-3" /> Mots de passe identiques.
          </p>
        )}
      </label>

      <button
        type="submit"
        disabled={!formValide || loading}
        className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
      >
        {loading && <Loader2 className="h-4 w-4 animate-spin" />}
        Modifier mon mot de passe
      </button>
    </form>
  );
}

interface Force {
  score: number;
  criteres: { longueur: boolean; majuscule: boolean; minuscule: boolean; chiffre: boolean; special: boolean };
}

function calculerForce(mdp: string): Force {
  const criteres = {
    longueur: mdp.length >= 12,
    majuscule: /[A-Z]/.test(mdp),
    minuscule: /[a-z]/.test(mdp),
    chiffre: /[0-9]/.test(mdp),
    special: /[^A-Za-z0-9]/.test(mdp),
  };
  const score = Object.values(criteres).filter(Boolean).length;
  return { score, criteres };
}

function JaugeForce({ force }: { force: Force }) {
  const labels = ['Très faible', 'Faible', 'Moyen', 'Bon', 'Fort', 'Excellent'];
  const couleurs = ['bg-destructive', 'bg-destructive', 'bg-warning', 'bg-warning', 'bg-primary', 'bg-success'];
  return (
    <div className="mt-2 space-y-1">
      <div className="h-1.5 bg-muted rounded-full overflow-hidden">
        <div
          className={`h-full transition-all duration-300 ${couleurs[force.score]}`}
          style={{ width: `${(force.score / 5) * 100}%` }}
        />
      </div>
      <p className="text-[11px] text-muted-foreground">
        Force : <strong>{labels[force.score]}</strong>
      </p>
      <ul className="text-[10px] text-muted-foreground space-y-0.5 mt-1">
        <Critere ok={force.criteres.longueur} label="12 caractères minimum" />
        <Critere ok={force.criteres.majuscule} label="1 majuscule" />
        <Critere ok={force.criteres.minuscule} label="1 minuscule" />
        <Critere ok={force.criteres.chiffre} label="1 chiffre" />
        <Critere ok={force.criteres.special} label="1 caractère spécial" />
      </ul>
    </div>
  );
}

function Critere({ ok, label }: { ok: boolean; label: string }) {
  return (
    <li className={`flex items-center gap-1.5 ${ok ? 'text-success' : 'text-muted-foreground'}`}>
      {ok ? <CheckCircle2 className="h-3 w-3" /> : <span className="inline-block h-3 w-3 rounded-full border border-muted-foreground" />}
      <span>{label}</span>
    </li>
  );
}
