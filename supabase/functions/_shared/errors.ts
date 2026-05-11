// Helper partagé pour structurer les réponses d'erreur des edge functions.
//
// Format retenu :
//   {
//     ok: false,
//     code: "MACHINE_READABLE_CODE",
//     message: "Texte affichable utilisateur",
//     error: "Texte affichable utilisateur",  // miroir de message — rétro-compat
//     details?: { ... }                       // optionnel
//   }
//
// Le champ `error` est conservé en miroir de `message` pour ne pas casser
// les call-sites frontend existants qui lisent encore `data.error`. Les
// nouveaux call-sites doivent lire `code` (stable et machine-readable).
//
// Les codes sont en SCREAMING_SNAKE_CASE et stables — toute modification
// est un breaking change pour les consommateurs.
//
// Helper `safeStringifyError` : remplace `console.error('msg', err)` qui
// produit `[object Object]` dans Sentry. À utiliser systématiquement dans
// les catch :
//   } catch (err) {
//     console.error('contexte:', safeStringifyError(err));
//   }

export interface ErrorResponseBody {
  ok: false;
  code: string;
  message: string;
  error: string;
  details?: Record<string, unknown>;
}

export function errorResponse(
  corsHdrs: Record<string, string>,
  status: number,
  code: string,
  message: string,
  details?: Record<string, unknown>,
): Response {
  const body: ErrorResponseBody = {
    ok: false,
    code,
    message,
    error: message,
  };
  if (details) body.details = details;
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHdrs, 'Content-Type': 'application/json' },
  });
}

export function safeStringifyError(err: unknown): string {
  if (err === null || err === undefined) return 'null';
  if (err instanceof Error) {
    return err.stack ? `${err.message}\n${err.stack}` : err.message;
  }
  if (typeof err === 'string') return err;
  try {
    return JSON.stringify(err);
  } catch {
    return String(err);
  }
}
