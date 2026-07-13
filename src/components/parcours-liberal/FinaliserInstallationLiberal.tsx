import { useCallback, useEffect, useState } from 'react';
import { BadgeCheck, Building2, Loader2, Lock, Receipt } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';
import { validerSiret } from '@/lib/luhn';

interface ProfilLiberal {
  siret_liberal: string | null;
  siret_liberal_verifie: boolean | null;
  siret_liberal_verifie_le: string | null;
  siret_liberal_raison_sociale: string | null;
  siret_liberal_coherence_identite: boolean | null;
  statut_liberal: string | null;
  type_contrat: string | null;
  assujetti_tva: boolean | null;
  numero_tva: string | null;
}

// Étape finale du parcours libéral : une fois immatriculé à l'URSSAF (guichet
// unique), le soignant renseigne son SIRET + son statut TVA, puis active son
// statut libéral sur Jolene. Ces 3 informations sont OBLIGATOIRES sur les notes
// d'honoraires (mention SIRET + TVA) — sans cette étape, le libéral ne pouvait
// pas facturer correctement (les fonctions backend existaient mais n'étaient
// branchées nulle part côté app).
export function FinaliserInstallationLiberal() {
  const { user } = useAuth();
  const [profil, setProfil] = useState<ProfilLiberal | null>(null);
  const [loading, setLoading] = useState(true);
  const [siret, setSiret] = useState('');
  const [assujettiTva, setAssujettiTva] = useState(false);
  const [numeroTva, setNumeroTva] = useState('');
  const [savingSiret, setSavingSiret] = useState(false);
  const [savingTva, setSavingTva] = useState(false);
  const [activating, setActivating] = useState(false);

  const charger = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from('soignants')
      .select('siret_liberal, siret_liberal_verifie, siret_liberal_verifie_le, siret_liberal_raison_sociale, siret_liberal_coherence_identite, statut_liberal, type_contrat, assujetti_tva, numero_tva')
      .eq('id', user.id)
      .maybeSingle();
    if (data) {
      const p = data as unknown as ProfilLiberal;
      setProfil(p);
      setSiret(p.siret_liberal || '');
      setAssujettiTva(p.assujetti_tva === true);
      setNumeroTva(p.numero_tva || '');
    }
    setLoading(false);
  }, [user]);

  useEffect(() => {
    charger();
  }, [charger]);

  const actif = profil?.statut_liberal === 'ACTIF' || profil?.type_contrat === 'LIBERAL';
  const siretEnregistre = Boolean(profil?.siret_liberal);
  const siretSaisi = siret.replace(/\s/g, '');
  const siretVerifie = Boolean(
    profil?.siret_liberal
    && profil.siret_liberal === siretSaisi
    && profil.siret_liberal_verifie === true
    && profil.siret_liberal_coherence_identite === true
  );

  const enregistrerSiret = async () => {
    const v = validerSiret(siret);
    if (!v.valide) {
      toast.error(v.message);
      return;
    }
    setSavingSiret(true);
    try {
      const { data: verifData, error } = await supabase.functions.invoke('verify-siret', {
        body: { siret: siret.replace(/\s/g, ''), usage: 'SOIGNANT_LIBERAL' },
      });
      if (error) throw error;
      const verification = verifData as {
        ok?: boolean;
        enregistre?: boolean;
        code?: string;
        raison_sociale?: string | null;
        message?: string;
        error?: string;
      } | null;
      if (!verification?.ok || !verification.enregistre) {
        toast.error(verification?.message || verification?.error || 'Ce SIRET ne peut pas être vérifié');
        return;
      }
      toast.success(`SIRET vérifié et enregistré${verification.raison_sociale ? ` : ${verification.raison_sociale}` : ''}`);
      await charger();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Vérification INSEE temporairement indisponible');
    } finally {
      setSavingSiret(false);
    }
  };

  const enregistrerTva = async () => {
    if (assujettiTva && !numeroTva.trim()) {
      toast.error('Numéro de TVA intracommunautaire requis si tu es assujetti');
      return;
    }
    setSavingTva(true);
    const { data, error } = await supabase.rpc('fn_modifier_tva_liberal', {
      p_assujetti_tva: assujettiTva,
      p_numero_tva: assujettiTva ? numeroTva.trim() : null,
    });
    setSavingTva(false);
    const res = data as { error?: string } | null;
    if (error || res?.error) {
      toast.error(res?.error || error?.message || 'Erreur lors de la mise à jour de la TVA');
      return;
    }
    toast.success('Statut TVA enregistré');
    await charger();
  };

  const activer = async () => {
    setActivating(true);
    const { data, error } = await supabase.rpc('fn_activer_liberal');
    setActivating(false);
    const res = data as { error?: string; success?: boolean } | null;
    if (error || res?.error) {
      toast.error(res?.error || error?.message || "Activation impossible");
      return;
    }
    toast.success('Ton statut libéral est activé sur Jolene 🎉');
    await charger();
  };

  if (loading) {
    return (
      <div className="card-base flex justify-center py-6">
        <Loader2 className="h-5 w-5 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="card-base space-y-5">
      <div className="flex items-center gap-2">
        <Building2 className="h-5 w-5 text-primary" />
        <h3 className="text-base font-bold text-foreground">Finaliser mon installation sur Jolene</h3>
      </div>
      <p className="text-xs text-muted-foreground -mt-2">
        Une fois immatriculé à l'URSSAF (guichet unique), renseigne ton SIRET et ton statut TVA.
        Ces informations figureront sur tes notes d'honoraires.
      </p>

      {actif && (
        <div className="rounded-xl border border-success/30 bg-success/5 p-3 flex items-start gap-2">
          <BadgeCheck className="h-5 w-5 text-success shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-foreground">Statut libéral actif</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Tu factures désormais en honoraires. Tu peux encore mettre à jour ton statut TVA ci-dessous.
            </p>
          </div>
        </div>
      )}

      {/* SIRET */}
      <div className="space-y-2">
        <Label htmlFor="siret-liberal" className="text-sm font-medium flex items-center gap-1.5">
          SIRET {actif && <Lock className="h-3.5 w-3.5 text-muted-foreground" />}
        </Label>
        {actif ? (
          <p className="text-sm font-mono text-foreground">{profil?.siret_liberal}</p>
        ) : (
          <>
            <div className="flex flex-col sm:flex-row gap-2">
              <Input
                id="siret-liberal"
                inputMode="numeric"
                autoComplete="off"
                placeholder="14 chiffres"
                value={siret}
                maxLength={17}
                onChange={(e) => setSiret(e.target.value)}
              />
              <BoutonY2K
                variant="secondary"
                loading={savingSiret}
                disabled={savingSiret}
                onClick={enregistrerSiret}
              >
                Vérifier et enregistrer
              </BoutonY2K>
            </div>
            {siretVerifie && (
              <div className="rounded-lg border border-success/30 bg-success/5 p-2" role="status">
                <p className="text-xs font-medium text-success">SIRET officiel actif et identité vérifiée.</p>
                {profil?.siret_liberal_raison_sociale && (
                  <p className="mt-0.5 text-xs text-muted-foreground">{profil.siret_liberal_raison_sociale}</p>
                )}
              </div>
            )}
            {siretEnregistre && !siretVerifie && (
              <p className="text-xs text-warning" role="status">
                Ce SIRET n’est pas encore vérifié. Relance la vérification avant l’activation.
              </p>
            )}
          </>
        )}
      </div>

      {/* TVA */}
      <div className="space-y-2 border-t border-border pt-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <Label htmlFor="tva-switch" className="text-sm font-medium flex items-center gap-1.5">
              <Receipt className="h-4 w-4 text-muted-foreground" /> Assujetti à la TVA
            </Label>
            <p className="text-xs text-muted-foreground mt-0.5">
              Par défaut non (franchise en base). À activer si tu dépasses le seuil légal.
            </p>
          </div>
          <Switch id="tva-switch" checked={assujettiTva} onCheckedChange={setAssujettiTva} />
        </div>
        {assujettiTva && (
          <Input
            inputMode="text"
            autoComplete="off"
            placeholder="N° TVA intracommunautaire (ex. FR12345678901)"
            value={numeroTva}
            onChange={(e) => setNumeroTva(e.target.value.toUpperCase())}
          />
        )}
        <BoutonY2K variant="secondary" loading={savingTva} disabled={savingTva} onClick={enregistrerTva}>
          Enregistrer mon statut TVA
        </BoutonY2K>
      </div>

      {/* Activation */}
      {!actif && (
        <div className="border-t border-border pt-4 space-y-2">
          <p className="text-xs text-muted-foreground">
            Dernière étape : active ton statut libéral sur Jolene. Tu bascules alors sur la facturation
            en honoraires (notes d'honoraires au lieu de bulletins de paie).
          </p>
          <BoutonY2K
            variant="primary"
            loading={activating}
            disabled={activating || !siretVerifie}
            onClick={activer}
            className="w-full"
          >
            Activer mon statut libéral
          </BoutonY2K>
          {!siretVerifie && (
            <p className="text-xs text-muted-foreground text-center">Vérifie d’abord ton SIRET officiel et son titulaire.</p>
          )}
        </div>
      )}
    </div>
  );
}
