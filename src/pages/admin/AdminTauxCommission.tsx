import { useEffect, useMemo, useState } from 'react';
import { Building2, Layers, Pencil, Save, Search, X } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Groupe {
  id: string;
  nom: string;
  siren: string | null;
  taux_commission_negocie: number | null;
  contrat_debut: string | null;
  contrat_fin: string | null;
  nb_etablissements: number;
}

interface Etablissement {
  id: string;
  nom: string;
  siret: string | null;
  taux_commission_negocie: number | null;
  groupe_id: string | null;
  groupe_nom: string | null;
  taux_groupe: number | null;
  taux_resolu: number;
  taux_resolu_source: 'etablissement' | 'groupe' | 'defaut_15';
}

const SOURCE_LABEL: Record<Etablissement['taux_resolu_source'], string> = {
  etablissement: 'Étab',
  groupe: 'Groupe',
  defaut_15: 'Défaut 15%',
};

const SOURCE_COLOR: Record<Etablissement['taux_resolu_source'], string> = {
  etablissement: 'bg-primary/10 text-primary',
  groupe: 'bg-info/10 text-info',
  defaut_15: 'bg-muted text-muted-foreground',
};

export default function AdminTauxCommission() {
  usePageTitle('Taux commission');
  const [loading, setLoading] = useState(true);
  const [groupes, setGroupes] = useState<Groupe[]>([]);
  const [etabs, setEtabs] = useState<Etablissement[]>([]);
  const [editing, setEditing] = useState<{ kind: 'etab' | 'groupe'; id: string; nom: string; current: number | null } | null>(null);
  const [nouveauTaux, setNouveauTaux] = useState<string>('');
  const [raison, setRaison] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [recherche, setRecherche] = useState<string>('');

  // Pattern « file de travail » léger : les entités jamais négociées (défaut 15 %) remontent en tête.
  const groupesTries = useMemo(
    () => [...groupes].sort((a, b) =>
      (a.taux_commission_negocie == null ? 0 : 1) - (b.taux_commission_negocie == null ? 0 : 1)
    ),
    [groupes]
  );

  const normaliser = (s: string) => s.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '');

  const etabsAffiches = useMemo(() => {
    const terme = normaliser(recherche.trim());
    const filtres = terme ? etabs.filter(e => normaliser(e.nom).includes(terme)) : etabs;
    return [...filtres].sort((a, b) =>
      (a.taux_resolu_source === 'defaut_15' ? 0 : 1) - (b.taux_resolu_source === 'defaut_15' ? 0 : 1)
    );
  }, [etabs, recherche]);

  const charger = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_taux_commission' as any);
    if (error || (data as any)?.success === false) {
      toast.error((data as any)?.error || error?.message || 'Erreur de chargement');
      setLoading(false);
      return;
    }
    setGroupes(((data as any).groupes || []) as Groupe[]);
    setEtabs(((data as any).etablissements || []) as Etablissement[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  useEffect(() => {
    if (!editing) return;
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !saving) fermerEdition();
    };
    document.addEventListener('keydown', fermerAvecEchap);
    return () => document.removeEventListener('keydown', fermerAvecEchap);
  }, [editing, saving]);

  const ouvrirEdition = (kind: 'etab' | 'groupe', id: string, nom: string, current: number | null) => {
    setEditing({ kind, id, nom, current });
    setNouveauTaux(current != null ? String(current) : '');
    setRaison('');
  };

  const fermerEdition = () => {
    setEditing(null);
    setNouveauTaux('');
    setRaison('');
  };

  const enregistrer = async () => {
    if (!editing) return;
    if (!raison.trim()) {
      toast.error('Raison obligatoire (audit)');
      return;
    }
    const tauxNum = nouveauTaux === '' ? null : parseFloat(nouveauTaux);
    if (tauxNum !== null && (Number.isNaN(tauxNum) || tauxNum < 0 || tauxNum > 100)) {
      toast.error('Taux invalide (0-100 ou vide)');
      return;
    }
    setSaving(true);
    const params: any = { p_nouveau_taux: tauxNum, p_raison: raison };
    if (editing.kind === 'etab') params.p_etablissement_id = editing.id;
    else params.p_groupe_id = editing.id;
    const { data, error } = await supabase.rpc('fn_admin_modifier_taux_commission' as any, params);
    if (error || (data as any)?.success === false) {
      toast.error((data as any)?.error || error?.message || 'Erreur');
      setSaving(false);
      return;
    }
    toast.success(`Taux modifié pour ${editing.nom}. Impacte les futures missions uniquement.`);
    setSaving(false);
    fermerEdition();
    charger();
  };

  const fmtTaux = (t: number | null) => t == null ? '—' : `${Number(t).toFixed(2)} %`;

  if (loading) {
    return (
      <LayoutAdmin>
        <ChargementAdmin titre="Taux de commission" />
      </LayoutAdmin>
    );
  }

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Taux commission" />
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Layers className="h-6 w-6 text-primary" /> Taux de commission
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Cascade : <strong>établissement</strong> &gt; <strong>groupe</strong> &gt; défaut 15 %.
            Les modifications n'impactent que les <strong>futures missions assignées</strong> (les missions
            déjà gelées conservent leur taux historique).
          </p>
        </div>

        {/* Groupes */}
        <section>
          <h2 className="text-base font-bold text-foreground mb-3 flex items-center gap-2">
            <Layers className="h-4 w-4" /> Groupes ({groupes.length})
          </h2>
          {groupes.length === 0 ? (
            <p className="text-sm text-muted-foreground card-base">Aucun groupe</p>
          ) : (
            <div className="card-base divide-y divide-border">
              {groupesTries.map(g => (
                <div key={g.id} className="py-3 flex items-center justify-between gap-3">
                  <div className="flex-1">
                    <p className="font-medium text-foreground">{g.nom}</p>
                    <p className="text-xs text-muted-foreground">
                      SIREN {g.siren || '—'} · {g.nb_etablissements} étab.
                      {g.contrat_debut && ` · contrat ${g.contrat_debut}${g.contrat_fin ? ` → ${g.contrat_fin}` : ''}`}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-lg font-bold text-foreground">{fmtTaux(g.taux_commission_negocie)}</p>
                    {g.taux_commission_negocie == null && (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
                        Défaut 15%
                      </span>
                    )}
                  </div>
                  <BoutonY2K size="sm" variant="secondary" onClick={() => ouvrirEdition('groupe', g.id, g.nom, g.taux_commission_negocie)} className="gap-1" iconeGauche={<Pencil className="h-3.5 w-3.5" />}>
                    Modifier
                  </BoutonY2K>
                </div>
              ))}
            </div>
          )}
        </section>

        {/* Établissements */}
        <section>
          <h2 className="text-base font-bold text-foreground mb-3 flex items-center gap-2">
            <Building2 className="h-4 w-4" /> Établissements ({etabs.length})
          </h2>
          <div className="relative mb-3">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
            <input
              type="search"
              value={recherche}
              onChange={e => setRecherche(e.target.value)}
              placeholder="Rechercher un établissement par nom…"
              aria-label="Rechercher un établissement par nom"
              className="input-base pl-9"
            />
          </div>
          {etabsAffiches.length === 0 ? (
            <p className="text-sm text-muted-foreground card-base">
              {etabs.length === 0 ? 'Aucun établissement' : 'Aucun établissement ne correspond à votre recherche.'}
            </p>
          ) : (
            <div className="card-base divide-y divide-border">
              {etabsAffiches.map(e => (
                <div key={e.id} className="py-3 flex items-center justify-between gap-3">
                  <div className="flex-1">
                    <p className="font-medium text-foreground">{e.nom}</p>
                    <p className="text-xs text-muted-foreground">
                      SIRET {e.siret || '—'}
                      {e.groupe_nom && <> · Groupe : <span className="text-foreground">{e.groupe_nom}</span></>}
                    </p>
                    <p className="text-[10px] text-muted-foreground mt-0.5">
                      Étab : {fmtTaux(e.taux_commission_negocie)}
                      {e.groupe_nom && ` · Groupe : ${fmtTaux(e.taux_groupe)}`}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-lg font-bold text-foreground">{fmtTaux(e.taux_resolu)}</p>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${SOURCE_COLOR[e.taux_resolu_source]}`}>
                      {SOURCE_LABEL[e.taux_resolu_source]}
                    </span>
                  </div>
                  <BoutonY2K size="sm" variant="secondary" onClick={() => ouvrirEdition('etab', e.id, e.nom, e.taux_commission_negocie)} className="gap-1" iconeGauche={<Pencil className="h-3.5 w-3.5" />}>
                    Modifier
                  </BoutonY2K>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => !saving && fermerEdition()}>
          <div className="bg-background rounded-xl shadow-xl max-w-md w-full p-6 space-y-4" role="dialog" aria-modal="true" aria-labelledby="admin-taux-dialog-title" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 id="admin-taux-dialog-title" className="text-lg font-bold text-foreground">
                Modifier le taux — {editing.nom}
              </h3>
              <button aria-label="Fermer la modification du taux" onClick={fermerEdition} disabled={saving} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>
            <p className="text-xs text-muted-foreground">
              Cible : <strong>{editing.kind === 'etab' ? 'Établissement' : 'Groupe'}</strong>.
              Le nouveau taux ne s'appliquera qu'aux <strong>missions assignées après cette modification</strong>.
            </p>
            <div>
              <label htmlFor="admin-taux-nouveau" className="text-sm font-medium text-foreground mb-1.5 block">Nouveau taux (%)</label>
              <input
                id="admin-taux-nouveau"
                type="number"
                step="0.01"
                min="0"
                max="100"
                value={nouveauTaux}
                onChange={e => setNouveauTaux(e.target.value)}
                placeholder="Vide pour utiliser la cascade (groupe ou défaut 15 %)"
                className="input-base"
              />
              <p className="text-[10px] text-muted-foreground mt-1">
                Laisser vide pour effacer (cascade : {editing.kind === 'etab' ? 'remontera vers le groupe ou défaut 15%' : 'établissements basculeront sur le défaut 15%'}).
              </p>
            </div>
            <div>
              <label htmlFor="admin-taux-raison" className="text-sm font-medium text-foreground mb-1.5 block">Raison <span className="text-destructive">*</span></label>
              <textarea
                id="admin-taux-raison"
                value={raison}
                onChange={e => setRaison(e.target.value)}
                placeholder="Ex : Renégociation contrat-cadre client X au 01/05/2026"
                rows={2}
                className="input-base"
              />
              <p className="text-[10px] text-muted-foreground mt-1">
                Audité dans <code>journaux_audit</code> (action <code>TAUX_COMMISSION_MODIFIE</code>).
              </p>
            </div>
            <div className="flex gap-2 justify-end pt-2">
              <BoutonY2K variant="secondary" disabled={saving} onClick={fermerEdition}>Annuler</BoutonY2K>
              <BoutonY2K disabled={saving || !raison.trim()} loading={saving} onClick={enregistrer} className="gap-2" iconeGauche={saving ? undefined : <Save className="h-4 w-4" />}>
                Enregistrer
              </BoutonY2K>
            </div>
          </div>
        </div>
      )}
    </LayoutAdmin>
  );
}
