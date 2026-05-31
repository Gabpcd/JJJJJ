-- BUG CRITIQUE : dec_maj_tous_documents_valides n'était rattaché à AUCUNE table
-- → tous_documents_valides jamais recalculé automatiquement.
CREATE TRIGGER trg_maj_tous_documents_valides
  AFTER INSERT OR UPDATE OR DELETE ON public.documents_soignants
  FOR EACH ROW EXECUTE FUNCTION public.dec_maj_tous_documents_valides();
