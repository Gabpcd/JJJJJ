import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { Key, Copy, Plus, Eye, EyeOff, Code2, CheckCircle, Ban, Trash2 } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { logger } from '@/lib/logger';
import { toast } from 'sonner';
import { SUPABASE_URL } from '@/integrations/supabase/client';

const SUPABASE_FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;

const ENDPOINTS = [
  { method: 'GET', path: '/api-v1/missions', desc: 'Lister les missions de l\'établissement', example: '{ "missions": [{ "id": "uuid", "intitule": "IDE Nuit", "debut_le": "2026-03-15T20:00:00Z", "statut": "OUVERTE" }], "count": 1 }' },
  { method: 'POST', path: '/api-v1/missions', desc: 'Créer une nouvelle mission', example: '{ "mission": { "id": "uuid", "intitule": "IDE Jour", "statut": "OUVERTE" } }' },
  { method: 'GET', path: '/api-v1/presences', desc: 'Lister les pointages validés', example: '{ "presences": [{ "id": "uuid", "mission_id": "uuid", "pointage_arrivee_le": "2026-03-15T07:00:00Z", "validee_par_etablissement": true }], "count": 1 }' },
  { method: 'GET', path: '/api-v1/factures', desc: 'Lister les factures émises', example: '{ "factures": [{ "id": "uuid", "numero_facture": "SD-2026-001", "montant_ttc": 150.00, "statut": "PAYEE" }], "count": 1 }' },
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

  const [generatedSecret, setGeneratedSecret] = useState<string | null>(null);

  const genererCle = async () => {
    if (!newName.trim() || generating) return;
    setGenerating(true);
    try {
      const { data, error } = await supabase.rpc('fn_creer_api_key' as any, {
        p_nom: newName.trim(),
        p_permissions: newPerms,
        p_etablissement_id: null,
      });
      if (error || (data as any)?.error) {
        logger.error('Erreur génération clé API:', error || data);
        toast.error((data as any)?.error || 'Erreur lors de la génération de la clé API.');
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
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur lors de la révocation.');
      return;
    }
    toast.success('Clé révoquée');
    charger();
  };

  const supprimer = async (id: string) => {
    if (!confirm('Supprimer définitivement cette clé API ? Action irréversible.')) return;
    const { data, error } = await supabase.rpc('fn_supprimer_api_key' as any, { p_id: id });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur lors de la suppression.');
      return;
    }
    toast.success('Clé supprimée');
    charger();
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
    return cle.slice(0, 8) + '••••••••••••••••';
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Code2 className="h-6 w-6 text-primary" /> API REST Jolene v1
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Documentation et gestion des clés d'accès</p>
        </div>
      </div>

      {/* Documentation */}
      <CardY2K hoverLift={false} className="mb-6">
        <h2 className="font-bold text-foreground mb-4">Endpoints disponibles</h2>
        <p className="text-xs text-muted-foreground mb-4">Base URL : <code className="bg-muted px-2 py-0.5 rounded text-foreground">{SUPABASE_FUNCTIONS_URL}</code></p>
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
      </CardY2K>

      {/* API Keys */}
      <CardY2K hoverLift={false}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-bold text-foreground flex items-center gap-2">
            <Key className="h-5 w-5 text-primary" /> Clés API
          </h2>
          <BoutonY2K variant="primary" size="sm" onClick={() => { setShowModal(true); setGeneratedKey(null); }} iconeGauche={<Plus className="h-3.5 w-3.5" />}>
            Générer une clé
          </BoutonY2K>
        </div>

        {keys.length > 0 ? (
          <>
            {/* Desktop table */}
            <div className="hidden md:block overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-muted-foreground">
                    <th className="pb-2 font-medium">Nom</th>
                    <th className="pb-2 font-medium">Clé API</th>
                    <th className="pb-2 font-medium">Permissions</th>
                    <th className="pb-2 font-medium">Dernière utilisation</th>
                    <th className="pb-2 font-medium">Statut</th>
                    <th className="pb-2 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {keys.map(k => (
                    <tr key={k.id} className="border-b border-border/50">
                      <td className="py-3 font-medium text-foreground">{k.nom}</td>
                      <td className="py-3">
                        <div className="flex items-center gap-1">
                          <code className="text-xs bg-muted px-2 py-0.5 rounded">{masquer(k.cle_api, revealedKeys.has(k.id))}</code>
                          <button onClick={() => toggleReveal(k.id)} className="p-1 hover:bg-muted rounded min-w-[44px] min-h-[44px] flex items-center justify-center" aria-label={revealedKeys.has(k.id) ? 'Masquer la clé API' : 'Afficher la clé API'}>
                            {revealedKeys.has(k.id) ? <EyeOff className="h-3.5 w-3.5 text-muted-foreground" /> : <Eye className="h-3.5 w-3.5 text-muted-foreground" />}
                          </button>
                          <button onClick={() => copier(k.cle_api)} className="p-1 hover:bg-muted rounded min-w-[44px] min-h-[44px] flex items-center justify-center" aria-label="Copier la clé API">
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
                        <BadgeY2K variant={k.actif ? 'success' : 'error'} size="sm">
                          {k.actif ? 'Active' : 'Désactivée'}
                        </BadgeY2K>
                      </td>
                      <td className="py-3">
                        <div className="flex items-center gap-1">
                          {k.actif && (
                            <button
                              onClick={() => revoquer(k.id)}
                              className="p-1.5 hover:bg-warning/10 rounded text-warning min-w-[32px] min-h-[32px] flex items-center justify-center"
                              aria-label="Révoquer la clé"
                              title="Révoquer (désactiver)"
                            >
                              <Ban className="h-3.5 w-3.5" />
                            </button>
                          )}
                          <button
                            onClick={() => supprimer(k.id)}
                            className="p-1.5 hover:bg-destructive/10 rounded text-destructive min-w-[32px] min-h-[32px] flex items-center justify-center"
                            aria-label="Supprimer la clé"
                            title="Supprimer définitivement"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile cards */}
            <div className="md:hidden space-y-3">
              {keys.map(k => (
                <CardY2K key={k.id} hoverLift={false} className="space-y-3">
                  <div className="flex items-start justify-between gap-2">
                    <p className="font-semibold text-foreground">{k.nom}</p>
                    <BadgeY2K variant={k.actif ? 'success' : 'error'} size="sm">
                      {k.actif ? 'Active' : 'Désactivée'}
                    </BadgeY2K>
                  </div>
                  <div className="space-y-1.5 text-xs">
                    <div>
                      <p className="text-muted-foreground mb-1">Clé API</p>
                      <div className="flex items-center gap-1">
                        <code className="text-xs bg-muted px-2 py-0.5 rounded flex-1 truncate">{masquer(k.cle_api, revealedKeys.has(k.id))}</code>
                        <button onClick={() => toggleReveal(k.id)} className="p-1 hover:bg-muted rounded min-w-[36px] min-h-[36px] flex items-center justify-center" aria-label={revealedKeys.has(k.id) ? 'Masquer la clé API' : 'Afficher la clé API'}>
                          {revealedKeys.has(k.id) ? <EyeOff className="h-3.5 w-3.5 text-muted-foreground" /> : <Eye className="h-3.5 w-3.5 text-muted-foreground" />}
                        </button>
                        <button onClick={() => copier(k.cle_api)} className="p-1 hover:bg-muted rounded min-w-[36px] min-h-[36px] flex items-center justify-center" aria-label="Copier la clé API">
                          <Copy className="h-3.5 w-3.5 text-muted-foreground" />
                        </button>
                      </div>
                    </div>
                    <div>
                      <p className="text-muted-foreground mb-1">Permissions</p>
                      <div className="flex flex-wrap gap-1">
                        {(k.permissions ?? []).map((p: string) => (
                          <span key={p} className="badge-base bg-muted text-muted-foreground text-[10px]">{p}</span>
                        ))}
                      </div>
                    </div>
                    <p className="text-muted-foreground">
                      Dernière utilisation : {k.derniere_utilisation ? format(new Date(k.derniere_utilisation), 'dd/MM/yyyy HH:mm', { locale: fr }) : 'Jamais'}
                    </p>
                  </div>
                  <div className="flex items-center gap-2 pt-1 border-t border-border/50">
                    {k.actif && (
                      <BoutonY2K variant="ghost" size="sm" onClick={() => revoquer(k.id)} aria-label="Révoquer la clé" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                        Révoquer
                      </BoutonY2K>
                    )}
                    <BoutonY2K variant="destructive" size="sm" onClick={() => supprimer(k.id)} aria-label="Supprimer la clé" iconeGauche={<Trash2 className="h-3.5 w-3.5" />}>
                      Supprimer
                    </BoutonY2K>
                  </div>
                </CardY2K>
              ))}
            </div>
          </>
        ) : (
          <p className="text-sm text-muted-foreground text-center py-6">Aucune clé API générée.</p>
        )}
      </CardY2K>

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
                <p className="text-xs text-muted-foreground mb-2">Copiez ces informations <strong>maintenant</strong>. Le secret ne sera plus jamais affiché.</p>
                <p className="text-[11px] text-muted-foreground mb-1 mt-3 font-semibold">Clé API (publique)</p>
                <div className="flex items-center gap-2 bg-muted rounded-lg p-3 mb-3">
                  <code className="text-xs flex-1 break-all">{generatedKey}</code>
                  <button onClick={() => copier(generatedKey)} className="p-1 hover:bg-background rounded" aria-label="Copier la clé API">
                    <Copy className="h-4 w-4 text-primary" />
                  </button>
                </div>
                {generatedSecret && (
                  <>
                    <p className="text-[11px] text-muted-foreground mb-1 mt-3 font-semibold">Clé secrète (à conserver)</p>
                    <div className="flex items-center gap-2 bg-destructive/5 border border-destructive/20 rounded-lg p-3 mb-4">
                      <code className="text-xs flex-1 break-all">{generatedSecret}</code>
                      <button onClick={() => copier(generatedSecret)} className="p-1 hover:bg-background rounded" aria-label="Copier la clé secrète">
                        <Copy className="h-4 w-4 text-primary" />
                      </button>
                    </div>
                  </>
                )}
                <BoutonY2K variant="primary" size="md" onClick={() => { setShowModal(false); setGeneratedSecret(null); }} className="w-full">Fermer</BoutonY2K>
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
                  <BoutonY2K variant="primary" size="md" onClick={genererCle} disabled={!newName.trim() || generating} loading={generating} className="flex-1">{generating ? 'Génération…' : 'Générer'}</BoutonY2K>
                  <BoutonY2K variant="secondary" size="md" onClick={() => setShowModal(false)} className="flex-1">Annuler</BoutonY2K>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </LayoutAdmin>
  );
}
