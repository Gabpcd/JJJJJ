import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Key, Copy, Plus, Eye, EyeOff, Code2, CheckCircle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const ENDPOINTS = [
  { method: 'GET', path: '/api-v1/missions', desc: 'Lister les missions de l\'établissement', example: '{ "data": [{ "id": "uuid", "intitule": "IDE Nuit", "debut_le": "2026-03-15T20:00:00Z", "statut": "OUVERTE" }] }' },
  { method: 'POST', path: '/api-v1/missions', desc: 'Créer une nouvelle mission', example: '{ "data": { "id": "uuid", "intitule": "IDE Jour", "statut": "OUVERTE" } }' },
  { method: 'GET', path: '/api-v1/presences', desc: 'Lister les pointages validés', example: '{ "data": [{ "id": "uuid", "mission_id": "uuid", "heure_arrivee": "07:00", "validee": true }] }' },
  { method: 'GET', path: '/api-v1/factures', desc: 'Lister les factures émises', example: '{ "data": [{ "id": "uuid", "numero_facture": "SD-2026-001", "montant_ttc": 150.00, "statut": "PAYEE" }] }' },
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

export default function AdminAPI() {
  usePageTitle('API REST');
  const [keys, setKeys] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [newName, setNewName] = useState('');
  const [newPerms, setNewPerms] = useState<string[]>(['missions:read']);
  const [generatedKey, setGeneratedKey] = useState<string | null>(null);
  const [revealedKeys, setRevealedKeys] = useState<Set<string>>(new Set());

  const charger = async () => {
    const { data } = await supabase.from('api_keys').select('*').order('cree_le', { ascending: false });
    setKeys(data ?? []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const [generating, setGenerating] = useState(false);

  const genererCle = async () => {
    if (!newName.trim() || generating) return;
    setGenerating(true);
    try {
      const cleApi = `sd_live_${crypto.randomUUID().replace(/-/g, '')}`;
      const cleSecret = crypto.randomUUID();
      const { error } = await supabase.from('api_keys').insert({
        nom: newName.trim(),
        cle_api: cleApi,
        cle_secret: cleSecret,
        permissions: newPerms,
        etablissement_id: null,
        groupe_sante_id: null,
      } as any);
      if (error) {
        console.error('Erreur génération clé API:', error);
        const { toast } = await import('sonner');
        toast.error('Erreur lors de la génération de la clé API.');
      } else {
        setGeneratedKey(cleApi);
        setNewName('');
        setNewPerms(['missions:read']);
        charger();
      }
    } finally {
      setGenerating(false);
    }
  };

  const copier = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const toggleReveal = (id: string) => {
    setRevealedKeys(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const masquer = (cle: string, revealed: boolean) => {
    if (revealed) return cle;
    return cle.slice(0, 12) + '••••••••••••';
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Code2 className="h-6 w-6 text-primary" /> API REST Soin Direct v1
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Documentation et gestion des clés d'accès</p>
        </div>
      </div>

      {/* Documentation */}
      <div className="card-base mb-6">
        <h2 className="font-bold text-foreground mb-4">📖 Endpoints disponibles</h2>
        <p className="text-xs text-muted-foreground mb-4">Base URL : <code className="bg-muted px-2 py-0.5 rounded text-foreground">https://api.soindirect.fr/v1</code></p>
        <div className="space-y-4">
          {ENDPOINTS.map((ep, i) => (
            <div key={i} className="border border-border rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <span className={`px-2 py-0.5 rounded text-xs font-bold ${METHOD_COLORS[ep.method]}`}>{ep.method}</span>
                <code className="text-sm font-mono text-foreground">{ep.path}</code>
              </div>
              <p className="text-sm text-muted-foreground mb-2">{ep.desc}</p>
              <details className="text-xs">
                <summary className="cursor-pointer text-primary hover:underline">Exemple de réponse</summary>
                <pre className="bg-muted rounded p-3 mt-2 overflow-x-auto text-foreground/80">{ep.example}</pre>
              </details>
            </div>
          ))}
        </div>
      </div>

      {/* API Keys */}
      <div className="card-base">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold text-foreground flex items-center gap-2">
            <Key className="h-5 w-5 text-primary" /> Clés API
          </h2>
          <button onClick={() => { setShowModal(true); setGeneratedKey(null); }} className="btn-primary text-xs flex items-center gap-1">
            <Plus className="h-3.5 w-3.5" /> Générer une clé
          </button>
        </div>

        {keys.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-muted-foreground">
                  <th className="pb-2 font-medium">Nom</th>
                  <th className="pb-2 font-medium">Clé API</th>
                  <th className="pb-2 font-medium">Permissions</th>
                  <th className="pb-2 font-medium">Dernière utilisation</th>
                  <th className="pb-2 font-medium">Statut</th>
                </tr>
              </thead>
              <tbody>
                {keys.map(k => (
                  <tr key={k.id} className="border-b border-border/50">
                    <td className="py-3 font-medium text-foreground">{k.nom}</td>
                    <td className="py-3">
                      <div className="flex items-center gap-1">
                        <code className="text-xs bg-muted px-2 py-0.5 rounded">{masquer(k.cle_api, revealedKeys.has(k.id))}</code>
                        <button onClick={() => toggleReveal(k.id)} className="p-1 hover:bg-muted rounded" title="Afficher/Masquer">
                          {revealedKeys.has(k.id) ? <EyeOff className="h-3.5 w-3.5 text-muted-foreground" /> : <Eye className="h-3.5 w-3.5 text-muted-foreground" />}
                        </button>
                        <button onClick={() => copier(k.cle_api)} className="p-1 hover:bg-muted rounded" title="Copier">
                          <Copy className="h-3.5 w-3.5 text-muted-foreground" />
                        </button>
                      </div>
                    </td>
                    <td className="py-3">
                      <div className="flex flex-wrap gap-1">
                        {(k.permissions ?? []).map((p: string) => (
                          <span key={p} className="badge-base bg-muted text-muted-foreground text-[10px]">{p}</span>
                        ))}
                      </div>
                    </td>
                    <td className="py-3 text-xs text-muted-foreground">
                      {k.derniere_utilisation ? format(new Date(k.derniere_utilisation), 'dd/MM/yyyy HH:mm', { locale: fr }) : 'Jamais'}
                    </td>
                    <td className="py-3">
                      <span className={`badge-base text-[10px] ${k.actif ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' : 'bg-destructive/10 text-destructive'}`}>
                        {k.actif ? 'Active' : 'Désactivée'}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground text-center py-6">Aucune clé API générée.</p>
        )}
      </div>

      {/* Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-card rounded-2xl p-6 max-w-md w-full shadow-xl">
            {generatedKey ? (
              <>
                <div className="flex items-center gap-2 mb-4">
                  <CheckCircle className="h-5 w-5 text-success" />
                  <h3 className="font-bold text-foreground">Clé générée !</h3>
                </div>
                <p className="text-xs text-muted-foreground mb-2">Copiez cette clé maintenant, elle ne sera plus affichée en clair.</p>
                <div className="flex items-center gap-2 bg-muted rounded-lg p-3 mb-4">
                  <code className="text-xs flex-1 break-all">{generatedKey}</code>
                  <button onClick={() => copier(generatedKey)} className="p-1 hover:bg-background rounded">
                    <Copy className="h-4 w-4 text-primary" />
                  </button>
                </div>
                <button onClick={() => setShowModal(false)} className="btn-primary w-full text-sm">Fermer</button>
              </>
            ) : (
              <>
                <h3 className="font-bold text-foreground mb-4">Générer une clé API</h3>
                <label className="block text-sm font-medium text-foreground mb-1">Nom de la clé</label>
                <input value={newName} onChange={e => setNewName(e.target.value)} className="input-base w-full mb-4" placeholder="Ex: Integration SIRH" />
                <label className="block text-sm font-medium text-foreground mb-2">Permissions</label>
                <div className="space-y-2 mb-6">
                  {PERMISSIONS.map(p => (
                    <label key={p.value} className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={newPerms.includes(p.value)}
                        onChange={e => {
                          setNewPerms(prev => e.target.checked ? [...prev, p.value] : prev.filter(x => x !== p.value));
                        }}
                        className="rounded border-border"
                      />
                      <span className="text-foreground">{p.label}</span>
                      <code className="text-[10px] text-muted-foreground">{p.value}</code>
                    </label>
                  ))}
                </div>
                <div className="flex gap-2">
                  <button onClick={genererCle} disabled={!newName.trim()} className="btn-primary flex-1 text-sm disabled:opacity-50">Générer</button>
                  <button onClick={() => setShowModal(false)} className="btn-secondary flex-1 text-sm">Annuler</button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </LayoutAdmin>
  );
}
