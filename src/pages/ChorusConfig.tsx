import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { Landmark, Loader2, Save, CheckCircle, Edit2, Search, XCircle } from 'lucide-react';
import { FadeInView } from '@/components/FadeInView';
import { Input } from '@/components/ui/input';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { messageErreurEdgeFn } from '@/lib/erreurs';
import { capturerErreurSentry } from '@/lib/sentry';

interface DiagnosticChorus {
  env?: string;
  oauth_ok?: boolean;
  piste_http_status?: number;
}

interface VerifyResult {
  status: 'idle' | 'loading' | 'found' | 'not_found' | 'error';
  designation?: string;
  error?: string;
  codeServiceObligatoire?: boolean;
  services?: Array<{ code: string; nom: string; actif: boolean }>;
  diagnostic?: DiagnosticChorus;
}

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
  const [verify, setVerify] = useState<VerifyResult>({ status: 'idle' });

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

  const verifyStructure = async () => {
    // Chorus attend un identifiant sans espaces (SIRET = 14 chiffres collés).
    // Un SIRET saisi/collé avec des espaces ("818 613 663 00017") rendait la
    // structure systématiquement "introuvable". On normalise avant l'appel et on
    // réaffiche la valeur nettoyée.
    const id = numeroStructure.replace(/\s/g, '');
    if (!id) return;
    if (id !== numeroStructure) setNumeroStructure(id);
    setVerify({ status: 'loading' });
    try {
      const { data, error } = await supabase.functions.invoke('chorus-pro-verify', {
        body: { identifiant: id, detail: true, services: true },
      });
      if (error) throw error;
      if (data.simulation) {
        setVerify({ status: 'error', error: 'Connexion Chorus Pro indisponible : identifiants PISTE non configurés côté serveur.', diagnostic: data.diagnostic });
      } else if (data.apiError) {
        // Erreur technique / habilitation PISTE — surtout PAS "introuvable",
        // qui ferait croire à un mauvais SIRET.
        setVerify({ status: 'error', error: data.error || 'La connexion à Chorus Pro a échoué (habilitation PISTE ou indisponibilité).', diagnostic: data.diagnostic });
      } else if (data.found) {
        setVerify({
          status: 'found',
          designation: data.structure?.designationStructure || 'Structure trouvée',
          codeServiceObligatoire: data.parametrage?.codeServiceObligatoire,
          services: data.services ?? [],
          diagnostic: data.diagnostic,
        });
      } else {
        setVerify({ status: 'not_found', error: data.error || 'Structure introuvable sur Chorus Pro', diagnostic: data.diagnostic });
      }
    } catch (err: any) {
      const msg = await messageErreurEdgeFn(err, 'Erreur lors de la vérification Chorus Pro.');
      setVerify({ status: 'error', error: msg });
    }
  };

  const sauvegarder = async () => {
    if (!user || !numeroStructure.trim()) {
      afficherNotification({ type: 'erreur', message: 'Le numéro de structure est obligatoire.' });
      return;
    }
    if (verify.codeServiceObligatoire && !codeService.trim()) {
      afficherNotification({ type: 'erreur', message: 'Le code service est obligatoire pour cette structure.' });
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
  const activeServices = verify.services?.filter(s => s.actif) ?? [];

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
                <BoutonY2K size="sm" variant="ghost" onClick={() => setEditMode(true)} className="text-xs gap-1">
                  <Edit2 className="h-3 w-3" /> Modifier
                </BoutonY2K>
              </div>
            )}

            {/* Numéro de structure + bouton Vérifier */}
            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">
                Numéro de structure Chorus <span className="text-destructive">*</span>
              </label>
              <div className="flex gap-2">
                <Input
                  value={numeroStructure}
                  onChange={e => { setNumeroStructure(e.target.value); setVerify({ status: 'idle' }); }}
                  placeholder="Ex: 10000071800067"
                  disabled={isReadOnly}
                  className="flex-1"
                />
                {!isReadOnly && (
                  <BoutonY2K
                    type="button"
                    variant="secondary"
                    size="sm"
                    onClick={verifyStructure}
                    disabled={verify.status === 'loading' || !numeroStructure.trim()}
                    className="shrink-0"
                  >
                    {verify.status === 'loading'
                      ? <Loader2 className="h-4 w-4 animate-spin" />
                      : <Search className="h-4 w-4" />
                    }
                    <span className="ml-1.5">Vérifier</span>
                  </BoutonY2K>
                )}
              </div>
              {verify.status === 'found' && (
                <p className="text-xs text-success flex items-center gap-1 mt-1.5">
                  <CheckCircle className="h-3.5 w-3.5" />
                  {verify.designation}
                </p>
              )}
              {verify.status === 'not_found' && (
                <p className="text-xs text-destructive flex items-center gap-1 mt-1.5">
                  <XCircle className="h-3.5 w-3.5" />
                  {verify.error}
                </p>
              )}
              {verify.status === 'error' && (
                <p className="text-xs text-warning flex items-center gap-1 mt-1.5">
                  <XCircle className="h-3.5 w-3.5" />
                  {verify.error}
                </p>
              )}
              {verify.status === 'idle' && (
                <p className="text-xs text-muted-foreground mt-1">
                  SIRET (14 chiffres, sans espaces) ou n° de structure du <strong>client du secteur public</strong> que vous facturez. Seuls les organismes publics sont enregistrés sur Chorus Pro.
                </p>
              )}
              {verify.diagnostic && (verify.status === 'not_found' || verify.status === 'error' || verify.status === 'found') && (
                <p className="text-[11px] text-muted-foreground mt-1 font-mono">
                  diagnostic : env={verify.diagnostic.env ?? '—'} · OAuth PISTE={verify.diagnostic.oauth_ok ? 'OK' : 'KO'}
                  {verify.diagnostic.piste_http_status != null && <> · Chorus HTTP {verify.diagnostic.piste_http_status}</>}
                </p>
              )}
            </div>

            {/* Code service — select dynamique si services chargés */}
            <div>
              <label className="block text-sm font-medium text-foreground mb-1.5">
                Code service
                {verify.codeServiceObligatoire && (
                  <span className="text-destructive ml-1">* obligatoire pour cette structure</span>
                )}
              </label>
              {activeServices.length > 0 ? (
                <select
                  value={codeService}
                  onChange={e => setCodeService(e.target.value)}
                  disabled={isReadOnly}
                  className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <option value="">— Aucun —</option>
                  {activeServices.map(s => (
                    <option key={s.code} value={s.code}>{s.code} — {s.nom}</option>
                  ))}
                </select>
              ) : (
                <Input
                  value={codeService}
                  onChange={e => setCodeService(e.target.value)}
                  placeholder="Ex: SRV001"
                  disabled={isReadOnly}
                />
              )}
              <p className="text-xs text-muted-foreground mt-1">
                {activeServices.length > 0
                  ? `${activeServices.length} service(s) disponible(s) — sélectionnez dans la liste`
                  : 'Code du service destinataire (cliquez "Vérifier" pour charger la liste).'
                }
              </p>
            </div>

            {/* Identifiant CPro */}
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

            {/* Actions */}
            {!isReadOnly && (
              <div className="flex gap-2">
                <BoutonY2K onClick={sauvegarder} disabled={saving || !numeroStructure.trim()} className="flex-1 gap-2">
                  {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                  Enregistrer
                </BoutonY2K>
                {editMode && (
                  <BoutonY2K variant="ghost" onClick={() => setEditMode(false)}>Annuler</BoutonY2K>
                )}
              </div>
            )}

            {configId || verify.status === 'found' ? (
              <div className="p-3 rounded-lg bg-success/5 border border-success/20">
                <p className="text-xs text-success">
                  <strong>Intégration Chorus Pro configurée</strong> — vos factures secteur public
                  seront déposées et suivies automatiquement via l'API Chorus Pro (PISTE), avec une
                  synchronisation du statut toutes les 2 heures.
                </p>
              </div>
            ) : (
              <div className="p-3 rounded-lg bg-muted/50 border border-border">
                <p className="text-xs text-muted-foreground">
                  L'intégration Chorus Pro (API PISTE) est <strong>disponible pour facturer vos clients
                  du secteur public</strong>. Renseignez le n° de structure du client public, cliquez
                  « Vérifier », puis enregistrez. Le dépôt et le suivi des factures deviennent alors
                  automatiques.
                </p>
              </div>
            )}
          </div>
        </div>
      </FadeInView>
    </LayoutApp>
  );
}
