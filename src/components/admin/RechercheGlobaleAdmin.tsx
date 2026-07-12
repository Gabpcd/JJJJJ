import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { LucideIcon, Building2, ClipboardList, FileText, Loader2, User } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from '@/components/ui/command';
import { supabase } from '@/integrations/supabase/client';

/* ── Types des résultats de fn_admin_recherche_globale ── */
interface ResUtilisateur {
  id: string;
  type: 'soignant' | 'etablissement' | 'inconnu';
  nom: string;
  prenom: string;
  email: string;
  profession: string | null;
  ville: string | null;
}
interface ResMission {
  id: string;
  intitule: string | null;
  statut: string;
  etablissement: string;
  debut_le: string;
  profession: string | null;
}
interface ResFacture {
  id: string;
  numero: string | null;
  statut: string;
  etablissement: string;
  montant_ttc: number | null;
  date_emission: string | null;
  type_document: string | null;
}
interface Resultats {
  utilisateurs: ResUtilisateur[];
  missions: ResMission[];
  factures: ResFacture[];
}

export interface PageRecherchable {
  icone: LucideIcon;
  label: string;
  route: string;
}

const fmtEuro = (v: number | null) =>
  v == null ? '' : new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);

const fmtDate = (iso: string | null) =>
  iso ? new Intl.DateTimeFormat('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(iso)) : '';

/** Statuts d'enum → libellé lisible (« VIREMENT_DECLARE » → « virement déclaré » sans accent garanti, on reste sobre) */
const fmtStatut = (s: string | null) => (s ? s.replace(/_/g, ' ').toLowerCase() : '');

/**
 * Palette de recherche globale admin (⌘K / Ctrl+K).
 * Recherche serveur (RPC fn_admin_recherche_globale) sur utilisateurs,
 * missions et factures + accès rapide aux pages admin (filtré RBAC en amont).
 */
export function RechercheGlobaleAdmin({
  open,
  onOpenChange,
  pages,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  pages: PageRecherchable[];
}) {
  const navigate = useNavigate();
  const [query, setQuery] = useState('');
  const [chargement, setChargement] = useState(false);
  const [resultats, setResultats] = useState<Resultats | null>(null);

  // Recherche serveur débouncée
  useEffect(() => {
    if (!open) return;
    const q = query.trim();
    if (q.length < 2) {
      setResultats(null);
      setChargement(false);
      return;
    }
    setChargement(true);
    const t = setTimeout(async () => {
      const { data, error } = await supabase.rpc('fn_admin_recherche_globale' as any, { p_query: q });
      if (!error && data) setResultats(data as unknown as Resultats);
      setChargement(false);
    }, 250);
    return () => clearTimeout(t);
  }, [query, open]);

  // Reset à la fermeture
  useEffect(() => {
    if (!open) {
      setQuery('');
      setResultats(null);
    }
  }, [open]);

  const aller = (route: string) => {
    onOpenChange(false);
    navigate(route);
  };

  const q = query.trim().toLowerCase();
  const pagesFiltrees = q.length >= 1
    ? pages.filter(p => p.label.toLowerCase().includes(q)).slice(0, 6)
    : pages.slice(0, 6);

  const aResultats = resultats
    && (resultats.utilisateurs.length > 0 || resultats.missions.length > 0 || resultats.factures.length > 0);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="overflow-hidden p-0 shadow-lg top-[20%] translate-y-0 max-w-xl">
        <DialogTitle className="sr-only">Recherche globale d’administration</DialogTitle>
        <DialogDescription className="sr-only">
          Rechercher une page, un utilisateur, une mission ou une facture.
        </DialogDescription>
        <Command shouldFilter={false} className="[&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-muted-foreground [&_[cmdk-group]]:px-2 [&_[cmdk-input]]:h-12">
          <CommandInput
            aria-label="Rechercher une page ou une donnée d’administration"
            placeholder="Rechercher un utilisateur, une mission, une facture…"
            value={query}
            onValueChange={setQuery}
          />
          <CommandList className="max-h-[420px]">
            {chargement && (
              <div className="flex items-center justify-center gap-2 py-4 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" /> Recherche…
              </div>
            )}

            {!chargement && q.length >= 2 && !aResultats && (
              <CommandEmpty>Aucun résultat pour « {query.trim()} »</CommandEmpty>
            )}

            {resultats && resultats.utilisateurs.length > 0 && (
              <CommandGroup heading="Utilisateurs">
                {resultats.utilisateurs.map(u => (
                  <CommandItem key={`u-${u.id}`} value={`u-${u.id}`} onSelect={() => aller(`/admin/utilisateurs/${u.id}`)}>
                    {u.type === 'etablissement'
                      ? <Building2 className="mr-2 h-4 w-4 text-muted-foreground" />
                      : <User className="mr-2 h-4 w-4 text-muted-foreground" />}
                    <div className="flex flex-col min-w-0">
                      <span className="truncate">{u.prenom ? `${u.prenom} ${u.nom}` : u.nom || u.email}</span>
                      <span className="text-xs text-muted-foreground truncate">
                        {[u.type === 'etablissement' ? 'Établissement' : u.profession || 'Soignant', u.ville, u.email]
                          .filter(Boolean).join(' · ')}
                      </span>
                    </div>
                  </CommandItem>
                ))}
              </CommandGroup>
            )}

            {resultats && resultats.missions.length > 0 && (
              <>
                <CommandSeparator />
                <CommandGroup heading="Missions">
                  {resultats.missions.map(m => (
                    <CommandItem key={`m-${m.id}`} value={`m-${m.id}`} onSelect={() => aller(`/admin/missions/${m.id}`)}>
                      <ClipboardList className="mr-2 h-4 w-4 text-muted-foreground" />
                      <div className="flex flex-col min-w-0">
                        <span className="truncate">{m.intitule || m.profession || 'Mission'}</span>
                        <span className="text-xs text-muted-foreground truncate">
                          {[m.etablissement, fmtDate(m.debut_le), fmtStatut(m.statut)].filter(Boolean).join(' · ')}
                        </span>
                      </div>
                    </CommandItem>
                  ))}
                </CommandGroup>
              </>
            )}

            {resultats && resultats.factures.length > 0 && (
              <>
                <CommandSeparator />
                <CommandGroup heading="Factures">
                  {resultats.factures.map(f => (
                    <CommandItem
                      key={`f-${f.id}`}
                      value={`f-${f.id}`}
                      onSelect={() => aller(`/admin/facturation?q=${encodeURIComponent(f.numero || f.id)}`)}
                    >
                      <FileText className="mr-2 h-4 w-4 text-muted-foreground" />
                      <div className="flex flex-col min-w-0">
                        <span className="truncate">{f.numero || 'Facture'}</span>
                        <span className="text-xs text-muted-foreground truncate">
                          {[f.etablissement, fmtDate(f.date_emission), fmtEuro(f.montant_ttc), fmtStatut(f.statut)]
                            .filter(Boolean).join(' · ')}
                        </span>
                      </div>
                    </CommandItem>
                  ))}
                </CommandGroup>
              </>
            )}

            {pagesFiltrees.length > 0 && (
              <>
                {(aResultats || chargement) && <CommandSeparator />}
                <CommandGroup heading="Pages">
                  {pagesFiltrees.map(p => (
                    <CommandItem key={`p-${p.route}`} value={`p-${p.route}`} onSelect={() => aller(p.route)}>
                      <p.icone className="mr-2 h-4 w-4 text-muted-foreground" />
                      {p.label}
                    </CommandItem>
                  ))}
                </CommandGroup>
              </>
            )}
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}
