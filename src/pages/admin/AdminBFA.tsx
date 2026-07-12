/**
 * AdminBFA — Refonte Sprint BFA
 *
 * Nouveau modèle : BFA = taux (%) × commissions Jolene sur les missions terminées de l'année
 * pour les groupes santé ou établissements isolés ayant signé un contrat spécial BFA.
 *
 * RPCs backend :
 *   fn_admin_bfa_lister           → liste groupes + étabs bénéficiaires
 *   fn_admin_bfa_definir_beneficiaire → ajouter / modifier / retirer un bénéficiaire
 *   fn_admin_bfa_detail_groupe    → drill-down établissements d'un groupe
 *   fn_admin_bfa_calculer         → calculer le BFA de l'année + enregistrer dans bfa_suivi
 *   fn_admin_bfa_marquer_verse    → marquer un BFA comme versé (post-virement SEPA manuel)
 */
import { useEffect, useState, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementSectionAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent, CardY2KHeader, CardY2KTitle } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Gift,
  ChevronDown,
  ChevronRight,
  Pencil,
  Check,
  X,
  Calculator,
  RefreshCw,
  Building2,
  Users,
  Euro,
  AlertCircle,
} from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

// ─── Types ────────────────────────────────────────────────────────────────────

interface BeneficiaireGroupe {
  type: 'GROUPE';
  id: string;
  nom: string;
  taux: number;
  contrat_signe_le: string | null;
  nb_etabs: number;
  nb_missions: number;
  commissions: number;
  montant_bfa: number;
  verse: boolean | null;
  suivi_id: string | null;
}

interface BeneficiaireEtab {
  type: 'ETABLISSEMENT';
  id: string;
  nom: string;
  taux: number;
  contrat_signe_le: string | null;
  nb_missions: number;
  commissions: number;
  montant_bfa: number;
  verse: boolean | null;
  suivi_id: string | null;
}

type Beneficiaire = BeneficiaireGroupe | BeneficiaireEtab;

interface DetailEtab {
  etablissement_id: string;
  nom: string;
  ville: string;
  nb_missions: number;
  ca_ht: number;
  commissions_ht: number;
}

interface GroupeSante {
  id: string;
  nom: string;
}

interface EtabSearchResult {
  id: string;
  nom: string;
  adresse_ville: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const EUR = (v: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 }).format(v);

const dateLocale = (s: string | null) =>
  s ? format(new Date(s), 'dd/MM/yyyy', { locale: fr }) : '—';

const todayISO = () => new Date().toISOString().split('T')[0];

const ANNEES = [2024, 2025, 2026] as const;

// ─── Sub-components ────────────────────────────────────────────────────────────

/** Inline taux editor (pencil → input + OK/Annuler) */
function TauxEditeur({
  id,
  type,
  tauxInitial,
  contratInitial,
  onSave,
}: {
  id: string;
  type: 'GROUPE' | 'ETABLISSEMENT';
  tauxInitial: number;
  contratInitial: string | null;
  onSave: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [taux, setTaux] = useState(String(tauxInitial));
  const [contrat, setContrat] = useState(contratInitial ?? '');
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    const t = parseFloat(taux);
    if (isNaN(t) || t < 0 || t > 100) {
      toast.error('Le taux doit être compris entre 0 et 100.');
      return;
    }
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_bfa_definir_beneficiaire' as any, {
        p_type: type,
        p_id: id,
        p_eligible: true,
        p_taux: t,
        p_contrat_signe_le: contrat.trim() || null,
      });
      if (error || (data as any)?.success === false) {
        toast.error((data as any)?.error ?? error?.message ?? 'Modification impossible.');
        return;
      }
      toast.success('Taux mis à jour.');
      setEditing(false);
      onSave();
    } finally {
      setSaving(false);
    }
  };

  if (!editing) {
    return (
      <button
        type="button"
        className="flex items-center gap-1 text-sm font-semibold text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-jolene-rose rounded"
        onClick={() => setEditing(true)}
        title="Modifier le taux"
      >
        {Number(tauxInitial).toFixed(2)} %
        <Pencil className="h-3 w-3 text-muted-foreground" />
      </button>
    );
  }

  return (
    <div className="flex items-center gap-1 flex-wrap">
      <Input
        aria-label="Taux BFA du bénéficiaire"
        type="number"
        step="0.5"
        min="0"
        max="100"
        value={taux}
        onChange={(e) => setTaux(e.target.value)}
        className="w-20 h-8 text-xs text-center"
        placeholder="Taux %"
      />
      <span className="text-xs">%</span>
      <Input
        aria-label="Date de signature du contrat BFA"
        type="date"
        value={contrat}
        onChange={(e) => setContrat(e.target.value)}
        className="w-36 h-8 text-xs"
        placeholder="Date contrat"
      />
      <BoutonY2K
        size="sm"
        onClick={handleSave}
        disabled={saving}
        loading={saving}
        iconeGauche={<Check className="h-3 w-3" />}
        className="h-8 text-xs"
      >
        OK
      </BoutonY2K>
      <BoutonY2K
        size="sm"
        variant="ghost"
        className="h-8 text-xs"
        onClick={() => {
          setEditing(false);
          setTaux(String(tauxInitial));
          setContrat(contratInitial ?? '');
        }}
        iconeGauche={<X className="h-3 w-3" />}
      >
        Annuler
      </BoutonY2K>
    </div>
  );
}

/** Drill-down détail groupe (lazy) */
function DetailGroupe({
  groupeId,
  annee,
}: {
  groupeId: string;
  annee: number;
}) {
  const [loading, setLoading] = useState(true);
  const [etabs, setEtabs] = useState<DetailEtab[]>([]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data, error } = await supabase.rpc('fn_admin_bfa_detail_groupe' as any, {
        p_groupe_id: groupeId,
        p_annee: annee,
      });
      if (cancelled) return;
      if (error) {
        toast.error('Impossible de charger le détail du groupe.');
        setLoading(false);
        return;
      }
      const d = data as any;
      setEtabs(d?.etablissements ?? []);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [groupeId, annee]);

  if (loading) {
    return (
      <div className="py-3 text-center text-sm text-muted-foreground">Chargement…</div>
    );
  }

  if (etabs.length === 0) {
    return (
      <div className="py-3 text-center text-sm text-muted-foreground">
        Aucun établissement dans ce groupe pour {annee}.
      </div>
    );
  }

  return (
    <div className="overflow-x-auto mt-1">
      <table className="w-full text-xs">
        <thead>
          <tr className="border-b border-border text-muted-foreground">
            <th className="text-left py-1.5 pr-3 font-medium">Établissement</th>
            <th className="text-left py-1.5 pr-3 font-medium">Ville</th>
            <th className="text-right py-1.5 pr-3 font-medium">Missions</th>
            <th className="text-right py-1.5 pr-3 font-medium">CA HT</th>
            <th className="text-right py-1.5 font-medium">Commissions HT</th>
          </tr>
        </thead>
        <tbody>
          {etabs.map((e) => (
            <tr key={e.etablissement_id} className="border-b border-border/50 last:border-0">
              <td className="py-1.5 pr-3 font-medium text-foreground">{e.nom}</td>
              <td className="py-1.5 pr-3 text-muted-foreground">{e.ville || '—'}</td>
              <td className="py-1.5 pr-3 text-right">{e.nb_missions}</td>
              <td className="py-1.5 pr-3 text-right">{EUR(e.ca_ht)}</td>
              <td className="py-1.5 text-right font-semibold text-primary">{EUR(e.commissions_ht)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Confirmation dialog simple (non-modal, inline) */
function ConfirmInline({
  message,
  onConfirm,
  onCancel,
  loading,
}: {
  message: string;
  onConfirm: () => void;
  onCancel: () => void;
  loading: boolean;
}) {
  return (
    <div className="mt-2 rounded-xl border border-border bg-muted/30 p-3 text-sm space-y-2">
      <p className="text-foreground">{message}</p>
      <div className="flex items-center gap-2">
        <BoutonY2K size="sm" onClick={onConfirm} loading={loading} disabled={loading} className="text-xs h-8">
          Confirmer
        </BoutonY2K>
        <BoutonY2K size="sm" variant="ghost" onClick={onCancel} disabled={loading} className="text-xs h-8">
          Annuler
        </BoutonY2K>
      </div>
    </div>
  );
}

// ─── Ligne bénéficiaire ────────────────────────────────────────────────────────

function LigneBeneficiaire({
  b,
  annee,
  onRefresh,
}: {
  b: Beneficiaire;
  annee: number;
  onRefresh: () => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const [confirmRetirer, setConfirmRetirer] = useState(false);
  const [confirmVerser, setConfirmVerser] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);

  const handleRetirer = async () => {
    setActionLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_bfa_definir_beneficiaire' as any, {
        p_type: b.type,
        p_id: b.id,
        p_eligible: false,
        p_taux: null,
        p_contrat_signe_le: null,
      });
      if (error || (data as any)?.success === false) {
        toast.error((data as any)?.error ?? error?.message ?? 'Suppression impossible.');
        return;
      }
      toast.success(`${b.nom} retiré des bénéficiaires BFA.`);
      setConfirmRetirer(false);
      onRefresh();
    } finally {
      setActionLoading(false);
    }
  };

  const handleMarquerVerse = async () => {
    if (!b.suivi_id) return;
    setActionLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_bfa_marquer_verse' as any, {
        p_suivi_id: b.suivi_id,
        p_date: todayISO(),
      });
      if (error || (data as any)?.success === false) {
        toast.error((data as any)?.error ?? error?.message ?? 'Impossible de marquer comme versé.');
        return;
      }
      toast.success(`BFA de ${b.nom} marqué comme versé.`);
      setConfirmVerser(false);
      onRefresh();
    } finally {
      setActionLoading(false);
    }
  };

  const isGroupe = b.type === 'GROUPE';

  return (
    <div className="rounded-xl border border-border p-3 space-y-2">
      {/* Ligne principale */}
      <div className="flex flex-col md:flex-row md:items-center gap-3">
        {/* Expand + nom */}
        <div className="flex items-center gap-2 flex-1 min-w-0">
          {isGroupe && (
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              className="shrink-0 text-muted-foreground hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-jolene-rose rounded"
              aria-label={expanded ? 'Réduire' : 'Voir les établissements'}
            >
              {expanded ? (
                <ChevronDown className="h-4 w-4" />
              ) : (
                <ChevronRight className="h-4 w-4" />
              )}
            </button>
          )}
          <div className="min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-semibold text-foreground text-sm truncate">{b.nom}</span>
              <BadgeY2K variant={isGroupe ? 'premium' : 'info'} size="sm">
                {isGroupe ? 'Groupe' : 'Étab.'}
              </BadgeY2K>
            </div>
            {b.contrat_signe_le && (
              <p className="text-xs text-muted-foreground mt-0.5">
                Contrat signé le {dateLocale(b.contrat_signe_le)}
                {isGroupe && (b as BeneficiaireGroupe).nb_etabs > 0 && (
                  <> · {(b as BeneficiaireGroupe).nb_etabs} établissement{(b as BeneficiaireGroupe).nb_etabs > 1 ? 's' : ''}</>
                )}
              </p>
            )}
          </div>
        </div>

        {/* Taux éditable */}
        <div className="shrink-0">
          <TauxEditeur
            id={b.id}
            type={b.type}
            tauxInitial={b.taux}
            contratInitial={b.contrat_signe_le}
            onSave={onRefresh}
          />
        </div>

        {/* Stats */}
        <div className="flex items-center gap-4 text-xs text-muted-foreground shrink-0">
          <span>{b.nb_missions} mission{b.nb_missions > 1 ? 's' : ''}</span>
          <span>{EUR(b.commissions)} commissions</span>
        </div>

        {/* Montant BFA */}
        <div className="shrink-0 rounded-lg bg-jolene-rose-50 border border-jolene-rose-200 px-3 py-1 text-center">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Montant BFA</p>
          <p className="text-base font-bold text-primary">{EUR(b.montant_bfa)}</p>
        </div>

        {/* Statut versement */}
        <div className="shrink-0 flex flex-col items-start gap-1">
          {b.verse ? (
            <BadgeY2K variant="success" size="sm">Versé</BadgeY2K>
          ) : b.suivi_id ? (
            <BoutonY2K
              size="sm"
              variant="secondary"
              className="text-xs h-8 whitespace-nowrap"
              onClick={() => setConfirmVerser(true)}
              disabled={actionLoading}
            >
              Marquer comme versé
            </BoutonY2K>
          ) : (
            <span
              className="text-xs text-muted-foreground italic cursor-help"
              title="Cliquez d'abord sur Calculer le BFA"
            >
              Pas encore calculé
            </span>
          )}
        </div>

        {/* Retirer */}
        <BoutonY2K
          size="sm"
          variant="ghost"
          className="text-xs h-8 shrink-0 text-destructive hover:text-destructive hover:bg-destructive/10"
          onClick={() => setConfirmRetirer(true)}
          disabled={actionLoading}
        >
          Retirer
        </BoutonY2K>
      </div>

      {/* Confirm retirer */}
      {confirmRetirer && (
        <ConfirmInline
          message={`Retirer ${b.nom} des bénéficiaires BFA ? Le contrat et le taux seront supprimés.`}
          onConfirm={handleRetirer}
          onCancel={() => setConfirmRetirer(false)}
          loading={actionLoading}
        />
      )}

      {/* Confirm verser */}
      {confirmVerser && (
        <ConfirmInline
          message={`Confirmez que le virement SEPA de ${EUR(b.montant_bfa)} à ${b.nom} a été effectué.`}
          onConfirm={handleMarquerVerse}
          onCancel={() => setConfirmVerser(false)}
          loading={actionLoading}
        />
      )}

      {/* Drill-down groupe */}
      {isGroupe && expanded && (
        <div className="ml-6 border-l-2 border-jolene-rose-200 pl-3">
          <DetailGroupe groupeId={b.id} annee={annee} />
        </div>
      )}
    </div>
  );
}

// ─── Panel "Ajouter un bénéficiaire" ──────────────────────────────────────────

function PanelAjout({
  annee,
  groupesExistants,
  etabsExistants,
  onAdded,
}: {
  annee: number;
  groupesExistants: string[];
  etabsExistants: string[];
  onAdded: () => void;
}) {
  const [typeAjout, setTypeAjout] = useState<'GROUPE' | 'ETABLISSEMENT'>('GROUPE');
  const [groupeId, setGroupeId] = useState('');
  const [etabId, setEtabId] = useState('');
  const [etabQuery, setEtabQuery] = useState('');
  const [etabResults, setEtabResults] = useState<EtabSearchResult[]>([]);
  const [etabSelectionne, setEtabSelectionne] = useState<EtabSearchResult | null>(null);
  const [taux, setTaux] = useState('');
  const [contrat, setContrat] = useState('');
  const [saving, setSaving] = useState(false);
  const [searchingEtabs, setSearchingEtabs] = useState(false);

  // All groups
  const [allGroupes, setAllGroupes] = useState<GroupeSante[]>([]);
  useEffect(() => {
    supabase
      .from('groupes_sante')
      .select('id, nom')
      .order('nom')
      .then(({ data }) => setAllGroupes((data as GroupeSante[]) ?? []));
  }, []);

  const groupesDisponibles = allGroupes.filter((g) => !groupesExistants.includes(g.id));

  // Debounced étab search
  useEffect(() => {
    if (typeAjout !== 'ETABLISSEMENT' || etabQuery.trim().length < 2) {
      setEtabResults([]);
      return;
    }
    const timer = setTimeout(async () => {
      setSearchingEtabs(true);
      const { data } = await supabase
        .from('etablissements')
        .select('id, nom, adresse_ville')
        .is('groupe_sante_id', null)
        .ilike('nom', `%${etabQuery.trim()}%`)
        .limit(10);
      setEtabResults(
        ((data as EtabSearchResult[]) ?? []).filter((e) => !etabsExistants.includes(e.id))
      );
      setSearchingEtabs(false);
    }, 300);
    return () => clearTimeout(timer);
  }, [etabQuery, typeAjout, etabsExistants]);

  const handleAjouter = async () => {
    const t = parseFloat(taux);
    if (isNaN(t) || t < 0 || t > 100) {
      toast.error('Taux invalide (0–100).');
      return;
    }
    const targetId = typeAjout === 'GROUPE' ? groupeId : etabId;
    if (!targetId) {
      toast.error(typeAjout === 'GROUPE' ? 'Sélectionnez un groupe.' : 'Sélectionnez un établissement.');
      return;
    }
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_bfa_definir_beneficiaire' as any, {
        p_type: typeAjout,
        p_id: targetId,
        p_eligible: true,
        p_taux: t,
        p_contrat_signe_le: contrat.trim() || null,
      });
      if (error || (data as any)?.success === false) {
        toast.error((data as any)?.error ?? error?.message ?? 'Ajout impossible.');
        return;
      }
      toast.success('Bénéficiaire BFA ajouté.');
      // reset
      setGroupeId('');
      setEtabId('');
      setEtabQuery('');
      setEtabSelectionne(null);
      setTaux('');
      setContrat('');
      onAdded();
    } finally {
      setSaving(false);
    }
  };

  return (
    <CardY2K noPadding>
      <CardY2KHeader>
        <CardY2KTitle className="text-lg flex items-center gap-2">
          <Building2 className="h-5 w-5" /> Ajouter un bénéficiaire
        </CardY2KTitle>
      </CardY2KHeader>
      <CardY2KContent>
        <div className="space-y-4">
          {/* Toggle type */}
          <div className="flex items-center gap-2">
            <BoutonY2K
              size="sm"
              variant={typeAjout === 'GROUPE' ? 'primary' : 'secondary'}
              className="text-xs h-8"
              onClick={() => { setTypeAjout('GROUPE'); setEtabId(''); setEtabQuery(''); setEtabSelectionne(null); }}
              iconeGauche={<Users className="h-3.5 w-3.5" />}
            >
              Groupe
            </BoutonY2K>
            <BoutonY2K
              size="sm"
              variant={typeAjout === 'ETABLISSEMENT' ? 'primary' : 'secondary'}
              className="text-xs h-8"
              onClick={() => { setTypeAjout('ETABLISSEMENT'); setGroupeId(''); }}
              iconeGauche={<Building2 className="h-3.5 w-3.5" />}
            >
              Établissement isolé
            </BoutonY2K>
          </div>

          {/* Sélection */}
          {typeAjout === 'GROUPE' ? (
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Groupe santé</label>
              <Select value={groupeId} onValueChange={setGroupeId}>
                <SelectTrigger className="text-sm" aria-label="Groupe santé bénéficiaire">
                  <SelectValue placeholder="Sélectionner un groupe…" />
                </SelectTrigger>
                <SelectContent>
                  {groupesDisponibles.length === 0 ? (
                    <div className="px-3 py-2 text-xs text-muted-foreground">
                      Tous les groupes sont déjà bénéficiaires.
                    </div>
                  ) : (
                    groupesDisponibles.map((g) => (
                      <SelectItem key={g.id} value={g.id}>
                        {g.nom}
                      </SelectItem>
                    ))
                  )}
                </SelectContent>
              </Select>
            </div>
          ) : (
            <div className="space-y-2">
              <label className="text-xs font-medium text-muted-foreground block">
                Établissement (sans groupe, recherche par nom)
              </label>
              {etabSelectionne ? (
                <div className="flex items-center gap-2 rounded-lg border border-jolene-rose-200 bg-jolene-rose-50 px-3 py-2 text-sm">
                  <span className="flex-1 font-medium">{etabSelectionne.nom}</span>
                  <span className="text-muted-foreground text-xs">{etabSelectionne.adresse_ville}</span>
                  <button
                    type="button"
                    onClick={() => { setEtabSelectionne(null); setEtabId(''); setEtabQuery(''); }}
                    aria-label={`Retirer l’établissement ${etabSelectionne.nom} de la sélection`}
                    className="text-muted-foreground hover:text-destructive transition-colors"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                <div className="relative">
                  <Input
                    aria-label="Rechercher un établissement bénéficiaire"
                    type="text"
                    placeholder="Rechercher un établissement…"
                    value={etabQuery}
                    onChange={(e) => setEtabQuery(e.target.value)}
                    className="text-sm"
                  />
                  {searchingEtabs && (
                    <div className="absolute right-3 top-1/2 -translate-y-1/2">
                      <RefreshCw className="h-4 w-4 animate-spin text-muted-foreground" />
                    </div>
                  )}
                  {etabResults.length > 0 && (
                    <div className="absolute z-10 mt-1 w-full rounded-xl border border-border bg-background shadow-lg overflow-hidden">
                      {etabResults.map((e) => (
                        <button
                          key={e.id}
                          type="button"
                          className="w-full text-left px-3 py-2 text-sm hover:bg-muted/50 flex items-center justify-between"
                          onClick={() => {
                            setEtabSelectionne(e);
                            setEtabId(e.id);
                            setEtabQuery('');
                            setEtabResults([]);
                          }}
                        >
                          <span className="font-medium">{e.nom}</span>
                          <span className="text-xs text-muted-foreground">{e.adresse_ville}</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Taux + date contrat */}
          <div className="flex items-end gap-3 flex-wrap">
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Taux BFA (%)</label>
              <div className="flex items-center gap-1">
                <Input
                  aria-label="Taux BFA du nouveau bénéficiaire"
                  type="number"
                  step="0.5"
                  min="0"
                  max="100"
                  value={taux}
                  onChange={(e) => setTaux(e.target.value)}
                  className="w-24 text-sm text-center"
                  placeholder="ex. 2"
                />
                <span className="text-sm text-muted-foreground">%</span>
              </div>
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                Date contrat signé
              </label>
              <Input
                aria-label="Date de signature du contrat du nouveau bénéficiaire"
                type="date"
                value={contrat}
                onChange={(e) => setContrat(e.target.value)}
                className="w-40 text-sm"
              />
            </div>
            <BoutonY2K
              size="md"
              onClick={handleAjouter}
              loading={saving}
              disabled={saving}
              iconeGauche={<Check className="h-4 w-4" />}
            >
              Ajouter
            </BoutonY2K>
          </div>
        </div>
      </CardY2KContent>
    </CardY2K>
  );
}

// ─── Page principale ───────────────────────────────────────────────────────────

export default function AdminBFA() {
  usePageTitle('Programme BFA');

  const [annee, setAnnee] = useState<number>(2026);
  const [loading, setLoading] = useState(true);
  const [groupes, setGroupes] = useState<BeneficiaireGroupe[]>([]);
  const [etabs, setEtabs] = useState<BeneficiaireEtab[]>([]);
  const [calculEnCours, setCalculEnCours] = useState(false);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_bfa_lister' as any, { p_annee: annee });
    if (error) {
      toast.error('Chargement impossible : ' + error.message);
      setLoading(false);
      return;
    }
    const d = data as any;
    setGroupes(d?.groupes ?? []);
    setEtabs(d?.etablissements ?? []);
    setLoading(false);
  }, [annee]);

  useEffect(() => {
    charger();
  }, [charger]);

  const handleCalculer = async () => {
    setCalculEnCours(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_bfa_calculer' as any, {
        p_annee: annee,
      });
      if (error || (data as any)?.success === false) {
        toast.error(
          (data as any)?.error ?? error?.message ?? 'Calcul impossible.'
        );
        return;
      }
      const d = data as any;
      const n = d?.beneficiaires_calcules ?? 0;
      toast.success(`${n} bénéficiaire${n > 1 ? 's' : ''} calculé${n > 1 ? 's' : ''} pour ${annee}.`);
      charger();
    } finally {
      setCalculEnCours(false);
    }
  };

  const tousLesBeneficiaires: Beneficiaire[] = [...groupes, ...etabs];
  const totalBFA = tousLesBeneficiaires.reduce((s, b) => s + (b.montant_bfa ?? 0), 0);
  const nbVerses = tousLesBeneficiaires.filter((b) => b.verse).length;
  const nbAVerser = tousLesBeneficiaires.filter((b) => !b.verse && (b.montant_bfa ?? 0) > 0).length;
  const totalVerses = tousLesBeneficiaires.filter((b) => b.verse).reduce((s, b) => s + (b.montant_bfa ?? 0), 0);

  const groupeIds = groupes.map((g) => g.id);
  const etabIds = etabs.map((e) => e.id);

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        {/* En-tête */}
        <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
              <Gift className="h-6 w-6 text-primary" /> Programme BFA — Bonus Fin d'Année
            </h1>
            <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
              Les groupes et établissements ayant signé le contrat spécial BFA. Le bonus = taux ×
              commissions Jolene encaissées sur leurs missions terminées de l'année.
            </p>
          </div>

          {/* Sélecteur d'année */}
          <div className="shrink-0">
            <label className="text-xs font-medium text-muted-foreground mb-1 block">Année</label>
            <Select value={String(annee)} onValueChange={(v) => setAnnee(Number(v))}>
              <SelectTrigger className="w-28 text-sm" aria-label="Année du programme BFA">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {ANNEES.map((a) => (
                  <SelectItem key={a} value={String(a)}>
                    {a}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        {loading ? (
          <ChargementSectionAdmin label="Chargement du programme BFA…" />
        ) : (
          <>
            {/* KPIs */}
            {tousLesBeneficiaires.length > 0 && (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                <CarteKPIY2K
                  label="Bénéficiaires"
                  valeur={tousLesBeneficiaires.length}
                  icone={<Users className="h-4 w-4" />}
                  variant="default"
                />
                <CarteKPIY2K
                  label="Total BFA à verser"
                  valeur={EUR(totalBFA)}
                  icone={<Euro className="h-4 w-4" />}
                  variant="holographic"
                />
                <CarteKPIY2K
                  label="Versés"
                  valeur={`${nbVerses} (${EUR(totalVerses)})`}
                  icone={<Check className="h-4 w-4" />}
                  variant="soft"
                />
                <CarteKPIY2K
                  label="À verser"
                  valeur={nbAVerser}
                  icone={<Gift className="h-4 w-4" />}
                  variant="default"
                />
              </div>
            )}

            {/* Section bénéficiaires */}
            <CardY2K noPadding>
              <CardY2KHeader>
                <CardY2KTitle className="text-lg">
                  Bénéficiaires ({tousLesBeneficiaires.length})
                </CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                {tousLesBeneficiaires.length === 0 ? (
                  <div className="flex flex-col items-center gap-2 py-6 text-center text-muted-foreground">
                    <Gift className="h-8 w-8 opacity-40" />
                    <p className="text-sm">
                      Aucun bénéficiaire BFA. Ajoutez un groupe ou un établissement ayant signé le
                      contrat spécial.
                    </p>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {tousLesBeneficiaires.map((b) => (
                      <LigneBeneficiaire
                        key={`${b.type}-${b.id}`}
                        b={b}
                        annee={annee}
                        onRefresh={charger}
                      />
                    ))}
                  </div>
                )}
              </CardY2KContent>
            </CardY2K>

            {/* Ajouter un bénéficiaire */}
            <PanelAjout
              annee={annee}
              groupesExistants={groupeIds}
              etabsExistants={etabIds}
              onAdded={charger}
            />

            {/* Calcul & versements */}
            <CardY2K noPadding>
              <CardY2KHeader>
                <div className="flex items-center justify-between flex-wrap gap-3">
                  <CardY2KTitle className="text-lg flex items-center gap-2">
                    <Calculator className="h-5 w-5" /> Calcul &amp; versements {annee}
                  </CardY2KTitle>
                  <BoutonY2K
                    size="sm"
                    variant="secondary"
                    onClick={handleCalculer}
                    loading={calculEnCours}
                    disabled={calculEnCours}
                    iconeGauche={calculEnCours ? undefined : <RefreshCw className="h-3.5 w-3.5" />}
                  >
                    Calculer le BFA {annee}
                  </BoutonY2K>
                </div>
              </CardY2KHeader>
              <CardY2KContent>
                {tousLesBeneficiaires.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    Ajoutez des bénéficiaires pour lancer le calcul.
                  </p>
                ) : (
                  <div className="space-y-3">
                    <div className="rounded-xl bg-muted/30 border border-border p-3 text-sm space-y-1">
                      <p>
                        <span className="font-semibold">Total BFA à verser :</span>{' '}
                        <span className="text-primary font-bold">{EUR(totalBFA)}</span>
                      </p>
                      <p className="text-muted-foreground">
                        {nbVerses} versé{nbVerses > 1 ? 's' : ''} ({EUR(totalVerses)}) ·{' '}
                        {nbAVerser} en attente
                      </p>
                    </div>
                    <div className="flex items-start gap-2 rounded-xl bg-jolene-butter-50 border border-jolene-butter-300 p-3 text-xs text-jolene-butter-800">
                      <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
                      <p>
                        Le virement SEPA est exécuté manuellement (validez le montant, faites le
                        virement vers le RIB du bénéficiaire, puis marquez comme versé).
                        L'automatisation Swan est une étape ultérieure.
                      </p>
                    </div>
                  </div>
                )}
              </CardY2KContent>
            </CardY2K>
          </>
        )}
      </div>
    </LayoutAdmin>
  );
}
