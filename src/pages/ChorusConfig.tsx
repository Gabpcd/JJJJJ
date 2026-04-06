import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { Landmark, Loader2, Save, CheckCircle, ExternalLink, Edit2 } from 'lucide-react';
import { FadeInView } from '@/components/FadeInView';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { capturerErreurSentry } from '@/lib/sentry';

export default function ChorusConfig() {
  usePageTitle('Configuration Chorus Pro');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [configId, setConfigId] = useState<string | null>(null);
  const [editMode, setEditMode] = useState(false);
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
      const payload = {
        etablissement_id: user.id,
        numero_structure: numeroStructure.trim(),
        code_service: codeService.trim() || null,
        identifiant_cpro: identifiantCpro.trim() || null,
        actif,
      } as any;

      if (configId) {
        const { error } = await supabase
          .from('chorus_pro_config')
          .update(payload)
          .eq('id', configId);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('chorus_pro_config')
          .insert(payload);
        if (error) throw error;
      }

      afficherNotification({ type: 'succes', message: 'Configuration Chorus Pro enregistrée' });
      setEditMode(false);

      const { data } = await supabase
        .from('chorus_pro_config')
        .select('*')
        .eq('etablissement_id', user.id)
        .maybeSingle();
      if (data) setConfigId(data.id);
    } catch (err: any) {
      capturerErreurSentry(err, 'ChorusConfig', 'sauvegarder');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la sauvegarde.' });
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

  const isReadOnly = !!configId && !editMode;

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
            {configId && !editMode && (
              <div className="flex items-center justify-between p-3 rounded-lg bg-success/10 border border-success/20">
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-success" />
                  <span className="text-sm text-success font-medium">Configuration active</span>
                </div>
                <Button size="sm" variant="ghost" onClick={() => setEditMode(true)} className="text-xs gap-1">
                  <Edit2 className="h-3 w-3" /> Modifier
                </Button>
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
                disabled={isReadOnly}
              />
              <p className="text-xs text-muted-foreground mt-1">Identifiant unique de votre structure sur Chorus Pro (SIRET ou n° structure).</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Code service</label>
              <Input
                value={codeService}
                onChange={e => setCodeService(e.target.value)}
                placeholder="Ex: SRV001"
                disabled={isReadOnly}
              />
              <p className="text-xs text-muted-foreground mt-1">Code du service destinataire (facultatif).</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">Identifiant CPro</label>
              <Input
                value={identifiantCpro}
                onChange={e => setIdentifiantCpro(e.target.value)}
                placeholder="Votre identifiant de connexion"
                disabled={isReadOnly}
              />
              <p className="text-xs text-muted-foreground mt-1">Identifiant de connexion à la plateforme Chorus Pro.</p>
            </div>

            {!isReadOnly && (
              <div className="flex gap-2">
                <Button onClick={sauvegarder} disabled={saving || !numeroStructure.trim()} className="flex-1 gap-2">
                  {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                  Enregistrer
                </Button>
                {editMode && (
                  <Button variant="ghost" onClick={() => setEditMode(false)}>Annuler</Button>
                )}
              </div>
            )}

            <div className="rounded-lg border border-border p-3 space-y-2">
              <p className="text-xs font-semibold text-foreground">Comment déposer vos factures ?</p>
              <p className="text-xs text-muted-foreground">
                En attendant l'intégration API directe, déposez vos factures manuellement sur le portail Chorus Pro.
                Un guide pas-à-pas est disponible dans chaque facture secteur public.
              </p>
              <a href="https://chorus-pro.gouv.fr" target="_blank" rel="noopener noreferrer">
                <Button size="sm" variant="outline" className="text-xs gap-1 mt-1">
                  <ExternalLink className="h-3 w-3" /> Accéder à Chorus Pro
                </Button>
              </a>
            </div>

            <div className="p-3 rounded-lg bg-primary/5 border border-primary/20">
              <p className="text-xs text-primary">
                <strong>Intégration API en cours</strong> — Lorsque l'API Chorus Pro sera connectée,
                vos factures seront déposées et suivies automatiquement depuis Jolene.
              </p>
            </div>
          </div>
        </div>
      </FadeInView>
    </LayoutApp>
  );
}
