import { toast } from "@/hooks/use-toast";
import { logger } from "@/lib/logger";

const MESSAGE_GENERIQUE = "Une erreur est survenue. Veuillez réessayer.";

/**
 * Gère une erreur Supabase ou applicative de manière sécurisée.
 * - En DEV : log l'erreur complète dans la console.
 * - En PROD : affiche uniquement un toast générique, aucune fuite d'info.
 *
 * @param error  L'objet erreur (Error, PostgrestError, ou inconnu)
 * @param contexte  Contexte technique (ex: "chargement missions") — jamais affiché à l'utilisateur en prod
 */
export function handleError(error: unknown, contexte?: string): void {
  if (import.meta.env.DEV) {
    logger.error(contexte ?? "Erreur applicative", error);
  }

  toast({
    title: "Erreur",
    description: MESSAGE_GENERIQUE,
    variant: "destructive",
  });
}

/**
 * Variante silencieuse — log sans toast.
 * Utile pour les requêtes non-critiques (KPIs secondaires, etc.)
 */
export function handleErrorSilent(error: unknown, contexte?: string): void {
  if (import.meta.env.DEV) {
    logger.error(contexte ?? "Erreur silencieuse", error);
  }
}
