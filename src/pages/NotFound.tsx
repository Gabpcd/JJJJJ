import { Link } from "react-router-dom";
import { HeartPulse } from "lucide-react";

const NotFound = () => {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="text-center max-w-md">
        <HeartPulse className="h-12 w-12 text-primary mx-auto mb-4" />
        <h1 className="mb-2 text-5xl font-bold text-foreground">404</h1>
        <p className="mb-6 text-lg text-muted-foreground">Cette page n'existe pas ou a été déplacée.</p>
        <Link to="/" className="btn-primary inline-flex items-center gap-2 px-6 py-3 text-sm">
          Retour à l'accueil
        </Link>
      </div>
    </div>
  );
};

export default NotFound;