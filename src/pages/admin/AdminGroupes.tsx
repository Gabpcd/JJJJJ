import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Building2, Palette, Globe, Save, Loader2, HeartPulse } from 'lucide-react';

export default function AdminGroupes() {
  usePageTitle('White Label — Groupes');
  const [groupes, setGroupes] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState<any>({});
  const [saving, setSaving] = useState(false);

  const charger = async () => {
    const { data } = await supabase.from('groupes_sante').select('*').is('supprime_le', null).order('nom');
    setGroupes(data ?? []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const editer = (g: any) => {
    setEditingId(g.id);
    setForm({
      nom_marque: g.nom_marque || '',
      couleur_primaire: g.couleur_primaire || '#17A2B8',
      couleur_secondaire: g.couleur_secondaire || '#0F172A',
      domaine_custom: g.domaine_custom || '',
      logo_url: g.logo_url || '',
    });
  };

  const sauvegarder = async () => {
    if (!editingId) return;
    setSaving(true);
    await supabase.from('groupes_sante').update({
      nom_marque: form.nom_marque || null,
      couleur_primaire: form.couleur_primaire,
      couleur_secondaire: form.couleur_secondaire,
      domaine_custom: form.domaine_custom || null,
      logo_url: form.logo_url || null,
    }).eq('id', editingId);
    setSaving(false);
    setEditingId(null);
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <h1 className="text-2xl font-bold text-foreground flex items-center gap-2 mb-6">
        <Building2 className="h-6 w-6 text-primary" /> White Label — Groupes de santé
      </h1>

      <div className="space-y-4">
        {groupes.map(g => (
          <div key={g.id} className="card-base">
            <div className="flex items-center justify-between mb-3">
              <div>
                <h3 className="font-bold text-foreground">{g.nom}</h3>
                <p className="text-xs text-muted-foreground">{g.siren ? `SIREN: ${g.siren}` : ''} {g.formule_abonnement && `· ${g.formule_abonnement}`}</p>
              </div>
              {editingId !== g.id && (
                <button onClick={() => editer(g)} className="btn-secondary text-xs flex items-center gap-1">
                  <Palette className="h-3.5 w-3.5" /> Personnaliser
                </button>
              )}
            </div>

            {/* Current branding preview */}
            {editingId !== g.id && (g.nom_marque || g.domaine_custom) && (
              <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
                {g.nom_marque && <span className="badge-base bg-muted">Marque: {g.nom_marque}</span>}
                {g.domaine_custom && <span className="badge-base bg-muted"><Globe className="h-3 w-3 inline mr-1" />{g.domaine_custom}</span>}
                {g.couleur_primaire && (
                  <span className="badge-base bg-muted flex items-center gap-1">
                    <span className="w-3 h-3 rounded-full inline-block" style={{ backgroundColor: g.couleur_primaire }} />
                    {g.couleur_primaire}
                  </span>
                )}
              </div>
            )}

            {/* Edit form */}
            {editingId === g.id && (
              <div className="space-y-4 mt-4 border-t border-border pt-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-foreground mb-1">Nom de marque</label>
                    <input value={form.nom_marque} onChange={e => setForm({ ...form, nom_marque: e.target.value })} className="input-base w-full" placeholder="Ex: Leader Santé Connect" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-foreground mb-1">Domaine custom</label>
                    <input value={form.domaine_custom} onChange={e => setForm({ ...form, domaine_custom: e.target.value })} className="input-base w-full" placeholder="staffing.leadersante.fr" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-foreground mb-1">URL du logo</label>
                    <input value={form.logo_url} onChange={e => setForm({ ...form, logo_url: e.target.value })} className="input-base w-full" placeholder="https://..." />
                  </div>
                  <div className="flex gap-4">
                    <div className="flex-1">
                      <label className="block text-sm font-medium text-foreground mb-1">Couleur primaire</label>
                      <div className="flex items-center gap-2">
                        <input type="color" value={form.couleur_primaire} onChange={e => setForm({ ...form, couleur_primaire: e.target.value })} className="w-10 h-10 rounded border border-border cursor-pointer" />
                        <input value={form.couleur_primaire} onChange={e => setForm({ ...form, couleur_primaire: e.target.value })} className="input-base flex-1" />
                      </div>
                    </div>
                    <div className="flex-1">
                      <label className="block text-sm font-medium text-foreground mb-1">Couleur secondaire</label>
                      <div className="flex items-center gap-2">
                        <input type="color" value={form.couleur_secondaire} onChange={e => setForm({ ...form, couleur_secondaire: e.target.value })} className="w-10 h-10 rounded border border-border cursor-pointer" />
                        <input value={form.couleur_secondaire} onChange={e => setForm({ ...form, couleur_secondaire: e.target.value })} className="input-base flex-1" />
                      </div>
                    </div>
                  </div>
                </div>

                {/* Live preview */}
                <div className="border border-border rounded-xl overflow-hidden">
                  <p className="text-xs font-medium text-muted-foreground px-3 pt-2">Aperçu en temps réel</p>
                  <div className="p-4" style={{ backgroundColor: form.couleur_secondaire }}>
                    <div className="flex items-center gap-3 mb-3">
                      {form.logo_url ? (
                        <img src={form.logo_url} alt="Logo" className="h-8 w-8 rounded-lg object-contain bg-white/10 p-1" />
                      ) : (
                        <HeartPulse className="h-7 w-7" style={{ color: form.couleur_primaire }} />
                      )}
                      <span className="text-lg font-bold" style={{ color: '#fff' }}>
                        {form.nom_marque || 'Soin Direct'}
                      </span>
                    </div>
                    <div className="flex gap-2">
                      <button className="px-4 py-2 rounded-lg text-white text-sm font-medium" style={{ backgroundColor: form.couleur_primaire }}>
                        Publier une mission
                      </button>
                      <button className="px-4 py-2 rounded-lg text-sm font-medium border" style={{ borderColor: form.couleur_primaire, color: form.couleur_primaire }}>
                        Voir les missions
                      </button>
                    </div>
                  </div>
                </div>

                <div className="flex gap-2">
                  <button onClick={sauvegarder} disabled={saving} className="btn-primary text-sm flex items-center gap-1 disabled:opacity-50">
                    {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                    Enregistrer
                  </button>
                  <button onClick={() => setEditingId(null)} className="btn-secondary text-sm">Annuler</button>
                </div>
              </div>
            )}
          </div>
        ))}

        {groupes.length === 0 && (
          <p className="text-sm text-muted-foreground text-center py-8">Aucun groupe de santé enregistré.</p>
        )}
      </div>
    </LayoutAdmin>
  );
}
