import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { CheckCircle, AlertTriangle, ExternalLink, CreditCard, FileSignature, Info, Landmark, AlertCircle, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { toast } from 'sonner';

interface Props {
  userId: string;
  typeExercice: string | null;
  mandatFacturationSigne: boolean | null;
  mandatFacturationSigneLe: string | null;
  estCompteTest: boolean;
}

function StripeConnectStatus({ userId, estCompteTest }: { userId: string; estCompteTest: boolean }) {
  const [status, setStatus] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  useEffect(() => {
    if (!userId) return;
    if (estCompteTest) { setLoading(false); return; }
    supabase.functions.invoke('stripe-connect-status').then(({ data, error }) => {
      if (error) {
        setErreur('Service Stripe temporairement indisponible. Réessayez dans quelques instants.');
      } else {
        setStatus(data);
      }
      setLoading(false);
    }).then(undefined, () => {
      setErreur('Service Stripe temporairement indisponible. Réessayez dans quelques instants.');
      setLoading(false);
    });
  }, [userId, estCompteTest]);

  if (estCompteTest) return (
    <div className="p-3 rounded-xl border border-info/30 bg-info/5 flex items-start gap-3" role="status">
      <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
      <div>
        <p className="text-sm font-semibold text-foreground">Stripe désactivé sur ce compte de test</p>
        <p className="text-xs text-muted-foreground mt-1">Aucun compte bancaire ni paiement réel ne sera créé avec les données de démonstration.</p>
      </div>
    </div>
  );

  const lancerOnboarding = async () => {
    setActionLoading(true);
    const { data, error } = await supabase.functions.invoke('stripe-connect-onboard');
    if (error || !(data as any)?.url) {
      const is403 = (data as any)?.error?.includes('libéral') || (error as any)?.message?.includes('403') || (error as any)?.status === 403;
      if (is403) {
        toast('La connexion Stripe sera disponible au lancement.', { icon: 'ℹ️' });
      } else {
        toast.error('Erreur lors de la connexion à Stripe.');
      }
      setActionLoading(false);
      return;
    }
    import('@/lib/platform').then((m) => m.ouvrirLienExterne((data as any).url));
    setActionLoading(false);
  };

  if (loading) return <div className="text-sm text-muted-foreground">Chargement…</div>;
  if (erreur) return (
    <div className="p-3 rounded-xl border border-warning/30 bg-warning/5 flex items-start gap-3" role="alert">
      <AlertTriangle className="h-4 w-4 text-warning shrink-0 mt-0.5" />
      <div className="text-sm">
        <p className="font-semibold text-warning">Statut paiement indisponible</p>
        <p className="text-xs text-warning/80 mt-1">{erreur}</p>
      </div>
    </div>
  );
  if (!status) return null;

  if (status.statut === 'COMPLET' && status.charges_enabled && status.payouts_enabled) {
    return (
      <div className="p-3 rounded-xl border border-success/30 bg-success/5 flex items-center gap-3">
        <CheckCircle className="h-5 w-5 text-success shrink-0" />
        <div>
          <p className="text-sm font-semibold text-success">Stripe Connect actif</p>
          <p className="text-xs text-muted-foreground">Tes honoraires sont versés automatiquement.</p>
        </div>
      </div>
    );
  }

  if (status.statut === 'EN_COURS' || status.statut === 'SUSPENDU') {
    return (
      <div className="p-3 rounded-xl border border-warning/30 bg-warning/5 space-y-2">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-warning">Compte Stripe Connect non finalisé</p>
            <p className="text-xs text-muted-foreground mt-0.5">Finalise-le pour recevoir tes honoraires automatiquement.</p>
          </div>
        </div>
        <BoutonY2K size="sm" variant="secondary" onClick={lancerOnboarding} disabled={actionLoading} loading={actionLoading} className="gap-2" iconeGauche={actionLoading ? undefined : <ExternalLink className="h-3.5 w-3.5" />}>
          Finaliser mon compte Stripe
        </BoutonY2K>
      </div>
    );
  }

  if (status.statut === 'SUPPRIME') {
    return (
      <div className="p-3 rounded-xl border border-destructive/30 bg-destructive/5 space-y-2">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-destructive">Compte Stripe supprimé</p>
            <p className="text-xs text-muted-foreground mt-0.5">Recommence l'onboarding pour recevoir tes paiements.</p>
          </div>
        </div>
        <BoutonY2K size="sm" variant="destructive" onClick={lancerOnboarding} disabled={actionLoading} loading={actionLoading} className="gap-2" iconeGauche={actionLoading ? undefined : <ExternalLink className="h-3.5 w-3.5" />}>
          Recommencer l'onboarding
        </BoutonY2K>
      </div>
    );
  }

  return (
    <div className="p-3 rounded-xl border border-border bg-muted/30 space-y-2">
      <div className="flex items-start gap-3">
        <CreditCard className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Active Stripe Connect</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Pour recevoir tes honoraires automatiquement. Sans Stripe Connect, les établissements te paieront par virement.
          </p>
        </div>
      </div>
      <BoutonY2K size="sm" onClick={lancerOnboarding} disabled={actionLoading} loading={actionLoading} className="gap-2" iconeGauche={actionLoading ? undefined : <ExternalLink className="h-3.5 w-3.5" />}>
        Activer Stripe Connect
      </BoutonY2K>
    </div>
  );
}

export function SectionPaiements({ userId, typeExercice, mandatFacturationSigne, mandatFacturationSigneLe, estCompteTest }: Props) {
  const navigate = useNavigate();
  const estLiberalOuMixte = typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';

  if (!typeExercice) {
    return (
      <div className="card-base">
        <div className="flex items-start gap-3">
          <Info className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div>
            <h2 className="text-base font-semibold text-foreground mb-1">Type d'exercice à définir</h2>
            <p className="text-sm text-muted-foreground">
              Définis d'abord ton type d'exercice dans l'onglet <strong>Profil principal</strong>.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {estLiberalOuMixte && (
        <>
          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
              <CreditCard className="h-4 w-4 text-primary" /> Stripe Connect
            </h2>
            <p className="text-xs text-muted-foreground mb-3">
              Reçois tes honoraires libéraux directement sur ton compte bancaire.
            </p>
            <StripeConnectStatus userId={userId} estCompteTest={estCompteTest} />
          </div>

          <div className="card-base">
            <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
              <FileSignature className="h-4 w-4 text-primary" /> Mandat de facturation
            </h2>
            {mandatFacturationSigne ? (
              <div className="p-3 rounded-xl border border-success/30 bg-success/5">
                <p className="text-sm font-semibold text-success flex items-center gap-2">
                  <CheckCircle className="h-4 w-4" /> Mandat signé
                </p>
                {mandatFacturationSigneLe && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Le {new Date(mandatFacturationSigneLe).toLocaleDateString('fr-FR')}
                  </p>
                )}
              </div>
            ) : (
              <div className="space-y-2">
                <p className="text-sm text-muted-foreground">
                  Le mandat de facturation autorise Jolene à émettre les factures à ton nom.
                </p>
                <button
                  onClick={() => navigate('/soignant/mandat-facturation')}
                  className="btn-primary text-sm py-2 px-3"
                >
                  Signer le mandat →
                </button>
              </div>
            )}
          </div>
        </>
      )}

      <SectionIbanPrime />
    </div>
  );
}

function validateIbanChecksum(iban: string): boolean {
  const cleaned = iban.toUpperCase().replace(/\s/g, '');
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$/.test(cleaned)) return false;
  const rearranged = cleaned.slice(4) + cleaned.slice(0, 4);
  let numeric = '';
  for (const c of rearranged) {
    numeric += c >= 'A' && c <= 'Z' ? (c.charCodeAt(0) - 55).toString() : c;
  }
  let remainder = 0;
  for (const c of numeric) {
    remainder = (remainder * 10 + parseInt(c)) % 97;
  }
  return remainder === 1;
}

function SectionIbanPrime() {
  const navigate = useNavigate();
  const [iban, setIban] = useState('');
  const [titulaire, setTitulaire] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [current, setCurrent] = useState<{
    iban_renseigne: boolean;
    iban_verifie: boolean;
    verification_requise?: boolean;
    iban_last4: string | null;
    iban_titulaire: string | null;
  } | null>(null);

  useEffect(() => {
    supabase.rpc('fn_consulter_mon_iban' as any).then(({ data }: any) => {
      if (data && !data.error) setCurrent(data);
      setLoading(false);
    });
  }, []);

  const ibanClean = iban.toUpperCase().replace(/\s/g, '');
  const ibanValid = ibanClean.length >= 14 && validateIbanChecksum(ibanClean);

  const submit = async () => {
    if (!ibanValid || !titulaire.trim()) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('fn_enregistrer_mon_iban' as any, {
      p_iban: ibanClean,
      p_titulaire: titulaire.trim(),
    });
    setSaving(false);
    const result = data as any;
    if (error) { toast.error(error.message); return; }
    if (result?.error) { toast.error(result.error); return; }
    toast.success(result?.message || 'IBAN enregistré');
    setCurrent({
      iban_renseigne: true,
      iban_verifie: true,
      verification_requise: false,
      iban_last4: result.iban_last4,
      iban_titulaire: result.titulaire,
    });
    setIban('');
    setTitulaire('');
  };

  return (
    <div className="card-base">
      <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
        <Landmark className="h-4 w-4 text-primary" /> Coordonnées bancaires
      </h2>
      <p className="text-xs text-muted-foreground mb-4">
        Ton IBAN est utilisé pour le versement de tes primes de parrainage. Il n'est jamais partagé avec l'établissement.
      </p>

      {loading ? (
        <div className="flex justify-center py-4"><Loader2 className="h-5 w-5 animate-spin text-muted-foreground" /></div>
      ) : (
        <div className="space-y-4">
          {current?.iban_renseigne && current.iban_verifie && (
            <div className="flex items-start gap-3 rounded-xl border border-success/30 bg-success/5 p-3">
              <CheckCircle className="h-5 w-5 text-success shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-semibold text-success">IBAN enregistré</p>
                <p className="text-sm text-muted-foreground font-mono mt-1">
                  •••• •••• •••• •••• •••• {current.iban_last4}
                </p>
                {current.iban_titulaire && (
                  <p className="text-xs text-muted-foreground mt-0.5">Titulaire : {current.iban_titulaire}</p>
                )}
              </div>
            </div>
          )}

          {current?.iban_renseigne && !current.iban_verifie && (
            <div className="flex items-start gap-3 rounded-xl border border-warning/30 bg-warning/5 p-3">
              <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold text-foreground">RIB vérifié requis</p>
                <p className="text-xs text-muted-foreground mt-1">
                  L'ancien IBAN est conservé dans ton historique, mais aucun nouveau versement ne peut l'utiliser sans un RIB courant vérifié portant exactement le même IBAN et ton identité.
                </p>
                <BoutonY2K
                  variant="secondary"
                  size="sm"
                  className="mt-3"
                  onClick={() => navigate('/soignant/documents')}
                >
                  Téléverser mon RIB
                </BoutonY2K>
              </div>
            </div>
          )}

          <div className="space-y-3">
            <div>
              <label htmlFor="iban-input" className="text-xs font-medium text-foreground block mb-1">
                {current?.iban_renseigne ? 'Modifier l\'IBAN' : 'IBAN'}
              </label>
              <input
                id="iban-input"
                type="text"
                value={iban}
                onChange={(e) => setIban(e.target.value.toUpperCase())}
                placeholder="FR76 3000 6000 0112 3456 7890 189"
                className="w-full rounded-lg border border-border bg-background px-3 py-2.5 text-base md:text-sm font-mono text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
                autoComplete="off"
                spellCheck={false}
              />
              {iban.length > 4 && !ibanValid && (
                <p className="text-xs text-destructive mt-1 flex items-center gap-1">
                  <AlertCircle className="h-3 w-3" /> IBAN invalide
                </p>
              )}
              {ibanValid && (
                <p className="text-xs text-success mt-1 flex items-center gap-1">
                  <CheckCircle className="h-3 w-3" /> IBAN valide
                </p>
              )}
            </div>

            <div>
              <label htmlFor="titulaire-input" className="text-xs font-medium text-foreground block mb-1">Nom du titulaire</label>
              <input
                id="titulaire-input"
                type="text"
                value={titulaire}
                onChange={(e) => setTitulaire(e.target.value)}
                placeholder="Prénom Nom"
                className="w-full rounded-lg border border-border bg-background px-3 py-2.5 text-base md:text-sm text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
                autoComplete="name"
              />
            </div>

            <BoutonY2K
              variant="primary"
              size="sm"
              onClick={submit}
              disabled={!ibanValid || !titulaire.trim() || saving}
              className="w-full"
            >
              {saving ? 'Enregistrement…' : current?.iban_renseigne ? 'Mettre à jour' : 'Enregistrer l\'IBAN'}
            </BoutonY2K>
          </div>
        </div>
      )}
    </div>
  );
}
