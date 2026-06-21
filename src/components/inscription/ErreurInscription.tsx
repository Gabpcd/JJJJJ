import { AlertCircle, RefreshCw, LogIn, LifeBuoy } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import type { ErreurInscriptionMappee } from '@/lib/erreurs';

interface Props {
  erreur: ErreurInscriptionMappee;
  onRetry?: () => void;
  onSeConnecter?: () => void;
}

/**
 * Affichage inline d'une erreur d'inscription, avec une action
 * contextualisée selon `erreur.action` :
 *  - reconnexion : bouton "Se connecter" (USER_ALREADY_REGISTERED)
 *  - retry : bouton "Réessayer" (NETWORK_ERROR, RPPS_API_UNAVAILABLE, ...)
 *  - support : lien mailto:support@jolene.app (UNKNOWN, INTERNAL_ERROR)
 *  - highlight_* : pas de bouton, le formulaire parent lit
 *    erreur.champs_highlight pour mettre en valeur les champs concernés.
 *
 * À utiliser au-dessus du bouton submit du formulaire pour rester visible.
 * Composant volontairement contrôlé : le parent gère l'état (afficher/masquer)
 * via mount/unmount conditionnel.
 */
export function ErreurInscription({ erreur, onRetry, onSeConnecter }: Props) {
  const aideRppsLink = ['RPPS_NOT_FOUND', 'RPPS_FORMAT_INVALID', 'RPPS_TRAITS_MISMATCH'].includes(erreur.code)
    ? <a href="/aide/comment-verifier-mon-rpps" className="text-primary underline font-medium ml-1">Comment vérifier mon RPPS ?</a>
    : null;

  return (
    <Alert variant="destructive" data-error-code={erreur.code} className="mt-4 mb-2">
      <AlertCircle className="h-4 w-4" />
      <AlertTitle>{titrePourCode(erreur.code)}</AlertTitle>
      <AlertDescription>
        <p className="mt-1">{erreur.message}{aideRppsLink}</p>

        {erreur.action === 'reconnexion' && onSeConnecter && (
          <button
            type="button"
            onClick={onSeConnecter}
            className="mt-3 inline-flex items-center gap-1.5 rounded-md bg-destructive px-3 py-1.5 text-sm font-medium text-destructive-foreground hover:bg-destructive/90"
          >
            <LogIn className="h-3.5 w-3.5" />
            Se connecter
          </button>
        )}

        {erreur.action === 'retry' && onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="mt-3 inline-flex items-center gap-1.5 rounded-md border border-destructive/50 bg-background px-3 py-1.5 text-sm font-medium text-destructive hover:bg-destructive/5"
          >
            <RefreshCw className="h-3.5 w-3.5" />
            Réessayer
          </button>
        )}

        {erreur.action === 'support' && (
          <a
            href="mailto:support@jolene.app?subject=Problème inscription Jolene"
            className="mt-3 inline-flex items-center gap-1.5 rounded-md border border-destructive/50 bg-background px-3 py-1.5 text-sm font-medium text-destructive hover:bg-destructive/5"
          >
            <LifeBuoy className="h-3.5 w-3.5" />
            Contacter le support
          </a>
        )}
      </AlertDescription>
    </Alert>
  );
}

function titrePourCode(code: string): string {
  switch (code) {
    case 'USER_ALREADY_REGISTERED':
      return 'Compte déjà existant';
    case 'EMAIL_RATE_LIMIT':
    case 'RATE_LIMITED':
      return 'Trop de tentatives';
    case 'INVALID_EMAIL':
      return 'Email invalide';
    case 'WEAK_PASSWORD':
      return 'Mot de passe trop faible';
    case 'RPPS_FORMAT_INVALID':
    case 'RPPS_NOT_FOUND':
    case 'RPPS_TRAITS_MISMATCH':
      return 'Numéro RPPS — vérification';
    case 'RPPS_ALREADY_REGISTERED':
      return 'Numéro RPPS déjà utilisé';
    case 'RPPS_API_UNAVAILABLE':
      return 'Annuaire Santé indisponible';
    case 'SIRET_FORMAT_INVALID':
    case 'SIRET_CHECKSUM_INVALID':
    case 'SIRET_ALREADY_REGISTERED':
      return 'Numéro SIRET — vérification';
    case 'CAPTCHA_FAILED':
      return 'Vérification anti-bot échouée';
    case 'MISSING_REQUIRED_FIELDS':
      return 'Champs manquants';
    case 'UNDERAGE':
      return 'Âge minimum requis';
    case 'UNAUTHORIZED':
    case 'INVALID_TOKEN':
      return 'Session invalide';
    case 'NETWORK_ERROR':
      return 'Connexion internet';
    case 'INTERNAL_ERROR':
      return 'Erreur serveur';
    default:
      return 'Erreur inattendue';
  }
}
