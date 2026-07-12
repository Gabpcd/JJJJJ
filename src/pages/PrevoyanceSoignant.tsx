import { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ShieldCheck, Clock, Calculator, CheckCircle2, Loader2, Mail, Sparkles } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { toast } from 'sonner';

type Niveau = 'BRONZE' | 'ARGENT' | 'OR' | 'INDIFFERENT';

const NIVEAUX: { valeur: Niveau; label: string; tauxRemplacement: number; description: string }[] = [
  { valeur: 'BRONZE', label: 'Bronze', tauxRemplacement: 30, description: 'Couverture de base, pour démarrer' },
  { valeur: 'ARGENT', label: 'Argent', tauxRemplacement: 50, description: 'Couverture intermédiaire recommandée' },
  { valeur: 'OR', label: 'Or', tauxRemplacement: 80, description: 'Couverture maximale, pour les hauts revenus' },
  { valeur: 'INDIFFERENT', label: 'Indifférent', tauxRemplacement: 0, description: 'Je veux juste être prévenu' },
];

function fmtEur(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(v);
}

export default function PrevoyanceSoignant() {
  usePageTitle('Prévoyance Madelin');
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [emailUser, setEmailUser] = useState('');
  const [dejaInscrit, setDejaInscrit] = useState(false);
  const [niveauActuel, setNiveauActuel] = useState<Niveau | null>(null);

  // Formulaire
  const [emailInput, setEmailInput] = useState('');
  const [niveau, setNiveau] = useState<Niveau>('INDIFFERENT');
  const [submitting, setSubmitting] = useState(false);

  // Calculateur
  const [revenuMensuel, setRevenuMensuel] = useState<number>(3500);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    Promise.all([
      supabase.from('soignants').select('email').eq('id', user.id).maybeSingle(),
      supabase.from('prevoyance_liste_attente').select('email, niveau_souhaite').eq('soignant_id', user.id).maybeSingle(),
    ]).then(([{ data: sg }, { data: la }]) => {
      const e = (sg as any)?.email ?? '';
      setEmailUser(e);
      setEmailInput(e);
      if (la) {
        setDejaInscrit(true);
        setNiveauActuel((la.niveau_souhaite as Niveau) ?? 'INDIFFERENT');
      }
      setLoading(false);
    });
  }, [user]);

  const inscrire = async () => {
    if (!emailInput.trim()) {
      toast.error('Email requis');
      return;
    }
    setSubmitting(true);
    const { data, error } = await supabase.rpc('fn_inscrire_liste_attente_prevoyance' as any, {
      p_email: emailInput.trim(),
      p_niveau: niveau,
    });
    setSubmitting(false);
    if (error) { toast.error(error.message); return; }
    const r = data as any;
    if (r?.success) {
      toast.success(r.message ?? 'Inscription enregistrée');
      setDejaInscrit(true);
      setNiveauActuel(niveau);
    } else {
      toast.error(r?.error ?? 'Erreur');
    }
  };

  const niveauChoisi = NIVEAUX.find(n => n.valeur === niveau);
  const perte30j = revenuMensuel; // perte sur 30j d'arrêt = 1 mois de revenu (simplification)
  const couvertureCalc = niveauChoisi && niveauChoisi.tauxRemplacement > 0
    ? Math.round((perte30j * niveauChoisi.tauxRemplacement) / 100)
    : 0;
  const resteCharge = perte30j - couvertureCalc;

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
            <ShieldCheck className="h-6 w-6 text-primary" /> Prévoyance Madelin
          </h1>
          <p className="text-sm text-muted-foreground mt-1 inline-flex items-center gap-2">
            <Clock className="h-4 w-4 text-warning" /> <strong>Bientôt disponible</strong> — partenariat assureur en cours de finalisation
          </p>
        </div>

        {/* Pédagogie Madelin */}
        <div className="card-base">
          <h2 className="font-semibold text-foreground mb-3">Qu'est-ce que la prévoyance Madelin ?</h2>
          <p className="text-sm text-muted-foreground leading-relaxed mb-3">
            La <strong>prévoyance Madelin</strong> est une assurance dédiée aux travailleurs indépendants (loi Madelin de 1994) qui couvre les <strong>arrêts de travail, l'invalidité et le décès</strong>. En cas de maladie ou d'accident, tu perçois un revenu de remplacement chaque mois pendant la durée de l'arrêt.
          </p>
          <div className="rounded-xl bg-primary/5 border border-primary/20 p-3 text-sm">
            <p className="font-semibold text-primary mb-1">💡 Avantage fiscal majeur</p>
            <p className="text-muted-foreground text-xs">
              Les cotisations Madelin sont <strong>déductibles de ton revenu imposable BNC</strong> dans la limite d'un plafond annuel (≈ 3,75 % de ton revenu professionnel + 7 % du PASS, plafonné). Concrètement, l'État rembourse une partie de ta cotisation via une réduction d'impôts.
            </p>
          </div>
        </div>

        {/* Calculateur */}
        <div className="card-base">
          <h2 className="font-semibold text-foreground mb-3 inline-flex items-center gap-2">
            <Calculator className="h-4 w-4 text-primary" /> Calculateur revenu remplacé en cas d'arrêt
          </h2>
          <p className="text-xs text-muted-foreground mb-4">
            Estime ce que tu toucherais par mois en cas d'arrêt de travail prolongé selon le niveau de couverture choisi. Calcul indicatif basé sur ton revenu mensuel libéral.
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4">
            <div>
              <label htmlFor="prevoyance-revenu" className="text-xs font-medium text-foreground mb-1 block">Ton revenu mensuel net (€)</label>
              <input
                id="prevoyance-revenu"
                type="number" min={500} max={20000} step={100}
                value={revenuMensuel}
                onChange={(e) => setRevenuMensuel(Math.max(0, parseInt(e.target.value, 10) || 0))}
                className="w-full px-3 py-2 text-sm rounded-lg border border-border bg-background"
              />
            </div>
            <div>
              <label htmlFor="prevoyance-niveau-calcul" className="text-xs font-medium text-foreground mb-1 block">Niveau de couverture</label>
              <select
                id="prevoyance-niveau-calcul"
                value={niveau}
                onChange={(e) => setNiveau(e.target.value as Niveau)}
                className="w-full px-3 py-2 text-sm rounded-lg border border-border bg-background"
              >
                {NIVEAUX.filter(n => n.valeur !== 'INDIFFERENT').map(n => (
                  <option key={n.valeur} value={n.valeur}>{n.label} ({n.tauxRemplacement}% remplacement)</option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
            <div className="rounded-xl border border-border bg-card p-3 text-center">
              <p className="text-[10px] uppercase font-semibold text-muted-foreground">Perte revenu / mois</p>
              <p className="text-xl font-extrabold text-destructive mt-1">{fmtEur(perte30j)}</p>
            </div>
            <div className="rounded-xl border border-success/30 bg-success/5 p-3 text-center">
              <p className="text-[10px] uppercase font-semibold text-success">Couverture {niveauChoisi?.label} ({niveauChoisi?.tauxRemplacement}%)</p>
              <p className="text-xl font-extrabold text-success mt-1">{fmtEur(couvertureCalc)}</p>
            </div>
            <div className="rounded-xl border border-border bg-card p-3 text-center">
              <p className="text-[10px] uppercase font-semibold text-muted-foreground">Reste à ta charge</p>
              <p className="text-xl font-extrabold text-foreground mt-1">{fmtEur(resteCharge)}</p>
            </div>
          </div>
        </div>

        {/* Liste d'attente */}
        {dejaInscrit ? (
          <div className="card-base border-l-4 border-l-success bg-success/5">
            <h2 className="font-semibold text-foreground inline-flex items-center gap-2 mb-2">
              <CheckCircle2 className="h-5 w-5 text-success" /> Tu es sur la liste d'attente
            </h2>
            <p className="text-sm text-muted-foreground">
              Tu seras prévenu·e par email à <strong>{emailUser || emailInput}</strong> dès le lancement du programme prévoyance Jolene.
              {niveauActuel && niveauActuel !== 'INDIFFERENT' && (
                <> Niveau préféré : <strong>{NIVEAUX.find(n => n.valeur === niveauActuel)?.label}</strong>.</>
              )}
            </p>
            <button
              type="button"
              onClick={() => { setNiveau(niveauActuel ?? 'INDIFFERENT'); setDejaInscrit(false); }}
              className="text-xs text-primary hover:underline mt-2"
            >
              Modifier mon niveau préféré
            </button>
          </div>
        ) : (
          <div className="card-base border-l-4 border-l-primary bg-primary/5">
            <h2 className="font-semibold text-foreground inline-flex items-center gap-2 mb-2">
              <Sparkles className="h-5 w-5 text-primary" /> Inscris-toi à la liste d'attente
            </h2>
            <p className="text-xs text-muted-foreground mb-4">
              Sois prévenu·e en avant-première dès que les contrats prévoyance Jolene seront disponibles. Aucune obligation, tu peux te désinscrire à tout moment.
            </p>

            <div className="grid grid-cols-1 sm:grid-cols-[1fr_auto] gap-2 mb-3">
              <div className="relative">
                <Mail className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                <input
                  aria-label="Email pour la liste d’attente prévoyance"
                  type="email"
                  value={emailInput}
                  onChange={(e) => setEmailInput(e.target.value)}
                  placeholder="ton.email@exemple.fr"
                  className="w-full pl-8 pr-3 py-2 text-sm rounded-lg border border-border bg-background"
                />
              </div>
              <select
                aria-label="Niveau de couverture souhaité"
                value={niveau}
                onChange={(e) => setNiveau(e.target.value as Niveau)}
                className="px-3 py-2 text-sm rounded-lg border border-border bg-background"
              >
                {NIVEAUX.map(n => (
                  <option key={n.valeur} value={n.valeur}>{n.label}</option>
                ))}
              </select>
            </div>

            <button
              type="button"
              onClick={inscrire}
              disabled={submitting || !emailInput.trim()}
              className="btn-primary text-sm inline-flex items-center gap-2"
            >
              {submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}
              {submitting ? 'Inscription...' : 'M\'inscrire à la liste d\'attente'}
            </button>
          </div>
        )}

        {/* Note bas de page */}
        <div className="text-xs text-muted-foreground bg-muted/30 rounded-xl p-4 border border-border">
          <p className="font-semibold text-foreground mb-1">Informations</p>
          <ul className="list-disc list-inside space-y-1">
            <li>Ton email reste confidentiel et ne sera utilisé que pour te prévenir du lancement du programme prévoyance.</li>
            <li>Aucune cotisation n'est prélevée pour l'inscription à la liste d'attente.</li>
            <li>Les niveaux Bronze/Argent/Or sont indicatifs ; les contrats finaux pourront différer selon le partenaire retenu.</li>
            <li>Tu peux consulter et exporter tes données via ton Centre RGPD.</li>
          </ul>
        </div>
      </div>
    </LayoutApp>
  );
}
