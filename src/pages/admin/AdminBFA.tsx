import { useEffect, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent, CardY2KHeader, CardY2KTitle } from '@/components/y2k/CardY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Gift, Save, RefreshCw, Calculator } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

interface Palier {
  id: string;
  nom: string;
  missions_min: number;
  missions_max: number | null;
  taux_bfa: number;
  ordre: number;
  est_actif: boolean;
}
interface GroupeBFA {
  id: string;
  nom: string;
  bfa_eligible: boolean;
  bfa_contrat_signe_le: string | null;
  nb_etablissements: number;
}

/* Gestion des paliers BFA (bonus de fin d'année) — le backend (paliers_bfa +
   RPCs de calcul) existait sans aucune interface : les paliers n'étaient
   modifiables qu'en SQL. Le widget soignant/étab (WidgetBFA, CarteBFAInfo)
   reflète automatiquement les changements faits ici. */
export default function AdminBFA() {
  usePageTitle('Paliers BFA');
  const [loading, setLoading] = useState(true);
  const [paliers, setPaliers] = useState<Palier[]>([]);
  const [groupes, setGroupes] = useState<GroupeBFA[]>([]);
  const [edit, setEdit] = useState<Record<string, { min: string; max: string; taux: string }>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [simulation, setSimulation] = useState<any>(null);
  const [simulEnCours, setSimulEnCours] = useState(false);

  const charger = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_paliers_bfa' as any);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Chargement impossible.');
      setLoading(false);
      return;
    }
    const d = data as any;
    setPaliers(d.paliers || []);
    setGroupes(d.groupes || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const sauvegarder = async (p: Palier) => {
    const e = edit[p.id];
    if (!e) return;
    const min = parseInt(e.min, 10);
    const max = e.max.trim() === '' ? null : parseInt(e.max, 10);
    const taux = parseFloat(e.taux);
    if (isNaN(min) || isNaN(taux) || (e.max.trim() !== '' && isNaN(max!))) {
      toast.error('Valeurs invalides.');
      return;
    }
    setSaving(p.id);
    try {
      const { data, error } = await supabase.rpc('fn_admin_modifier_palier_bfa' as any, {
        p_palier_id: p.id,
        p_missions_min: min,
        p_missions_max: max,
        p_taux_bfa: taux,
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Modification impossible.'); return; }
      toast.success(`Palier ${p.nom} mis à jour ✓`);
      setEdit(prev => { const { [p.id]: _r, ...rest } = prev; return rest; });
      charger();
    } finally {
      setSaving(null);
    }
  };

  const toggleActif = async (p: Palier) => {
    setSaving(p.id);
    try {
      const { data, error } = await supabase.rpc('fn_admin_modifier_palier_bfa' as any, {
        p_palier_id: p.id,
        p_est_actif: !p.est_actif,
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Modification impossible.'); return; }
      toast.success(p.est_actif ? `Palier ${p.nom} désactivé.` : `Palier ${p.nom} activé ✓`);
      charger();
    } finally {
      setSaving(null);
    }
  };

  const simuler = async () => {
    setSimulEnCours(true);
    try {
      const { data, error } = await supabase.rpc('fn_calculer_bfa_tous' as any);
      if (error) { toast.error('Simulation impossible.'); return; }
      setSimulation(data);
    } finally {
      setSimulEnCours(false);
    }
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Gift className="h-6 w-6 text-primary" /> Paliers BFA
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Bonus de fin d'année par volume de missions — les paliers s'appliquent au calcul automatique
            (les widgets côté établissements reflètent immédiatement les changements).
          </p>
        </div>

        {/* Paliers éditables */}
        <CardY2K noPadding>
          <CardY2KHeader><CardY2KTitle className="text-lg">Paliers ({paliers.length})</CardY2KTitle></CardY2KHeader>
          <CardY2KContent>
            <div className="space-y-3">
              {paliers.map((p) => {
                const e = edit[p.id];
                return (
                  <div key={p.id} className={`rounded-xl border p-3 flex flex-col md:flex-row md:items-center gap-3 ${p.est_actif ? 'border-border' : 'border-border bg-muted/30 opacity-70'}`}>
                    <div className="flex items-center gap-2 md:w-36 shrink-0">
                      <span className="font-semibold text-foreground">{p.nom}</span>
                      <BadgeY2K variant={p.est_actif ? 'success' : 'info'} size="sm">{p.est_actif ? 'Actif' : 'Inactif'}</BadgeY2K>
                    </div>
                    {e ? (
                      <div className="flex items-center gap-2 flex-wrap flex-1">
                        <label className="text-xs text-muted-foreground">De</label>
                        <Input type="number" min="0" value={e.min} onChange={ev => setEdit(prev => ({ ...prev, [p.id]: { ...e, min: ev.target.value } }))} className="w-24 h-8 text-xs text-center" />
                        <label className="text-xs text-muted-foreground">à</label>
                        <Input type="number" min="0" placeholder="∞" value={e.max} onChange={ev => setEdit(prev => ({ ...prev, [p.id]: { ...e, max: ev.target.value } }))} className="w-24 h-8 text-xs text-center" />
                        <label className="text-xs text-muted-foreground">missions →</label>
                        <Input type="number" step="0.5" min="0" max="50" value={e.taux} onChange={ev => setEdit(prev => ({ ...prev, [p.id]: { ...e, taux: ev.target.value } }))} className="w-20 h-8 text-xs text-center" />
                        <span className="text-xs">%</span>
                        <BoutonY2K size="sm" onClick={() => sauvegarder(p)} disabled={saving === p.id} loading={saving === p.id} iconeGauche={saving === p.id ? undefined : <Save className="h-3 w-3" />} className="h-8 text-xs">
                          Enregistrer
                        </BoutonY2K>
                        <BoutonY2K size="sm" variant="ghost" className="h-8 text-xs" onClick={() => setEdit(prev => { const { [p.id]: _r, ...rest } = prev; return rest; })}>
                          Annuler
                        </BoutonY2K>
                      </div>
                    ) : (
                      <div className="flex items-center gap-3 flex-wrap flex-1">
                        <p className="text-sm text-foreground">
                          {p.missions_min} → {p.missions_max ?? '∞'} missions ·{' '}
                          <strong className="text-primary">{Number(p.taux_bfa).toFixed(2)} % de BFA</strong>
                        </p>
                        <BoutonY2K size="sm" variant="secondary" className="h-8 text-xs"
                          onClick={() => setEdit(prev => ({ ...prev, [p.id]: { min: String(p.missions_min), max: p.missions_max == null ? '' : String(p.missions_max), taux: String(p.taux_bfa) } }))}>
                          Modifier
                        </BoutonY2K>
                        <BoutonY2K size="sm" variant="ghost" className="h-8 text-xs" onClick={() => toggleActif(p)} disabled={saving === p.id}>
                          {p.est_actif ? 'Désactiver' : 'Activer'}
                        </BoutonY2K>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </CardY2KContent>
        </CardY2K>

        {/* Simulation */}
        <CardY2K noPadding>
          <CardY2KHeader>
            <div className="flex items-center justify-between">
              <CardY2KTitle className="text-lg flex items-center gap-2"><Calculator className="h-5 w-5" /> Simulation d'impact</CardY2KTitle>
              <BoutonY2K size="sm" variant="secondary" onClick={simuler} disabled={simulEnCours} loading={simulEnCours} iconeGauche={simulEnCours ? undefined : <RefreshCw className="h-3.5 w-3.5" />}>
                Calculer le BFA de tous
              </BoutonY2K>
            </div>
          </CardY2KHeader>
          <CardY2KContent>
            {simulation ? (
              <pre className="text-xs bg-muted/40 rounded-xl p-3 overflow-x-auto max-h-80 whitespace-pre-wrap">
                {JSON.stringify(simulation, null, 2)}
              </pre>
            ) : (
              <p className="text-sm text-muted-foreground">
                Lance le calcul du BFA pour tous les établissements et groupes avec les paliers actuels —
                pratique pour vérifier l'impact avant/après une modification.
              </p>
            )}
          </CardY2KContent>
        </CardY2K>

        {/* Groupes éligibles */}
        <CardY2K noPadding>
          <CardY2KHeader><CardY2KTitle className="text-lg">Groupes ({groupes.length})</CardY2KTitle></CardY2KHeader>
          <CardY2KContent>
            {groupes.length === 0 ? (
              <p className="text-sm text-muted-foreground">Aucun groupe santé.</p>
            ) : (
              <div className="space-y-2">
                {groupes.map((g) => (
                  <div key={g.id} className="flex items-center justify-between rounded-lg border border-border p-3">
                    <div>
                      <p className="text-sm font-medium text-foreground">{g.nom}</p>
                      <p className="text-xs text-muted-foreground">
                        {g.nb_etablissements} établissement{g.nb_etablissements > 1 ? 's' : ''}
                        {g.bfa_contrat_signe_le && ` · contrat BFA signé le ${format(new Date(g.bfa_contrat_signe_le), 'dd/MM/yyyy', { locale: fr })}`}
                      </p>
                    </div>
                    <BadgeY2K variant={g.bfa_eligible ? 'success' : 'info'} size="sm">
                      {g.bfa_eligible ? 'Éligible BFA' : 'Non éligible'}
                    </BadgeY2K>
                  </div>
                ))}
              </div>
            )}
          </CardY2KContent>
        </CardY2K>
      </div>
    </LayoutAdmin>
  );
}
