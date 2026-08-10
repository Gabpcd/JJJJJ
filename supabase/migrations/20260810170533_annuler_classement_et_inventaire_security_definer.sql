-- Version conservée pour rester aligné avec l'historique déjà enregistré sur
-- le staging. Le rollback de #935/#936 est abandonné : l'incident provenait
-- des purges E2E non bornées, et non de ces protections déjà saines en prod.
-- L'état du staging est réparé par la migration compensatrice 20260810190000.
BEGIN;
COMMIT;
