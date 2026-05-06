import * as Sentry from "@sentry/react";
import { toast } from "@/hooks/use-toast";
import { logger } from "@/lib/logger";

const MESSAGE_GENERIQUE = "Une erreur est survenue. Veuillez réessayer.";

/**
 * Extrait un message d'erreur sécurisé.
 * En DEV : retourne le message technique complet pour le debug.
 * En PROD : retourne TOUJOURS le message générique — jamais error.message,
 * error.details, error.hint ou error.code.
 */
function getSecureMessage(error: unknown): string {
  if (import.meta.env.DEV) {
    if (error instanceof Error) return error.message;
    if (typeof error === "object" && error !== null) {
      const e = error as Record<string, unknown>;
      return (e.message ?? e.details ?? e.hint ?? JSON.stringify(error)) as string;
    }
    return String(error);
  }
  return MESSAGE_GENERIQUE;
}

function reportToSentry(error: unknown, contexte: string | undefined, level: 'error' | 'warning') {
  if (error instanceof Error) {
    Sentry.captureException(error, {
      level,
      tags: { source: 'handleError', contexte: contexte ?? 'unknown' },
    });
  } else if (error !== undefined && error !== null) {
    Sentry.captureMessage(
      `[${contexte ?? 'unknown'}] ${getSecureMessage(error)}`,
      { level, tags: { source: 'handleError', contexte: contexte ?? 'unknown' } },
    );
  }
}

/**
 * Gère une erreur Supabase ou applicative de manière sécurisée.
 * - En DEV : log l'erreur complète dans la console.
 * - En PROD : affiche uniquement un toast générique, aucune fuite d'info.
 *   Ne jamais afficher error.message, error.details, error.hint ou error.code.
 * - Toujours : push l'erreur vers Sentry avec tags { source, contexte }.
 *
 * @param error  L'objet erreur (Error, PostgrestError, ou inconnu)
 * @param contexte  Contexte technique (ex: "chargement missions") — jamais affiché à l'utilisateur en prod
 */
export function handleError(error: unknown, contexte?: string): void {
  if (import.meta.env.DEV) {
    logger.error(contexte ?? "Erreur applicative", error);
  }

  reportToSentry(error, contexte, 'error');

  toast({
    title: "Erreur",
    description: MESSAGE_GENERIQUE,
    variant: "destructive",
  });
}

/**
 * Variante silencieuse — log + Sentry sans toast.
 * Utile pour les requêtes non-critiques (KPIs secondaires, audit best-effort, etc.)
 * Niveau 'warning' côté Sentry (déduplication par message + tags).
 */
export function handleErrorSilent(error: unknown, contexte?: string): void {
  if (import.meta.env.DEV) {
    logger.error(contexte ?? "Erreur silencieuse", error);
  }
  reportToSentry(error, contexte, 'warning');
}

/**
 * Retourne un message d'erreur sûr pour affichage utilisateur.
 * Utilise getSecureMessage en interne.
 */
export function getDisplayMessage(error: unknown): string {
  return getSecureMessage(error);
}
