import { ChevronRight } from 'lucide-react';
import { Link } from 'react-router-dom';

interface Props {
  pageName: string;
}

export function BreadcrumbAdmin({ pageName }: Props) {
  return (
    <nav className="flex items-center gap-1.5 text-sm text-muted-foreground mb-4" aria-label="Fil d'Ariane">
      <Link to="/admin" className="hover:text-foreground transition-colors">Admin</Link>
      <ChevronRight className="h-3.5 w-3.5" />
      <span className="text-foreground font-medium">{pageName}</span>
    </nav>
  );
}
