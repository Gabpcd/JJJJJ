import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Key, Copy, Plus, Eye, EyeOff, Code2, CheckCircle, Ban, Trash2 } from 'lucide-react';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

const ENDPOINTS = [
  { method: 'GET', path: '/api-v1/missions', desc: 'Lister vos missions', example: '{ "missions": [{ "id": "uuid", "intitule": "IDE Nuit", "statut": "OUVERTE" }], "count": 1 }' },
  { method: 'POST', path: '/api-v1/missions', desc: 'Créer une mission (permission missions:write)', example: '{ "mission": { "id": "uuid", "intitule": "IDE Jour" } }' },
  { method: 'GET', path: '/api-v1/presences', desc: 'Lister les pointages', example: '{ "presences": [{ "id": "uuid", "validee": true }], "count": 1 }' },
  { method: 'GET', path: '/api-v1/factures', desc: 'Lister les factures', example: '{ "factures": [{ "numero_facture": "SD-2026-001", "montant_ttc": 150.00 }], "count": 1 }' },
];

const PERMISSIONS = [
  { value: 'missions:read', label: 'Lire les missions' },
  { value: 'missions:write', label: 'Créer/modifier des missions' },
  { value: 'presences:read', label: 'Lire les pointages' },
  { value: 'factures:read', label: 'Lire les factures' },
];

const METHOD_COLORS: Record<string, string> = {
  GET: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  POST: 'bg-primary/10 text-primary',
};

export default function APIEtablissement() {
  usePageTitle('API');
  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <APIContent />
    </LayoutApp>
  );
}

export function APIContent() {
  const { user } = useAuth();
  const [keys, setKeys] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [newName, setNewName] = useState('');
  const [newPerms, setNewPerms] = useState<string[]>(['missions:read']);
  const [generatedKey, setGeneratedKey] = useState<string | null>(null);
  const [revealedKeys, setRevealedKeys] = useState<Set<string>>(new Set());

  const charger = async () => {
    if (!user) return;
    const { data } = await supabase.from('api_keys').select('*').eq('etablissement_id', user.id).order('cree_le', { ascending: false });
    setKeys(data ?? []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const [generatedSecret, setGeneratedSecret] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);

  const genererCle = async () => {
    if (!newName.trim() || !user || generating) return;
    setGenerating(true);
    try {
      const { data, error } = await supabase.rpc('fn_creer_api_key' as any, {
        p_nom: newName.trim(),
        p_permissions: newPerms,
        p_etablissement_id: user.id,
      });
      if (error || (data as any)?.error) {
        toast.error((data as any)?.error || 'Erreur lors de la génération de la clé.');
        return;
      }
      const result = data as any;
      setGeneratedKey(result.cle_api);
      setGeneratedSecret(result.cle_secret);
      setNewName('');
      setNewPerms(['missions:read']);
      charger();
    } finally {
      setGenerating(false);
    }
  };

  const revoquer = async (id: string) => {
    if (!confirm('Révoquer cette clé API ? Elle ne sera plus utilisable.')) return;
    const { data, error } = await supabase.rpc('fn_revoquer_api_key' as any, { p_id: id });
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur'); return; }
    toast.success('Clé révoquée');
    charger();
  };

  const supprimer = async (id: string) => {
    if (!confirm('Supprimer définitivement cette clé API ? Action irréversible.')) return;
    const { data, error } = await supabase.rpc('fn_supprimer_api_key' as any, { p_id: id });
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur'); return; }
    toast.success('Clé supprimée');
    charger();
  };

  const copier = (text: string) => { navigator.clipboard.writeText(text); };
  const toggleReveal = (id: string) => {
    setRevealedKeys(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });
  };
  const masquer = (cle: string, revealed: boolean) => revealed ? cle : cle.slice(0, 12) + '••••••••••••';

  if (loading) return <ChargementPage />;

  return (
    <>
      <h2 className="text-lg font-bold text-foreground flex items-center gap-2 mb-1">
        <Code2 className="h-5 w-5 text-primary" /> API REST Jolene
      </h2>
      <p className="text-sm text-muted-foreground mb-6">Intégrez vos outils RH avec notre API</p>

      {/* Doc */}
      <div className="card-base mb-6">
        <h2 className="font-bold text-foreground mb-3">📖 Endpoints</h2>
        <p className="text-xs text-muted-foreground mb-1">Base URL : <code className="bg-muted px-2 py-0.5 rounded text-foreground">https://flripxtsyegjshnhzjkz.supabase.co/functions/v1</code></p>
        <p className="text-xs text-muted-foreground mb-3">Authentification : header <code className="bg-muted px-2 py-0.5 rounded text-foreground">x-api-key: sd_live_…</code> (votre clé ci-dessous).</p>
        <div className="space-y-3">
          {ENDPOINTS.map((ep, i) => (
            <div key={i} className="border border-border rounded-lg p-3">
              <div className="flex items-center gap-2 mb-1">
                <span className={`px-2 py-0.5 rounded text-xs font-bold ${METHOD_COLORS[ep.method]}`}>{ep.method}</span>
                <code className="text-sm font-mono text-foreground">{ep.path}</code>
              </div>
              <p className="text-xs text-muted-foreground">{ep.desc}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Keys */}
      <div className="card-base">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold text-foreground flex items-center gap-2"><Key className="h-5 w-5 text-primary" /> Mes clés API</h2>
          <button onClick={() => { setShowModal(true); setGeneratedKey(null); }} className="btn-primary text-xs flex items-center gap-1"><Plus className="h-3.5 w-3.5" /> Générer</button>
        </div>

        {keys.length > 0 ? (
          <div className="space-y-3">
            {keys.map(k => (
              <div key={k.id} className="border border-border rounded-lg p-3">
                <div className="flex items-center justify-between mb-1">
                  <span className="font-medium text-foreground text-sm">{k.nom}</span>
                  <span className={`badge-base text-[10px] ${k.actif ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' : 'bg-destructive/10 text-destructive'}`}>
                    {k.actif ? 'Active' : 'Désactivée'}
                  </span>
                </div>
                <div className="flex items-center gap-1 mb-1">
                  <code className="text-xs bg-muted px-2 py-0.5 rounded">{masquer(k.cle_api, revealedKeys.has(k.id))}</code>
                  <button onClick={() => toggleReveal(k.id)} className="p-1 hover:bg-muted rounded" aria-label={revealedKeys.has(k.id) ? 'Masquer' : 'Afficher'}>
                    {revealedKeys.has(k.id) ? <EyeOff className="h-3.5 w-3.5 text-muted-foreground" /> : <Eye className="h-3.5 w-3.5 text-muted-foreground" />}
                  </button>
                  <button onClick={() => copier(k.cle_api)} className="p-1 hover:bg-muted rounded" aria-label="Copier"><Copy className="h-3.5 w-3.5 text-muted-foreground" /></button>
                  {k.actif && (
                    <button onClick={() => revoquer(k.id)} className="p-1 hover:bg-warning/10 text-warning rounded ml-auto" aria-label="Révoquer" title="Révoquer">
                      <Ban className="h-3.5 w-3.5" />
                    </button>
                  )}
                  <button onClick={() => supprimer(k.id)} className={`p-1 hover:bg-destructive/10 text-destructive rounded ${k.actif ? '' : 'ml-auto'}`} aria-label="Supprimer" title="Supprimer">
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
                <div className="flex flex-wrap gap-1">
                  {(k.permissions ?? []).map((p: string) => <span key={p} className="badge-base bg-muted text-muted-foreground text-[10px]">{p}</span>)}
                </div>
                <p className="text-[10px] text-muted-foreground mt-1">
                  Dernière utilisation : {k.derniere_utilisation ? format(new Date(k.derniere_utilisation), 'dd/MM/yyyy', { locale: fr }) : 'Jamais'}
                </p>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground text-center py-6">Aucune clé API. Générez-en une pour commencer.</p>
        )}
      </div>

      {/* Modal */}
      <DialogResponsive open={showModal} onOpenChange={setShowModal}>
        <DialogResponsiveContent>
          <DialogResponsiveBody>
          {generatedKey ? (
            <>
              <div className="flex items-center gap-2 mb-4"><CheckCircle className="h-5 w-5 text-success" /><h3 className="font-bold text-foreground">Clé générée !</h3></div>
              <p className="text-xs text-muted-foreground mb-2">⚠️ Copiez ces informations <strong>maintenant</strong>. Le secret ne sera plus jamais affiché.</p>
              <p className="text-[11px] text-muted-foreground mb-1 mt-3 font-semibold">Clé API (publique)</p>
              <div className="flex items-center gap-2 bg-muted rounded-lg p-3 mb-3">
                <code className="text-xs flex-1 break-all">{generatedKey}</code>
                <button onClick={() => copier(generatedKey)} className="p-1 hover:bg-background rounded" aria-label="Copier la clé API"><Copy className="h-4 w-4 text-primary" /></button>
              </div>
              {generatedSecret && (
                <>
                  <p className="text-[11px] text-muted-foreground mb-1 mt-3 font-semibold">Clé secrète (à conserver)</p>
                  <div className="flex items-center gap-2 bg-destructive/5 border border-destructive/20 rounded-lg p-3 mb-4">
                    <code className="text-xs flex-1 break-all">{generatedSecret}</code>
                    <button onClick={() => copier(generatedSecret)} className="p-1 hover:bg-background rounded" aria-label="Copier la clé secrète"><Copy className="h-4 w-4 text-primary" /></button>
                  </div>
                </>
              )}
              <button onClick={() => { setShowModal(false); setGeneratedSecret(null); }} className="btn-primary w-full text-sm">Fermer</button>
            </>
          ) : (
            <>
              <h3 className="font-bold text-foreground mb-4">Générer une clé API</h3>
              <label className="block text-sm font-medium text-foreground mb-1">Nom</label>
              <input value={newName} onChange={e => setNewName(e.target.value)} className="input-base w-full mb-4" placeholder="Ex: SIRH Integration" />
              <label className="block text-sm font-medium text-foreground mb-2">Permissions</label>
              <div className="space-y-2 mb-6">
                {PERMISSIONS.map(p => (
                  <label key={p.value} className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={newPerms.includes(p.value)} onChange={e => setNewPerms(prev => e.target.checked ? [...prev, p.value] : prev.filter(x => x !== p.value))} className="rounded border-border" />
                    <span className="text-foreground">{p.label}</span>
                  </label>
                ))}
              </div>
              <div className="flex gap-2">
                <button onClick={genererCle} disabled={!newName.trim() || generating} className="btn-primary flex-1 text-sm disabled:opacity-50">{generating ? 'Génération…' : 'Générer'}</button>
                <button onClick={() => setShowModal(false)} className="btn-secondary flex-1 text-sm">Annuler</button>
              </div>
            </>
          )}
          </DialogResponsiveBody>
        </DialogResponsiveContent>
      </DialogResponsive>
    </>
  );
}
