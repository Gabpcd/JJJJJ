import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

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

export function ChorusConfigEtabDialog({ etabId, etabNom, config, open, onClose, onSaved }: Props) {
  const [numeroStructure, setNumeroStructure] = useState('');
  const [codeService, setCodeService] = useState('');
  const [identifiantCpro, setIdentifiantCpro] = useState('');
  const [actif, setActif] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setNumeroStructure(config?.numero_structure ?? '');
    setCodeService(config?.code_service ?? '');
    setIdentifiantCpro(config?.identifiant_cpro ?? '');
    setActif(!!config?.actif);
  }, [config, open]);

  const save = async () => {
    if (actif && !numeroStructure.trim()) {
      toast.error('Numéro de structure obligatoire si actif');
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
            <Input id="num-struct" value={numeroStructure} onChange={e => setNumeroStructure(e.target.value)} placeholder="ex. 10000071800067" />
            <p className="text-xs text-muted-foreground mt-1">SIRET étendu Chorus Pro destinataire (14 chiffres + extension si applicable)</p>
          </div>

          <div>
            <Label htmlFor="code-service">Code service</Label>
            <Input id="code-service" value={codeService} onChange={e => setCodeService(e.target.value)} placeholder="ex. PAIE" />
            <p className="text-xs text-muted-foreground mt-1">Code du service exécutant (si applicable, sinon laisser vide)</p>
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
          <Button variant="outline" onClick={onClose} disabled={saving}>Annuler</Button>
          <Button onClick={save} disabled={saving}>
            {saving ? 'Enregistrement…' : 'Enregistrer'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
