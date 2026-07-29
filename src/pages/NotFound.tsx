import { usePageTitle } from '@/hooks/usePageTitle';
import { Link } from "react-router-dom";
import { Home } from "lucide-react";
import { LogoJolene } from '@/components/LogoJolene';

const NotFound = () => {
  usePageTitle('Page introuvable');
  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-background px-4">
      <div className="text-center max-w-md">
        <LogoJolene
          afficherNom={false}
          decoratif
          className="mx-auto mb-6"
          imageClassName="h-14 w-14"
        />
        <h1 className="mb-2 text-6xl font-bold text-foreground tracking-tight">404</h1>
        <p className="mb-2 text-lg font-medium text-foreground">Page introuvable</p>
        <p className="mb-8 text-sm text-muted-foreground">
          Cette page n'existe pas ou a été déplacée.<br />
          Si vous pensez qu'il s'agit d'une erreur, contactez le support Jolene.
        </p>
        <Link
          to="/"
          className="btn-primary inline-flex items-center gap-2 px-8 py-3 text-sm font-medium rounded-xl"
        >
          <Home className="h-4 w-4" />
          Retour à l'accueil
        </Link>
        <p className="mt-8 text-xs text-muted-foreground">© 2026 Jolene SASU</p>
      </div>
    </div>
  );
};

export default NotFound;
