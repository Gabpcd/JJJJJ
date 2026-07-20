import { useCallback, useEffect, useState } from 'react';
import {
  Building2,
  CheckCircle2,
  Database,
  EyeOff,
  Mail,
  MapPin,
  Phone,
  Plus,
  RefreshCw,
  Search,
  ShieldCheck,
  Sparkles,
  Target,
  UserRoundSearch,
  Users,
} from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { PROFESSIONS, getLabelProfession } from '@/lib/constantes';
import { toast } from 'sonner';

type CibleSourcing = 'SOIGNANT' | 'ETABLISSEMENT';

interface ProspectSourcing {
  id: string;
  cible: CibleSourcing;
  nom: string;
  prenom: string | null;
  profession: string | null;
  sous_titre: string | null;
  telephone: string | null;
  email: string | null;
  ville: string | null;
  departement: string | null;
  code_postal: string | null;
  numero_rpps: string | null;
  mode_exercice: string | null;
  finess_structure: string | null;
  type_etab: string | null;
  source_code: string;
  source_url: string | null;
  source_maj_le: string | null;
  importe_le: string;
  statut_sourcing: string;
  deja_crm: boolean;
  deja_inscrit: boolean;
  missions_ouvertes: number;
  score: number;
}

interface BesoinSourcing {
  profession: string;
  departement: string | null;
  missions_ouvertes: number;
}

interface ImportSourcing {
  id: string;
  source_code: string;
  cible: CibleSourcing;
  statut: 'EN_COURS' | 'TERMINE' | 'ERREUR';
  source_maj_le: string | null;
  demarre_le: string;
  termine_le: string | null;
  lignes_lues: number;
  lignes_importees: number;
  erreur: string | null;
}

interface TableauSourcing {
  stats: {
    total: number;
    nouveaux_30j: number;
    contactables: number;
    hors_crm: number;
  };
  resultats: ProspectSourcing[];
  besoins: BesoinSourcing[];
  imports: ImportSourcing[];
  page: number;
  par_page: number;
  total_pages: number;
  genere_le: string;
}

const TYPES_ETAB = [
  { value: '', label: 'Tous les établissements' },
  { value: 'HOPITAL', label: 'Hôpitaux et cliniques' },
  { value: 'EHPAD', label: 'EHPAD' },
  { value: 'DOMICILE', label: 'Domicile / SSIAD' },
  { value: 'HANDICAP', label: 'Handicap / médico-social' },
  { value: 'CENTRE_SANTE', label: 'Centres de santé' },
  { value: 'LABO', label: 'Laboratoires' },
  { value: 'DIALYSE', label: 'Dialyse' },
  { value: 'ECOLE_SANTE', label: 'IFSI, IFAS et écoles de santé' },
] as const;

const PROFESSIONS_SANS_ANNUAIRE_INDIVIDUEL_EXHAUSTIF = new Set([
  'AS',
  'AES',
  'AUXILIAIRE_PUERICULTURE',
]);

function formatNombre(value: number): string {
  return new Intl.NumberFormat('fr-FR').format(value || 0);
}

function formatDate(value: string | null): string {
  if (!value) return 'date inconnue';
  return new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium' }).format(new Date(value));
}

function sourceLabel(code: string): string {
  if (code === 'ANNUAIRE_SANTE_RPPS') return 'Annuaire Santé / RPPS';
  if (code === 'FINESS_DATA_GOUV') return 'FINESS / data.gouv.fr';
  if (code.includes('CNAM')) return 'Ancien annuaire CNAM';
  if (code.includes('FINESS')) return 'FINESS historique';
  return code;
}

function scoreVariant(score: number): 'success' | 'warning' | 'info' {
  if (score >= 75) return 'success';
  if (score >= 50) return 'warning';
  return 'info';
}

export function AdminSourcingCockpit({ onContactsChanged }: { onContactsChanged?: () => void }) {
  const [cible, setCible] = useState<CibleSourcing>('SOIGNANT');
  const [departement, setDepartement] = useState('');
  const [profession, setProfession] = useState('');
  const [typeEtab, setTypeEtab] = useState('');
  const [nouveaux, setNouveaux] = useState(false);
  const [contactables, setContactables] = useState(true);
  const [horsCrm, setHorsCrm] = useState(true);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<TableauSourcing | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [importLoading, setImportLoading] = useState(false);

  const charger = useCallback(async (pageDemandee = 1) => {
    setLoading(true);
    const { data: resultat, error } = await supabase.rpc('fn_admin_sourcing_tableau' as never, {
      p_cible: cible,
      p_departement: departement.trim() || null,
      p_profession: cible === 'SOIGNANT' ? profession || null : null,
      p_type_etab: cible === 'ETABLISSEMENT' ? typeEtab || null : null,
      p_nouveaux: nouveaux,
      p_contactables: contactables,
      p_hors_crm: horsCrm,
      p_page: pageDemandee,
      p_par_page: 30,
    } as never);
    setLoading(false);
    if (error) {
      toast.error(`Sourcing indisponible : ${error.message}`);
      setData(null);
      return;
    }
    setData(resultat as unknown as TableauSourcing);
    setPage(pageDemandee);
  }, [cible, contactables, departement, horsCrm, nouveaux, profession, typeEtab]);

  useEffect(() => {
    void charger(1);
  }, [charger]);

  const ajouterAuCrm = async (prospect: ProspectSourcing) => {
    setActionLoading(prospect.id);
    const { error } = await supabase.rpc('fn_admin_sourcing_ajouter_crm' as never, {
      p_cible: prospect.cible,
      p_prospect_id: prospect.id,
      p_score: prospect.score,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success('Prospect ajouté au CRM, sans séquence de contact active.');
    onContactsChanged?.();
    await charger(page);
  };

  const ignorer = async (prospect: ProspectSourcing) => {
    if (!window.confirm(`Masquer ${prospect.prenom ? `${prospect.prenom} ` : ''}${prospect.nom} de la file de sourcing ?`)) return;
    setActionLoading(prospect.id);
    const { error } = await supabase.rpc('fn_admin_sourcing_qualifier' as never, {
      p_cible: prospect.cible,
      p_prospect_id: prospect.id,
      p_statut: 'IGNORE',
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success('Prospect masqué de la file.');
    await charger(page);
  };

  const actualiserSource = async () => {
    const source = cible === 'SOIGNANT' ? 'l’Annuaire Santé / RPPS' : 'FINESS';
    if (!window.confirm(`Démarrer l’actualisation silencieuse depuis ${source} ? Aucun message ne sera envoyé.`)) return;
    setImportLoading(true);
    const { data: resultat, error } = await supabase.rpc('fn_sourcing_lancer_import' as never, { p_cible: cible } as never);
    setImportLoading(false);
    if (error) {
      toast.error(`Actualisation non démarrée : ${error.message}`);
      return;
    }
    const lancement = resultat as unknown as { success?: boolean; already_running?: boolean; error?: string };
    if (lancement?.success === false) {
      toast.error(lancement.error || 'Actualisation non démarrée.');
      return;
    }
    toast.success(lancement?.already_running
      ? 'Une actualisation silencieuse est déjà en cours.'
      : 'Actualisation démarrée en arrière-plan. Aucun contact ne sera envoyé.');
    await charger(1);
  };

  if (loading && !data) {
    return <div className="rounded-xl border border-border bg-card p-8 text-center text-sm text-muted-foreground" role="status">Analyse des nouveaux contacts potentiels…</div>;
  }

  if (!data) {
    return <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-destructive" role="alert">Le cockpit de sourcing n’a pas pu être chargé.</div>;
  }

  return (
    <section className="space-y-5" aria-labelledby="sourcing-title">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 id="sourcing-title" className="flex items-center gap-2 font-bold text-foreground">
            <UserRoundSearch className="h-5 w-5 text-primary" aria-hidden="true" /> Nouveaux contacts à recruter
          </h2>
          <p className="max-w-3xl text-xs text-muted-foreground">
            Annuaire officiel, dédoublonné des comptes Jolene et du CRM, classé selon la contactabilité, la fraîcheur et les besoins ouverts. La découverte et l’ajout au CRM sont silencieux.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <BadgeY2K variant="success"><ShieldCheck className="mr-1 inline h-3.5 w-3.5" aria-hidden="true" /> Aucun envoi automatique</BadgeY2K>
          <BoutonY2K variant="secondary" size="sm" loading={importLoading} onClick={actualiserSource} iconeGauche={<RefreshCw className="h-4 w-4" />}>
            Actualiser la source
          </BoutonY2K>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <CarteKPIY2K icone={<Target className="h-4 w-4" />} label="Prospects ciblés" valeur={formatNombre(data.stats.total)} contexte="selon les filtres" variant="holographic" />
        <CarteKPIY2K icone={<Sparkles className="h-4 w-4" />} label="Nouveaux / 30 j" valeur={formatNombre(data.stats.nouveaux_30j)} contexte="nouvellement importés" variant="soft" />
        <CarteKPIY2K icone={<Phone className="h-4 w-4" />} label="Contactables" valeur={formatNombre(data.stats.contactables)} contexte="email ou téléphone public" />
        <CarteKPIY2K icone={<Database className="h-4 w-4" />} label="Hors CRM" valeur={formatNombre(data.stats.hors_crm)} contexte="et non inscrits" />
      </div>

      <CardY2K hoverLift={false} noPadding>
        <CardY2KContent className="pt-6">
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <fieldset>
              <legend className="mb-1 text-xs font-medium text-foreground">Je cherche</legend>
              <div className="grid grid-cols-2 gap-2">
                <BoutonY2K size="sm" variant={cible === 'SOIGNANT' ? 'primary' : 'secondary'} aria-pressed={cible === 'SOIGNANT'} onClick={() => setCible('SOIGNANT')} iconeGauche={<Users className="h-4 w-4" />}>Soignants</BoutonY2K>
                <BoutonY2K size="sm" variant={cible === 'ETABLISSEMENT' ? 'primary' : 'secondary'} aria-pressed={cible === 'ETABLISSEMENT'} onClick={() => setCible('ETABLISSEMENT')} iconeGauche={<Building2 className="h-4 w-4" />}>Établissements</BoutonY2K>
              </div>
            </fieldset>
            <div>
              <Label htmlFor="sourcing-departement" className="text-xs">Département</Label>
              <div className="relative mt-1">
                <MapPin className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden="true" />
                <Input id="sourcing-departement" value={departement} onChange={(event) => setDepartement(event.target.value)} placeholder="National, 56, 75, 92…" className="h-9 pl-8" />
              </div>
            </div>
            {cible === 'SOIGNANT' ? (
              <div>
                <Label htmlFor="sourcing-profession" className="text-xs">Profession</Label>
                <select id="sourcing-profession" className="input-base mt-1 h-9 w-full" value={profession} onChange={(event) => setProfession(event.target.value)}>
                  <option value="">Toutes les professions</option>
                  {PROFESSIONS.map((item) => <option key={item.valeur} value={item.valeur}>{item.label}</option>)}
                </select>
              </div>
            ) : (
              <div>
                <Label htmlFor="sourcing-type-etab" className="text-xs">Type d’établissement</Label>
                <select id="sourcing-type-etab" className="input-base mt-1 h-9 w-full" value={typeEtab} onChange={(event) => setTypeEtab(event.target.value)}>
                  {TYPES_ETAB.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
                </select>
              </div>
            )}
            <div className="flex items-end">
              <BoutonY2K size="sm" onClick={() => charger(1)} loading={loading} className="w-full" iconeGauche={<Search className="h-4 w-4" />}>Recalculer</BoutonY2K>
            </div>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            <BoutonY2K size="sm" variant={horsCrm ? 'primary' : 'secondary'} aria-pressed={horsCrm} onClick={() => setHorsCrm((value) => !value)}>Exclure CRM + inscrits</BoutonY2K>
            <BoutonY2K size="sm" variant={contactables ? 'primary' : 'secondary'} aria-pressed={contactables} onClick={() => setContactables((value) => !value)}>Avec coordonnées</BoutonY2K>
            <BoutonY2K size="sm" variant={nouveaux ? 'primary' : 'secondary'} aria-pressed={nouveaux} onClick={() => setNouveaux((value) => !value)}>Nouveaux depuis 30 jours</BoutonY2K>
          </div>
        </CardY2KContent>
      </CardY2K>

      {cible === 'SOIGNANT' && PROFESSIONS_SANS_ANNUAIRE_INDIVIDUEL_EXHAUSTIF.has(profession) && (
        <CardY2K hoverLift={false} noPadding className="border-warning/40">
          <CardY2KContent className="pt-6 sm:flex sm:items-center sm:justify-between sm:gap-4">
            <div>
              <h3 className="font-bold text-foreground">Compléter par les écoles et employeurs</h3>
              <p className="text-xs text-muted-foreground">
                Il n’existe pas d’annuaire public individuel exhaustif pour cette profession. Le canal fiable est donc le partenariat avec les IFAS/écoles et les établissements employeurs, sans collecter de profils personnels sur les réseaux sociaux.
              </p>
            </div>
            <BoutonY2K
              size="sm"
              variant="secondary"
              className="mt-3 shrink-0 sm:mt-0"
              onClick={() => { setCible('ETABLISSEMENT'); setTypeEtab('ECOLE_SANTE'); }}
              iconeGauche={<Building2 className="h-4 w-4" />}
            >
              Voir les écoles de santé
            </BoutonY2K>
          </CardY2KContent>
        </CardY2K>
      )}

      {data.besoins.length > 0 && (
        <CardY2K hoverLift={false} noPadding>
          <CardY2KContent className="pt-6">
            <div className="mb-3">
              <h3 className="font-bold text-foreground">Besoins actuellement ouverts sur Jolene</h3>
              <p className="text-xs text-muted-foreground">Ces tensions augmentent automatiquement la priorité des soignants correspondants.</p>
            </div>
            <div className="flex flex-wrap gap-2">
              {data.besoins.map((besoin) => (
                <button
                  key={`${besoin.profession}-${besoin.departement || 'national'}`}
                  type="button"
                  onClick={() => { setCible('SOIGNANT'); setProfession(besoin.profession); setDepartement(besoin.departement || ''); }}
                  className="min-h-[44px] rounded-xl border border-primary/20 bg-primary/5 px-3 py-2 text-left text-xs text-foreground transition-colors hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <strong>{getLabelProfession(besoin.profession)}</strong> · {besoin.departement || 'National'}
                  <span className="ml-2 text-primary">{besoin.missions_ouvertes} mission(s)</span>
                </button>
              ))}
            </div>
          </CardY2KContent>
        </CardY2K>
      )}

      <div className="flex items-center justify-between gap-2">
        <p className="text-xs text-muted-foreground">Page {data.page} sur {Math.max(data.total_pages, 1)} · classement recalculé à partir des données officielles</p>
        {loading && <span className="text-xs text-primary" role="status">Mise à jour…</span>}
      </div>

      {data.resultats.length === 0 ? (
        <CardY2K hoverLift={false} noPadding>
          <CardY2KContent className="pt-6 text-center">
            <CheckCircle2 className="mx-auto mb-2 h-8 w-8 text-emerald-600" aria-hidden="true" />
            <p className="font-semibold text-foreground">Aucun nouveau prospect pour ces filtres</p>
            <p className="text-sm text-muted-foreground">Élargissez la zone ou actualisez la source officielle.</p>
          </CardY2KContent>
        </CardY2K>
      ) : (
        <div className="grid gap-3 xl:grid-cols-2">
          {data.resultats.map((prospect) => {
            const busy = actionLoading === prospect.id;
            const nomComplet = prospect.prenom ? `${prospect.prenom} ${prospect.nom}` : prospect.nom;
            return (
              <CardY2K key={`${prospect.cible}-${prospect.id}`} hoverLift={false} noPadding>
                <CardY2KContent className="pt-6">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex flex-wrap gap-1.5">
                        <BadgeY2K variant={scoreVariant(prospect.score)}>Potentiel {prospect.score}/100</BadgeY2K>
                        {prospect.missions_ouvertes > 0 && <BadgeY2K variant="warning">{prospect.missions_ouvertes} mission(s) ouverte(s)</BadgeY2K>}
                        {prospect.mode_exercice && <BadgeY2K variant="info">{prospect.mode_exercice}</BadgeY2K>}
                      </div>
                      <h3 className="mt-2 font-bold text-foreground">{nomComplet}</h3>
                      <p className="text-xs text-muted-foreground">
                        {prospect.profession ? getLabelProfession(prospect.profession) : prospect.sous_titre || prospect.type_etab || 'Établissement'}
                        {prospect.ville ? ` · ${prospect.ville}` : ''}{prospect.departement ? ` (${prospect.departement})` : ''}
                      </p>
                      {prospect.sous_titre && prospect.profession && <p className="mt-0.5 truncate text-[11px] text-muted-foreground">{prospect.sous_titre}</p>}
                    </div>
                    <div className="shrink-0 text-right text-[11px] text-muted-foreground">
                      <Database className="ml-auto mb-1 h-4 w-4" aria-hidden="true" />
                      <p>{sourceLabel(prospect.source_code)}</p>
                      <p>Source : {formatDate(prospect.source_maj_le)}</p>
                    </div>
                  </div>

                  <dl className="mt-3 grid gap-2 rounded-xl bg-muted/40 p-3 text-xs sm:grid-cols-2">
                    <div className="flex min-w-0 gap-2">
                      <Phone className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" aria-hidden="true" />
                      <div><dt className="sr-only">Téléphone</dt><dd className="break-all text-foreground">{prospect.telephone || 'Non publié'}</dd></div>
                    </div>
                    <div className="flex min-w-0 gap-2">
                      <Mail className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" aria-hidden="true" />
                      <div><dt className="sr-only">Email</dt><dd className="break-all text-foreground">{prospect.email || 'Non publié'}</dd></div>
                    </div>
                    {prospect.numero_rpps && <div className="sm:col-span-2"><dt className="inline text-muted-foreground">RPPS : </dt><dd className="inline font-mono text-foreground">{prospect.numero_rpps}</dd></div>}
                    {prospect.finess_structure && <div className="sm:col-span-2"><dt className="inline text-muted-foreground">FINESS : </dt><dd className="inline font-mono text-foreground">{prospect.finess_structure}</dd></div>}
                  </dl>

                  <div className="mt-3 flex flex-wrap gap-2 border-t border-border pt-3">
                    <BoutonY2K size="sm" onClick={() => ajouterAuCrm(prospect)} loading={busy} iconeGauche={<Plus className="h-4 w-4" />}>Ajouter au CRM</BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => ignorer(prospect)} disabled={busy} iconeGauche={<EyeOff className="h-4 w-4" />}>Ignorer</BoutonY2K>
                    {prospect.source_url && (
                      <a href={prospect.source_url} target="_blank" rel="noreferrer" className="inline-flex min-h-[44px] items-center rounded-xl px-3 text-xs font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                        Vérifier la source
                      </a>
                    )}
                  </div>
                </CardY2KContent>
              </CardY2K>
            );
          })}
        </div>
      )}

      {data.total_pages > 1 && (
        <nav aria-label="Pagination du sourcing" className="flex items-center justify-center gap-2">
          <BoutonY2K size="sm" variant="secondary" disabled={page <= 1 || loading} onClick={() => charger(page - 1)}>Précédent</BoutonY2K>
          <span className="text-xs text-muted-foreground">{page}/{data.total_pages}</span>
          <BoutonY2K size="sm" variant="secondary" disabled={page >= data.total_pages || loading} onClick={() => charger(page + 1)}>Suivant</BoutonY2K>
        </nav>
      )}

      <CardY2K hoverLift={false} noPadding>
        <CardY2KContent className="pt-6">
          <div className="mb-3 flex items-start justify-between gap-2">
            <div>
              <h3 className="font-bold text-foreground">Fraîcheur des sources</h3>
              <p className="text-xs text-muted-foreground">Historique des imports silencieux. « Importé » ne signifie jamais « contacté ».</p>
            </div>
            <BadgeY2K variant="info">{data.imports.length} dernières exécutions</BadgeY2K>
          </div>
          {data.imports.length === 0 ? (
            <p className="py-3 text-center text-sm text-muted-foreground">Le prochain import officiel apparaîtra ici.</p>
          ) : (
            <ul className="divide-y divide-border">
              {data.imports.map((item) => (
                <li key={item.id} className="flex flex-col gap-1 py-2 text-xs sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <strong className="text-foreground">{sourceLabel(item.source_code)}</strong>
                    <span className="text-muted-foreground"> · démarré le {formatDate(item.demarre_le)}</span>
                    {item.erreur && <p className="mt-0.5 text-destructive">{item.erreur}</p>}
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="tabular-nums text-muted-foreground">{formatNombre(item.lignes_importees)} importés / {formatNombre(item.lignes_lues)} lus</span>
                    <BadgeY2K variant={item.statut === 'TERMINE' ? 'success' : item.statut === 'ERREUR' ? 'error' : 'warning'}>{item.statut === 'TERMINE' ? 'Terminé' : item.statut === 'ERREUR' ? 'Erreur' : 'En cours'}</BadgeY2K>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardY2KContent>
      </CardY2K>
    </section>
  );
}
