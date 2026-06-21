import { useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle, Coins, Loader2, Save, Settings, ShieldAlert, Sparkles, TrendingUp, Check,
} from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { EditeurEquivalencesScolarite } from '@/components/admin/EditeurEquivalencesScolarite';

interface Parametre {
  cle: string;
  valeur: number;
  label: string;
  description: string | null;
  unite: string | null;
  val_min: number | null;
  val_max: number | null;
  categorie: string;
  avertissement: string | null;
  cablee: boolean;
  maj_le: string;
}

// Métadonnées d'affichage par catégorie (ordre + libellé + icône).
const CATEGORIES: { cle: string; label: string; description: string; icon: typeof Coins }[] = [
  { cle: 'FINANCE', label: 'Finance & facturation', description: 'Commission et délais de paiement. Encadrés par la loi — modifiez en connaissance de cause.', icon: Coins },
  { cle: 'RISQUE', label: 'Risque & recouvrement', description: 'Seuils de blocage automatique des établissements en retard.', icon: ShieldAlert },
  { cle: 'OPERATIONS', label: 'Opérations', description: 'Délais d\'automatisation des présences et relances.', icon: Settings },
  { cle: 'ENGAGEMENT', label: 'Engagement (swipe)', description: 'Mécaniques de jeu du matching soignant.', icon: Sparkles },
  { cle: 'CROISSANCE', label: 'Croissance & options', description: 'Primes et options payantes (parrainage, boost, garantie).', icon: TrendingUp },
];

export default function AdminConfig() {
  usePageTitle('Configuration système');
  const [loading, setLoading] = useState(true);
  const [params, setParams] = useState<Parametre[]>([]);
  const [brouillons, setBrouillons] = useState<Record<string, string>>({});
  const [savingCle, setSavingCle] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_parametres' as any);
    if (error) {
      toast.error(error.message || 'Erreur de chargement');
      setLoading(false);
      return;
    }
    const liste = (data || []) as Parametre[];
    setParams(liste);
    setBrouillons(Object.fromEntries(liste.map((p) => [p.cle, String(p.valeur)])));
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const parCategorie = useMemo(() => {
    const map = new Map<string, Parametre[]>();
    for (const p of params) {
      if (!map.has(p.categorie)) map.set(p.categorie, []);
      map.get(p.categorie)!.push(p);
    }
    return map;
  }, [params]);

  const enregistrer = async (p: Parametre) => {
    const brut = brouillons[p.cle];
    const valeur = brut === '' || brut === undefined ? NaN : Number(brut);
    if (Number.isNaN(valeur)) { toast.error('Valeur numérique invalide'); return; }
    if (p.val_min != null && valeur < p.val_min) { toast.error(`Minimum : ${p.val_min}`); return; }
    if (p.val_max != null && valeur > p.val_max) { toast.error(`Maximum : ${p.val_max}`); return; }
    setSavingCle(p.cle);
    const { data, error } = await supabase.rpc('fn_admin_maj_parametre' as any, { p_cle: p.cle, p_valeur: valeur });
    if (error || (data as any)?.success === false) {
      toast.error((data as any)?.error || error?.message || 'Erreur');
      setSavingCle(null);
      return;
    }
    toast.success(`« ${p.label} » mis à jour.`);
    setSavingCle(null);
    setParams((prev) => prev.map((x) => (x.cle === p.cle ? { ...x, valeur, maj_le: new Date().toISOString() } : x)));
  };

  if (loading) {
    return (
      <LayoutAdmin>
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutAdmin>
    );
  }

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Configuration" />
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Settings className="h-6 w-6 text-primary" /> Configuration système
          </h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-3xl">
            Réglages de la plateforme, modifiables par l'admin uniquement. Une modification s'applique
            aux opérations <strong>à venir</strong> (les missions et factures déjà figées conservent leurs
            valeurs historiques). Les paramètres marqués <span className="font-medium text-foreground">Actif</span> sont
            réellement consommés par le code ; ceux marqués <span className="font-medium text-foreground">Bientôt</span> sont
            stockés mais pas encore branchés.
          </p>
        </div>

        {CATEGORIES.filter((c) => parCategorie.has(c.cle)).map((cat) => {
          const liste = parCategorie.get(cat.cle)!;
          return (
            <section key={cat.cle}>
              <h2 className="text-base font-bold text-foreground mb-1 flex items-center gap-2">
                <cat.icon className="h-4 w-4 text-primary" /> {cat.label}
              </h2>
              <p className="text-xs text-muted-foreground mb-3">{cat.description}</p>
              <div className="space-y-3">
                {liste.map((p) => {
                  const brouillon = brouillons[p.cle] ?? String(p.valeur);
                  const modifie = brouillon !== String(p.valeur);
                  const saving = savingCle === p.cle;
                  return (
                    <div key={p.cle} className="card-base">
                      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <p className="font-medium text-foreground">{p.label}</p>
                            {p.cablee ? (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-success/10 text-success inline-flex items-center gap-1">
                                <Check className="h-3 w-3" /> Actif
                              </span>
                            ) : (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-warning/10 text-warning">
                                Bientôt
                              </span>
                            )}
                          </div>
                          {p.description && (
                            <p className="text-xs text-muted-foreground mt-1">{p.description}</p>
                          )}
                          {p.avertissement && (
                            <p className="text-xs text-warning mt-2 flex items-start gap-1.5">
                              <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                              <span>{p.avertissement}</span>
                            </p>
                          )}
                        </div>
                        <div className="flex items-end gap-2 shrink-0">
                          <div>
                            <label htmlFor={`param-${p.cle}`} className="sr-only">{p.label}</label>
                            <div className="flex items-center gap-1.5">
                              <input
                                id={`param-${p.cle}`}
                                type="number"
                                inputMode="decimal"
                                step="any"
                                min={p.val_min ?? undefined}
                                max={p.val_max ?? undefined}
                                value={brouillon}
                                onChange={(e) => setBrouillons((b) => ({ ...b, [p.cle]: e.target.value }))}
                                className="input-base w-28 text-right"
                              />
                              {p.unite && <span className="text-sm text-muted-foreground whitespace-nowrap">{p.unite}</span>}
                            </div>
                            <p className="text-[10px] text-muted-foreground mt-1 text-right">
                              {p.val_min != null && p.val_max != null
                                ? `${p.val_min} – ${p.val_max}`
                                : p.val_min != null
                                  ? `min ${p.val_min}`
                                  : p.val_max != null
                                    ? `max ${p.val_max}`
                                    : ''}
                            </p>
                          </div>
                          <BoutonY2K
                            size="sm"
                            disabled={!modifie || saving}
                            loading={saving}
                            onClick={() => enregistrer(p)}
                            iconeGauche={saving ? undefined : <Save className="h-3.5 w-3.5" />}
                          >
                            Enregistrer
                          </BoutonY2K>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>
          );
        })}

        <EditeurEquivalencesScolarite />
      </div>
    </LayoutAdmin>
  );
}
