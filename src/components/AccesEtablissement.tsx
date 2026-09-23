import { Fragment, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { Building2, RefreshCw } from 'lucide-react';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';

/** Une identité peut explorer l'app avant de créer son dossier établissement.
 * Cette frontière ne donne aucun droit : les permissions métier restent vérifiées
 * par chaque rubrique et par le serveur, une fois le périmètre résolu.
 */
export function AccesEtablissement({ children, titre, description, sansLayout = false }: {
  children: ReactNode;
  titre: string;
  description: string;
  sansLayout?: boolean;
}) {
  usePageTitle(titre);
  const { user, parcours, etablissementId, loading, resolved, error, retry } = useEtablissementScope();
  const envelopper = (contenu: ReactNode) => sansLayout
    ? contenu
    : <LayoutApp role="ADMIN_ETABLISSEMENT">{contenu}</LayoutApp>;

  if (error) return envelopper(
    <ErreurRubriqueEtablissement titre="Impossible de vérifier votre établissement" reessayer={retry} />,
  );
  if (loading || !resolved) return envelopper(<ChargementPage />);
  if (!user) return envelopper(
    <section className="card-base max-w-xl mx-auto space-y-4" role="alert">
      <h1 className="text-xl font-semibold">Reconnectez-vous pour continuer</h1>
      <Link className="btn-primary inline-flex" to="/connexion">Se connecter</Link>
    </section>,
  );
  if (!etablissementId && parcours?.type_compte !== 'ETABLISSEMENT') return envelopper(
    <section className="card-base max-w-xl mx-auto space-y-4" role="alert">
      <h1 className="text-xl font-semibold">Établissement non rattaché</h1>
      <p className="text-sm text-muted-foreground">Votre accès n’est associé à aucun établissement. Réessayez ou vérifiez votre rattachement auprès du responsable de votre équipe.</p>
      <div className="flex flex-col sm:flex-row gap-3">
        <button type="button" className="btn-secondary" onClick={retry}>Réessayer</button>
        <Link className="btn-secondary inline-flex items-center justify-center" to="/etablissement/mon-compte">Retour à mon compte</Link>
      </div>
    </section>,
  );
  if (!etablissementId) return envelopper(
    <section className="max-w-xl mx-auto space-y-5" aria-labelledby="rubrique-etablissement-titre">
      <h1 id="rubrique-etablissement-titre" className="text-xl font-semibold">{titre}</h1>
      <div className="card-base space-y-4">
        <Building2 className="h-8 w-8 text-primary" aria-hidden="true" />
        <h2 className="text-lg font-semibold">Votre établissement se prépare à votre rythme</h2>
        <p className="text-sm text-muted-foreground">{description}</p>
        <p className="text-sm text-muted-foreground">Vous pouvez continuer à explorer Jolene et préparer une mission sans compléter votre dossier maintenant.</p>
        <div className="flex flex-col sm:flex-row gap-3">
          <Link className="btn-primary inline-flex items-center justify-center" to="/etablissement/missions/creer">Préparer une mission</Link>
          <Link className="btn-secondary inline-flex items-center justify-center" to="/inscription/completer">Compléter mon établissement</Link>
        </div>
      </div>
    </section>,
  );
  return <Fragment key={`${user.id}:${etablissementId}`}>{children}</Fragment>;
}

export function ErreurRubriqueEtablissement({ titre, reessayer }: {
  titre: string;
  reessayer: () => void;
}) {
  return (
    <section className="card-base max-w-xl mx-auto space-y-4" role="alert">
      <h1 className="text-xl font-semibold">{titre}</h1>
      <p className="text-sm text-muted-foreground">Le chargement n'a pas abouti. Réessayez dans un instant.</p>
      <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={reessayer}>
        <RefreshCw className="h-4 w-4" aria-hidden="true" /> Réessayer
      </button>
    </section>
  );
}
