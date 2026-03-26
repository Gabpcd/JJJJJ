import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { Landmark, Loader2, Save, CheckCircle } from 'lucide-react';
import { FadeInView } from '@/components/FadeInView';
import { Input } from '@/components/ui/input';
import { capturerErreurSentry } from '@/lib/sentry';

export default function ChorusConfig() {
  usePageTitle('Configuration Chorus Pro');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [configId, setConfigId] = useState<string | null>(null);
  const [numeroStructure, setNumeroStructure] = useState('');
  const [codeService, setCodeService] = useState('');
  const [identifiantCpro, setIdentifiantCpro] = useState('');
  const [actif, setActif] = useState(true);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase
        .from('chorus_pro_config')
        .select('*')
        .eq('etablissement_id', user.id)
        .maybeSingle();
      if (data) {
        setConfigId(data.id);
        setNumeroStructure(data.numero_structure ?? '');
        setCodeService(data.code_service ?? '');
        setIdentifiantCpro(data.identifiant_cpro ?? '');
        setActif(data.actif ?? true);
      }
      setLoading(false);
    })();
  }, [user]);

  const sauvegarder = async () => {
    if (!user || !numeroStructure.trim()) {
      afficherNotification({ type: 'erreur', message: 'Le numéro de structure est obligatoire.' });
      return;
    }
    setSaving(true);
    try {
      if (configId) {
        // Update not allowed by RLS — use upsert via insert with conflict
        // Actually RLS blocks UPDATE. We'll delete + re-insert if needed.
        // For now, since UPDATE is blocked by RLS, inform user.
        afficherNotification({ type: 'info', message: 'Configuration déjà enregistrée. Contactez le support pour la modifier.' });
      } else {
        const { error } = await supabase.from('chorus_pro_config').insert({
          etablissement_id: user.id,
          numero_structure: numeroStructure.trim(),
          code_service: codeService.trim() || null,
          identifiant_cpro: identifiantCpro.trim() || null,
          actif,
        } as any);
        if (error) throw error;
        afficherNotification({ type: 'succes', message: '✅ Configuration Chorus Pro enregistrée !' });
        // Reload
        const { data } = await supabase
          .from('chorus_pro_config')
          .select('*')
          .eq('etablissement_id', user.id)
          .maybeSingle();
        if (data) setConfigId(data.id);
      }
    } catch (err: any) {
      capturerErreurSentry(err, 'ChorusConfig', 'sauvegarder');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la sauvegarde. Veuillez réessayer.' });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <FadeInView>
        <div className="max-w-xl mx-auto">
          <div className="flex items-center gap-3 mb-6">
            <div className="p-2.5 rounded-xl bg-primary/10">
              <Landmark className="h-6 w-6 text-primary" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-foreground">Configuration Chorus Pro</h1>
              <p className="text-sm text-muted-foreground">Paramétrez vos identifiants pour la facturation secteur public.</p>
            </div>
          </div>

          <div className="card-base space-y-5">
            {configId && (
              <div className="flex items-center gap-2 p-3 rounded-lg bg-success/10 border border-success/20">
                <CheckCircle className="h-4 w-4 text-success" />
                <span className="text-sm text-success font-medium">Configuration active</span>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">
                Numéro de structure Chorus <span className="text-destructive">*</span>
              </label>
              <Input
                value={numeroStructure}
                onChange={e => setNumeroStructure(e.target.value)}
                placeholder="Ex: 12345678"
                disabled={!!configId}
              />
              <p className="text-xs text-muted-foreground mt-1">Identifiant unique de votre structure sur Chorus Pro.</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Code service</label>
              <Input
                value={codeService}
                onChange={e => setCodeService(e.target.value)}
                placeholder="Ex: SRV001"
                disabled={!!configId}
              />
              <p className="text-xs text-muted-foreground mt-1">Code du service destinataire (facultatif).</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Identifiant CPro</label>
              <Input
                value={identifiantCpro}
                onChange={e => setIdentifiantCpro(e.target.value)}
                placeholder="Votre identifiant de connexion"
                disabled={!!configId}
              />
              <p className="text-xs text-muted-foreground mt-1">Identifiant de connexion à la plateforme Chorus Pro.</p>
            </div>

            {!configId && (
              <button
                onClick={sauvegarder}
                disabled={saving || !numeroStructure.trim()}
                className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                Enregistrer la configuration
              </button>
            )}

            <div className="p-3 rounded-lg bg-muted/50 border border-border">
              <p className="text-xs text-muted-foreground">
                💡 <strong>Mode simulation</strong> : tant qu'aucune clé API Chorus Pro n'est configurée côté serveur, les dépôts sont simulés. Contactez le support pour activer le mode réel.
              </p>
            </div>
          </div>
        </div>
      </FadeInView>
    </LayoutApp>
  );
}
