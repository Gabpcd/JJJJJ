import { useEffect, useState } from 'react';
import { GraduationCap, Loader2, Plus, Trash2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { PROFESSIONS, getLabelProfession } from '@/lib/constantes';
import { FORMATIONS_ETUDIANT } from '@/components/inscription/DeclarationEtudiant';

interface Equivalence {
  id: string;
  formation: string;
  libelle_formation: string;
  annee_validee_min: number;
  profession_autorisee: string;
  base_reglementaire: string | null;
  actif: boolean;
}

const FORMATION_OPTIONS = [
  ...FORMATIONS_ETUDIANT,
  { valeur: 'AUTRE', label: 'Autre formation' },
];

/**
 * Éditeur admin des règles d'équivalence étudiant (table equivalences_scolarite,
 * RLS réservée à est_admin). Permet d'ajouter/activer/supprimer une règle
 * « formation + année validée → profession faisant fonction » sans déploiement.
 */
export function EditeurEquivalencesScolarite() {
  const [liste, setListe] = useState<Equivalence[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    formation: 'IFSI', annee: '1', profession: 'AS', base: '',
  });

  const charger = async () => {
    setLoading(true);
    const { data, error } = await (supabase as any).from('equivalences_scolarite')
      .select('id, formation, libelle_formation, annee_validee_min, profession_autorisee, base_reglementaire, actif')
      .order('formation', { ascending: true })
      .order('annee_validee_min', { ascending: true });
    if (error) toast.error(error.message);
    setListe((data || []) as Equivalence[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const ajouter = async () => {
    const annee = parseInt(form.annee, 10);
    if (!form.formation || !form.profession || !Number.isFinite(annee) || annee < 1) {
      toast.error('Formation, année (≥ 1) et profession sont requises.');
      return;
    }
    const libelle = FORMATION_OPTIONS.find((f) => f.valeur === form.formation)?.label || form.formation;
    setSaving(true);
    const { error } = await (supabase as any).from('equivalences_scolarite').insert({
      formation: form.formation,
      libelle_formation: libelle,
      annee_validee_min: annee,
      profession_autorisee: form.profession,
      base_reglementaire: form.base.trim() || null,
    });
    setSaving(false);
    if (error) { toast.error(error.message.includes('duplicate') ? 'Cette règle existe déjà.' : error.message); return; }
    toast.success('Règle ajoutée.');
    setForm({ ...form, base: '' });
    charger();
  };

  const basculerActif = async (e: Equivalence) => {
    const { error } = await (supabase as any).from('equivalences_scolarite')
      .update({ actif: !e.actif }).eq('id', e.id);
    if (error) { toast.error(error.message); return; }
    charger();
  };

  const supprimer = async (id: string) => {
    const { error } = await (supabase as any).from('equivalences_scolarite').delete().eq('id', id);
    if (error) { toast.error(error.message); return; }
    toast.success('Règle supprimée.');
    charger();
  };

  return (
    <section className="card-base">
      <div className="flex items-center gap-2 mb-1">
        <GraduationCap className="h-5 w-5 text-primary" />
        <h2 className="text-base font-semibold text-foreground">Équivalences étudiant « faisant fonction »</h2>
      </div>
      <p className="text-xs text-muted-foreground mb-4">
        Règle = une formation + une année validée autorise l'exercice d'une profession. Appliquée à l'inscription (suggestion)
        et confirmée par l'attestation de scolarité vérifiée IA. Conforme à l'arrêté du 3 février 2022.
      </p>

      {loading ? (
        <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Chargement…</div>
      ) : (
        <div className="space-y-2 mb-4">
          {liste.length === 0 && <p className="text-sm text-muted-foreground">Aucune règle.</p>}
          {liste.map((e) => (
            <div key={e.id} className={`flex items-center justify-between gap-3 rounded-lg border p-2.5 ${e.actif ? 'border-input' : 'border-input opacity-60'}`}>
              <div className="min-w-0">
                <p className="text-sm font-medium text-foreground">
                  {e.libelle_formation} · année {e.annee_validee_min} validée → <span className="text-primary">{getLabelProfession(e.profession_autorisee)}</span>
                </p>
                {e.base_reglementaire && <p className="text-[11px] text-muted-foreground truncate">{e.base_reglementaire}</p>}
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <button type="button" onClick={() => basculerActif(e)}
                  className={`text-[11px] px-2 py-1 rounded-full ${e.actif ? 'bg-emerald-100 text-emerald-700' : 'bg-muted text-muted-foreground'}`}>
                  {e.actif ? 'Active' : 'Inactive'}
                </button>
                <button type="button" onClick={() => supprimer(e.id)} aria-label="Supprimer" className="text-destructive hover:bg-destructive/10 rounded p-1">
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="border-t border-input pt-3">
        <p className="text-xs font-semibold text-foreground mb-2">Ajouter une règle</p>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          <select value={form.formation} onChange={(e) => setForm({ ...form, formation: e.target.value })} className="input-base text-sm" aria-label="Formation">
            {FORMATION_OPTIONS.map((f) => <option key={f.valeur} value={f.valeur}>{f.label}</option>)}
          </select>
          <input value={form.annee} onChange={(e) => setForm({ ...form, annee: e.target.value.replace(/\D/g, '').slice(0, 1) })}
            inputMode="numeric" placeholder="Année validée" className="input-base text-sm" aria-label="Année validée" />
          <select value={form.profession} onChange={(e) => setForm({ ...form, profession: e.target.value })} className="input-base text-sm" aria-label="Profession autorisée">
            {PROFESSIONS.map((p) => <option key={p.valeur} value={p.valeur}>{p.label}</option>)}
          </select>
          <button type="button" onClick={ajouter} disabled={saving}
            className="btn-primary text-sm inline-flex items-center justify-center gap-1.5 disabled:opacity-50">
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />} Ajouter
          </button>
        </div>
        <input value={form.base} onChange={(e) => setForm({ ...form, base: e.target.value })}
          placeholder="Base réglementaire (optionnel, ex : Arrêté du 3 février 2022)" className="input-base text-sm mt-2" aria-label="Base réglementaire" />
      </div>
    </section>
  );
}
