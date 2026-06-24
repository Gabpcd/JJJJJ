import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { messageErreurEdgeFn } from '@/lib/erreurs';
import { toast } from 'sonner';
import { CheckCircle, XCircle, Search, ChevronDown } from 'lucide-react';

interface ChorusConfig {
  etablissement_id: string;
  numero_structure?: string | null;
  code_service?: string | null;
  identifiant_cpro?: string | null;
  actif?: boolean | null;
}

interface Props {
  etabId: string;
  etabNom: string;
  config: ChorusConfig | null;
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}

interface VerifyResult {
  status: 'idle' | 'loading' | 'found' | 'not_found' | 'error';
  designation?: string;
  error?: string;
  codeServiceObligatoire?: boolean;
  services?: Array<{ code: string; nom: string; actif: boolean }>;
}

export function ChorusConfigEtabDialog({ etabId, etabNom, config, open, onClose, onSaved }: Props) {
  const [numeroStructure, setNumeroStructure] = useState('');
  const [codeService, setCodeService] = useState('');
  const [identifiantCpro, setIdentifiantCpro] = useState('');
  const [actif, setActif] = useState(false);
  const [saving, setSaving] = useState(false);
  const [verify, setVerify] = useState<VerifyResult>({ status: 'idle' });

  useEffect(() => {
    setNumeroStructure(config?.numero_structure ?? '');
    setCodeService(config?.code_service ?? '');
    setIdentifiantCpro(config?.identifiant_cpro ?? '');
    setActif(!!config?.actif);
    setVerify({ status: 'idle' });
  }, [config, open]);

  const verifyStructure = async () => {
    const id = numeroStructure.trim();
    if (!id) { toast.error('Saisissez un numéro de structure'); return; }
    setVerify({ status: 'loading' });
    try {
      const { data, error } = await supabase.functions.invoke('chorus-pro-verify', {
        body: { identifiant: id, detail: true, services: true },
      });
      if (error) throw error;
      if (data.simulation) {
        setVerify({ status: 'error', error: 'Credentials PISTE non configurés' });
      } else if (data.found) {
        setVerify({
          status: 'found',
          designation: data.structure?.designationStructure || 'Structure trouvée',
          codeServiceObligatoire: data.parametrage?.codeServiceObligatoire,
          services: data.services ?? [],
        });
      } else {
        setVerify({ status: 'not_found', error: data.error || 'Structure introuvable' });
      }
    } catch (err: any) {
      const msg = await messageErreurEdgeFn(err, 'Erreur lors de la vérification Chorus Pro.');
      setVerify({ status: 'error', error: msg });
    }
  };

  const save = async () => {
    if (actif && !numeroStructure.trim()) {
      toast.error('Numéro de structure obligatoire si actif');
      return;
    }
    if (actif && verify.codeServiceObligatoire && !codeService.trim()) {
      toast.error('Le code service est obligatoire pour cette structure');
      return;
    }
    setSaving(true);
    const { data, error: rpcError } = await supabase.rpc('fn_admin_chorus_config_toggle' as any, {
      p_etablissement_id: etabId,
      p_actif: actif,
      p_numero_structure: numeroStructure.trim() || null,
      p_code_service: codeService.trim() || null,
      p_identifiant_cpro: identifiantCpro.trim() || null,
    });
    const error = rpcError || ((data as any)?.error ? { message: (data as any).error } : null);
    setSaving(false);
    if (error) {
      toast.error(`Erreur : ${error.message}`);
      return;
    }
    toast.success('Configuration Chorus Pro mise à jour');
    onSaved();
    onClose();
  };

  const activeServices = verify.services?.filter(s => s.actif) ?? [];

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Configuration Chorus Pro</DialogTitle>
          <DialogDescription>{etabNom}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div>
            <Label htmlFor="num-struct">Numéro de structure Chorus Pro *</Label>
            <div className="flex gap-2 mt-1">
              <Input
                id="num-struct"
                value={numeroStructure}
                onChange={e => { setNumeroStructure(e.target.value); setVerify({ status: 'idle' }); }}
                placeholder="ex. 10000071800067"
                className="flex-1"
              />
              <BoutonY2K
                type="button"
                variant="secondary"
                size="sm"
                onClick={verifyStructure}
                disabled={verify.status === 'loading' || !numeroStructure.trim()}
                loading={verify.status === 'loading'}
                className="shrink-0"
                iconeGauche={verify.status === 'loading' ? undefined : <Search className="h-4 w-4" />}
              >
                Vérifier
              </BoutonY2K>
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
              <p className="text-xs text-muted-foreground mt-1">SIRET étendu Chorus Pro destinataire</p>
            )}
          </div>

          <div>
            <Label htmlFor="code-service">
              Code service
              {verify.codeServiceObligatoire && <span className="text-destructive ml-1">* obligatoire pour cette structure</span>}
            </Label>
            {activeServices.length > 0 ? (
              <select
                id="code-service"
                value={codeService}
                onChange={e => setCodeService(e.target.value)}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              >
                <option value="">— Aucun —</option>
                {activeServices.map(s => (
                  <option key={s.code} value={s.code}>{s.code} — {s.nom}</option>
                ))}
              </select>
            ) : (
              <Input id="code-service" value={codeService} onChange={e => setCodeService(e.target.value)} placeholder="ex. PAIE" />
            )}
            <p className="text-xs text-muted-foreground mt-1">
              {activeServices.length > 0
                ? `${activeServices.length} service(s) disponible(s) — sélectionnez dans la liste`
                : 'Code du service exécutant (cliquez "Vérifier" pour charger la liste)'
              }
            </p>
          </div>

          <div>
            <Label htmlFor="id-cpro">Identifiant CPRO</Label>
            <Input id="id-cpro" value={identifiantCpro} onChange={e => setIdentifiantCpro(e.target.value)} placeholder="ex. 10000071800067" />
            <p className="text-xs text-muted-foreground mt-1">Identifiant destinataire Chorus Pro</p>
          </div>

          <div className="flex items-center justify-between pt-2 border-t">
            <div>
              <Label htmlFor="actif" className="cursor-pointer">Actif</Label>
              <p className="text-xs text-muted-foreground">Active la soumission Chorus Pro pour cet établissement</p>
            </div>
            <Switch id="actif" checked={actif} onCheckedChange={setActif} />
          </div>
        </div>

        <div className="flex justify-end gap-2 mt-4 pt-4 border-t">
          <BoutonY2K variant="secondary" onClick={onClose} disabled={saving}>Annuler</BoutonY2K>
          <BoutonY2K onClick={save} disabled={saving} loading={saving}>
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </BoutonY2K>
        </div>
      </DialogContent>
    </Dialog>
  );
}
