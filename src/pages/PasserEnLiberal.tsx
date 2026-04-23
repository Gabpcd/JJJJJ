import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Rocket, ExternalLink, Check, Circle, Loader2, PartyPopper,
  ClipboardCheck, FileText, Building2, Heart, Shield, Landmark,
  Copy, CheckCircle2, XCircle, ArrowRight,
} from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { JaugeProgression } from '@/components/JaugeProgression';
import { Checkbox } from '@/components/ui/checkbox';
import { Progress } from '@/components/ui/progress';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { ConfettiMini } from '@/components/ConfettiMini';
import { usePageTitle } from '@/hooks/usePageTitle';
import { capturerErreurSentry } from '@/lib/sentry';
import { estEligibleLiberal } from '@/lib/regles-installation-liberal';
import type jsPDF from 'jspdf';

const STORAGE_KEY = 'liberal_parcours_checks';

function getChecks(userId: string): Record<string, boolean> {
  try {
    return JSON.parse(localStorage.getItem(`${STORAGE_KEY}_${userId}`) || '{}');
  } catch { return {}; }
}
function saveChecks(userId: string, checks: Record<string, boolean>) {
  localStorage.setItem(`${STORAGE_KEY}_${userId}`, JSON.stringify(checks));
}

function fmt(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function CopyField({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };
  return (
    <div className="flex items-center justify-between gap-2 py-1.5 px-3 rounded-lg bg-muted/40 text-sm">
      <div><span className="text-muted-foreground">{label} :</span> <span className="font-medium text-foreground">{value}</span></div>
      <button onClick={copy} className="text-primary hover:text-primary/80 transition-colors shrink-0" title="Copier">
        {copied ? <Check className="h-4 w-4 text-success" /> : <Copy className="h-4 w-4" />}
      </button>
    </div>
  );
}

function DocBadge({ label, ok, lien }: { label: string; ok: boolean; lien?: string }) {
  return (
    <div className="flex items-center justify-between py-1">
      <div className="flex items-center gap-2 text-sm">
        {ok ? <CheckCircle2 className="h-4 w-4 text-success shrink-0" /> : <XCircle className="h-4 w-4 text-destructive shrink-0" />}
        <span className={ok ? 'text-foreground' : 'text-muted-foreground'}>{label}</span>
      </div>
      {!ok && lien && (
        <a href={lien} className="text-xs text-primary hover:underline flex items-center gap-0.5">
          Ajouter <ArrowRight className="h-3 w-3" />
        </a>
      )}
    </div>
  );
}

type StepStatus = 'done' | 'current' | 'todo';

function TimelineIcon({ status, icon: Icon }: { status: StepStatus; icon: React.ElementType }) {
  const base = 'relative z-10 flex items-center justify-center h-10 w-10 rounded-full border-2 transition-all duration-300';
  if (status === 'done') return <div className={`${base} border-success bg-success text-success-foreground`}><Check className="h-5 w-5" /></div>;
  if (status === 'current') return <div className={`${base} border-primary bg-primary/10 text-primary ring-4 ring-primary/20`}><Icon className="h-5 w-5" /></div>;
  return <div className={`${base} border-border bg-muted text-muted-foreground`}><Icon className="h-5 w-5" /></div>;
}

export default function PasserEnLiberal() {
  usePageTitle('Passer en libéral');
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [soignant, setSoignant] = useState<any>(null);
  const [profData, setProfData] = useState<any>(null);
  const [freeTransition, setFreeTransition] = useState<any>(null);
  const [documents, setDocuments] = useState<any[]>([]);
  const [checks, setChecks] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState(false);
  const [showConfetti, setShowConfetti] = useState(false);

  useEffect(() => {
    if (!user) return;
    setChecks(getChecks(user.id));
    const load = async () => {
      const [{ data: sg }, { data: prof }, { data: ft }, { data: docs }] = await Promise.all([
        supabase.from('soignants').select('prenom, nom, profession, siret_liberal, statut_liberal, type_contrat, heures_cumulees, eligible_conversion_3200h, date_naissance, adresse_ville, numero_rpps').eq('id', user.id).single(),
        supabase.from('professions_liberal_eligible').select('profession, code_ape, libelle_urssaf, nom_ordre, ordre_obligatoire, plafond_micro').limit(20),
        supabase.rpc('fn_calculer_taux_free_transition_safe', { p_soignant_id: user.id }),
        supabase.from('documents_soignants').select('type_document, statut_verification').eq('soignant_id', user.id).is('supprime_le', null),
      ]);
      if (sg) {
        if (!estEligibleLiberal(sg.profession)) {
          navigate('/soignant/tableau-de-bord', { replace: true });
          return;
        }
        setSoignant(sg);
      }
      if (prof) {
        const match = (prof as any[]).find((p: any) => p.profession === sg?.profession);
        setProfData(match || null);
      }
      if (ft) setFreeTransition(ft);
      if (docs) setDocuments(docs);
      setLoading(false);
    };
    load();
  }, [user]);

  const toggleCheck = useCallback((key: string, val: boolean) => {
    if (!user) return;
    setChecks(prev => {
      const next = { ...prev, [key]: val };
      saveChecks(user.id, next);
      return next;
    });
  }, [user]);

  // Eligibility auto-check (step 1)
  const heures = soignant?.heures_cumulees || 0;
  const hasEnoughHours = heures >= 3200;
  const hasDocsCritiques = documents.some(d => d.type_document === 'DIPLOME' && d.statut_verification === 'VERIFIE')
    && documents.some(d => d.type_document === 'CARTE_IDENTITE' && d.statut_verification === 'VERIFIE');
  const professionEligible = !!profData;
  const step1Done = hasEnoughHours && hasDocsCritiques && professionEligible;

  // Document checks for step 3
  const hasDoc = (type: string) => documents.some(d => d.type_document === type && ['VERIFIE', 'EN_ATTENTE'].includes(d.statut_verification || ''));
  const hasRCP = hasDoc('RCP_ASSURANCE');

  // Steps completion
  const stepsCompleted = [
    step1Done,
    checks['step2'] || false,
    checks['step3'] || false,
    checks['step4'] || false,
    checks['step5'] || false,
    checks['step6'] || false,
  ];
  const completedCount = stepsCompleted.filter(Boolean).length;
  const allDone = completedCount === 6;

  useEffect(() => {
    if (allDone && !showConfetti) setShowConfetti(true);
  }, [allDone]);

  const getStatus = (idx: number): StepStatus => {
    if (stepsCompleted[idx]) return 'done';
    // First incomplete step is current
    const firstIncomplete = stepsCompleted.findIndex(s => !s);
    if (idx === firstIncomplete) return 'current';
    return 'todo';
  };

  const handleActiverLiberal = async () => {
    if (!user) return;
    setSaving(true);
    try {
      // fn_activer_liberal ne prend aucun argument — elle lit siret_liberal
      // depuis la table soignants, qui doit donc avoir été persisté avant.
      const { data, error } = await supabase.rpc('fn_activer_liberal' as any);
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      afficherNotification({ type: 'succes', message: '🎉 Profil libéral activé !' });
      setTimeout(() => navigate('/soignant/tableau-de-bord'), 2000);
    } catch (err: any) {
      capturerErreurSentry(err, 'PasserEnLiberal', 'activer_liberal');
      afficherNotification({ type: 'erreur', message: 'Une erreur est survenue. Veuillez réessayer.' });
    } finally { setSaving(false); }
  };

  const genererLettreBanque = async () => {
    const { default: jsPDF } = await import('jspdf');
    const doc = new jsPDF();
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(16);
    doc.text('Jolene', 20, 20);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(11);
    const nom = `${soignant?.prenom || ''} ${soignant?.nom || ''}`;
    const date = new Date().toLocaleDateString('fr-FR');
    doc.text(nom, 20, 35);
    doc.text(`Profession : ${profData?.libelle_urssaf || soignant?.profession || ''}`, 20, 42);
    if (soignant?.numero_rpps) doc.text(`RPPS : ${soignant.numero_rpps}`, 20, 49);
    if (soignant?.siret_liberal) doc.text(`SIRET : ${soignant.siret_liberal}`, 20, 56);
    doc.text(`${soignant?.adresse_ville || ''}`, 20, 63);
    doc.text(`Le ${date}`, 20, 78);
    doc.text('Objet : Demande d\'ouverture de compte bancaire professionnel', 20, 92);
    doc.setFontSize(10);
    const body = [
      'Madame, Monsieur,',
      '',
      `Je soussigné(e) ${nom}, exerçant la profession de ${profData?.libelle_urssaf || ''} en libéral,`,
      'vous prie de bien vouloir procéder à l\'ouverture d\'un compte bancaire dédié à mon activité',
      'professionnelle libérale.',
      '',
      'Vous trouverez ci-joint les pièces justificatives nécessaires :',
      '— Pièce d\'identité en cours de validité',
      '— Justificatif de domicile',
      '— Attestation d\'inscription RPPS',
      soignant?.siret_liberal ? `— Extrait SIRENE / SIRET : ${soignant.siret_liberal}` : '',
      '',
      'Je vous remercie par avance et reste à votre disposition.',
      '',
      'Cordialement,',
      nom,
    ].filter(Boolean);
    doc.text(body, 20, 105);
    doc.save(`lettre-banque-${nom.replace(/\s/g, '-')}.pdf`);
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  if (!profData) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="text-center py-12">
          <p className="text-lg font-semibold text-foreground mb-2">Votre profession n'est pas éligible au libéral</p>
          <button onClick={() => navigate(-1)} className="text-sm text-primary hover:underline mt-4">Retour</button>
        </div>
      </LayoutApp>
    );
  }

  const heuresPlat = freeTransition?.heures_plateforme || 0;
  const tauxPC = freeTransition?.taux_prise_en_charge || 0;
  const montantPC = freeTransition?.montant_pris_en_charge || 0;

  const STEPS = [
    { icon: ClipboardCheck, title: 'Vérifier l\'éligibilité' },
    { icon: FileText, title: 'Déclarer votre activité' },
    { icon: Building2, title: 'Inscription à l\'Ordre' },
    { icon: Heart, title: 'Conventionnement CPAM' },
    { icon: Shield, title: 'Assurance RCP' },
    { icon: Landmark, title: 'Compte bancaire pro' },
  ];

  return (
    <LayoutApp role="SOIGNANT">
      <ConfettiMini active={showConfetti} duration={3000} count={12} />

      {/* Header */}
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Rocket className="h-6 w-6 text-primary" /> Passer en libéral
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Parcours guidé en 6 étapes</p>
      </div>

      {/* Progress bar */}
      <div className="card-base mb-6">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-semibold text-foreground">{completedCount}/6 étapes complétées</span>
          <span className="text-xs text-muted-foreground">{Math.round((completedCount / 6) * 100)}%</span>
        </div>
        <Progress value={(completedCount / 6) * 100} className="h-2" />
      </div>

      {/* All done banner */}
      {allDone && (
        <div className="rounded-2xl bg-success/10 border border-success/30 p-5 mb-6 text-center animate-in fade-in slide-in-from-bottom-4 duration-500">
          <PartyPopper className="h-10 w-10 text-success mx-auto mb-3" />
          <h2 className="text-lg font-bold text-foreground mb-1">🎉 Félicitations !</h2>
          <p className="text-sm text-muted-foreground mb-4">Votre installation libérale est complète. Activez votre profil libéral ci-dessous.</p>
          <button
            onClick={handleActiverLiberal}
            disabled={saving}
            className="inline-flex items-center gap-2 px-6 py-3 rounded-xl text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 transition-colors disabled:opacity-50"
          >
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <>Activer mon statut libéral <ArrowRight className="h-4 w-4" /></>}
          </button>
        </div>
      )}

      {/* Timeline */}
      <div className="relative ml-5 pl-8 border-l-2 border-border space-y-0">
        {STEPS.map((step, idx) => {
          const status = getStatus(idx);
          return (
            <div key={idx} className="relative pb-8 last:pb-0">
              {/* Icon on the line */}
              <div className="absolute -left-[calc(1.25rem+1px)] top-0">
                <TimelineIcon status={status} icon={step.icon} />
              </div>

              <div className={`ml-4 card-base transition-all duration-300 ${status === 'current' ? 'ring-2 ring-primary/20' : ''}`}>
                <h3 className="text-sm font-bold text-foreground mb-1">
                  Étape {idx + 1} — {step.title}
                </h3>

                {/* Step 1: Eligibility */}
                {idx === 0 && (
                  <div className="space-y-2 mt-2">
                    <DocBadge label={`Heures cumulées ≥ 3 200h (${heures}h)`} ok={hasEnoughHours} lien="/soignant/parcours-3200h" />
                    <DocBadge label="Documents critiques valides (diplôme, identité)" ok={hasDocsCritiques} lien="/soignant/documents" />
                    <DocBadge label={`Profession éligible (${soignant?.profession || ''})`} ok={professionEligible} lien="/soignant/profil" />
                    {step1Done && <p className="text-xs font-semibold text-success mt-1">Éligible ✅</p>}
                    {!step1Done && <p className="text-xs text-muted-foreground mt-1">Complétez les éléments manquants pour continuer.</p>}
                  </div>
                )}

                {/* Step 2: Guichet Unique */}
                {idx === 1 && (
                  <div className="space-y-3 mt-2">
                    <p className="text-sm text-muted-foreground">Depuis 2023, la déclaration se fait en ligne sur le Guichet Unique des formalités d'entreprises.</p>
                    <a href="https://formalites.entreprises.gouv.fr" target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 transition-colors">
                      Accéder au Guichet Unique <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                    <div className="rounded-xl bg-muted/40 p-3 space-y-1.5">
                      <p className="text-xs font-semibold text-foreground mb-2">📋 Vos informations à copier-coller</p>
                      <CopyField label="Nom" value={soignant?.nom || ''} />
                      <CopyField label="Prénom" value={soignant?.prenom || ''} />
                      {soignant?.date_naissance && <CopyField label="Date de naissance" value={soignant.date_naissance} />}
                      {soignant?.adresse_ville && <CopyField label="Ville" value={soignant.adresse_ville} />}
                      <CopyField label="Profession" value={profData?.libelle_urssaf || soignant?.profession || ''} />
                      <CopyField label="Code APE" value={profData?.code_ape || '86.90D'} />
                    </div>
                    <label className="flex items-center gap-3 cursor-pointer pt-1">
                      <Checkbox checked={checks['step2'] || false} onCheckedChange={(v) => toggleCheck('step2', !!v)} />
                      <span className="text-sm text-foreground font-medium">J'ai déclaré mon activité ✅</span>
                    </label>
                  </div>
                )}

                {/* Step 3: Ordre */}
                {idx === 2 && (
                  <div className="space-y-3 mt-2">
                    <a href="https://www.ordre-infirmiers.fr" target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 transition-colors">
                      Conseil de l'Ordre <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                    <div className="space-y-1">
                      <p className="text-xs font-semibold text-foreground mb-1.5">Documents requis :</p>
                      <DocBadge label="Diplôme d'État" ok={hasDoc('DIPLOME')} lien="/soignant/documents" />
                      <DocBadge label="Pièce d'identité" ok={hasDoc('CARTE_IDENTITE')} lien="/soignant/documents" />
                      <DocBadge label="Assurance RCP" ok={hasRCP} lien="/soignant/documents" />
                      <DocBadge label="Justificatif de domicile" ok={false} />
                    </div>
                    <label className="flex items-center gap-3 cursor-pointer pt-1">
                      <Checkbox checked={checks['step3'] || false} onCheckedChange={(v) => toggleCheck('step3', !!v)} />
                      <span className="text-sm text-foreground font-medium">Inscrit à l'Ordre ✅</span>
                    </label>
                  </div>
                )}

                {/* Step 4: CPAM */}
                {idx === 3 && (
                  <div className="space-y-3 mt-2">
                    <p className="text-sm text-muted-foreground">Prenez rendez-vous avec votre CPAM.</p>
                    <a href="https://www.ameli.fr/assure/adresses-et-contacts" target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 transition-colors">
                      Trouver ma CPAM <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                    <div className="space-y-1">
                      <p className="text-xs font-semibold text-foreground mb-1.5">Documents nécessaires :</p>
                      <DocBadge label="Attestation de l'Ordre" ok={checks['step3'] || false} />
                      <DocBadge label="RPPS" ok={!!soignant?.numero_rpps} lien="/soignant/profil" />
                      <DocBadge label="SIRET" ok={!!soignant?.siret_liberal} lien="/soignant/profil" />
                      <DocBadge label="RIB professionnel" ok={false} />
                    </div>
                    <label className="flex items-center gap-3 cursor-pointer pt-1">
                      <Checkbox checked={checks['step4'] || false} onCheckedChange={(v) => toggleCheck('step4', !!v)} />
                      <span className="text-sm text-foreground font-medium">Conventionné CPAM ✅</span>
                    </label>
                  </div>
                )}

                {/* Step 5: RCP */}
                {idx === 4 && (
                  <div className="space-y-3 mt-2">
                    <div className="flex flex-wrap gap-2">
                      {[
                        { label: 'MACSF', url: 'https://www.macsf.fr' },
                        { label: 'La Médicale', url: 'https://www.lamedicale.fr' },
                        { label: 'GPM Assurances', url: 'https://www.gpm.fr' },
                      ].map(a => (
                        <a key={a.label} href={a.url} target="_blank" rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-semibold border border-border text-foreground hover:bg-muted transition-colors">
                          {a.label} <ExternalLink className="h-3 w-3" />
                        </a>
                      ))}
                    </div>
                    <div className="rounded-xl bg-muted/40 p-3 space-y-1">
                      <p className="text-xs font-semibold text-foreground mb-1.5">Infos à communiquer :</p>
                      <CopyField label="Nom" value={`${soignant?.prenom || ''} ${soignant?.nom || ''}`} />
                      <CopyField label="Profession" value={profData?.libelle_urssaf || ''} />
                      {soignant?.numero_rpps && <CopyField label="RPPS" value={soignant.numero_rpps} />}
                    </div>
                    {hasRCP && <p className="text-xs font-semibold text-success">RCP valide ✅ (déjà dans votre coffre-fort)</p>}
                    <label className="flex items-center gap-3 cursor-pointer pt-1">
                      <Checkbox checked={checks['step5'] || false} onCheckedChange={(v) => toggleCheck('step5', !!v)} />
                      <span className="text-sm text-foreground font-medium">RCP souscrite ✅</span>
                    </label>
                  </div>
                )}

                {/* Step 6: Banque */}
                {idx === 5 && (
                  <div className="space-y-3 mt-2">
                    <p className="text-sm text-muted-foreground">Ouvrez un compte dédié à votre activité libérale.</p>
                    <button
                      onClick={async () => { await genererLettreBanque(); }}
                      className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold border border-border text-foreground hover:bg-muted transition-colors"
                    >
                      📄 Télécharger la lettre type (PDF)
                    </button>
                    <label className="flex items-center gap-3 cursor-pointer pt-1">
                      <Checkbox checked={checks['step6'] || false} onCheckedChange={(v) => toggleCheck('step6', !!v)} />
                      <span className="text-sm text-foreground font-medium">Compte pro ouvert ✅</span>
                    </label>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Free Transition section */}
      <div className="rounded-2xl bg-gradient-to-r from-rose-light to-primary/5 dark:from-rose/10 dark:to-primary/5 border border-rose/20 p-5 mt-8">
        <h2 className="text-base font-bold text-foreground mb-3">🎁 Votre Free Transition</h2>
        <div className="space-y-2 text-sm">
          <p className="text-muted-foreground">Heures sur Jolene : <span className="font-bold text-foreground">{heuresPlat}h</span></p>
          <p className="text-muted-foreground">Taux de prise en charge : <span className="font-bold text-primary">{tauxPC}%</span></p>
          <p className="text-muted-foreground">
            Jolene prend en charge <span className="font-bold text-primary">{fmt(montantPC)}</span> de vos frais d'installation :
          </p>
          <div className="space-y-1 mt-2">
            <p className="text-xs">{tauxPC >= 75 ? '✅' : '⚠️'} Comptabilité Indy {tauxPC >= 75 ? '(6 mois offerts)' : `(non couvert à ${tauxPC}%)`}</p>
            <p className="text-xs">{tauxPC >= 75 ? '✅' : '⚠️'} Banque pro Qonto {tauxPC >= 75 ? '(6 mois offerts)' : `(non couverte à ${tauxPC}%)`}</p>
            <p className="text-xs">{tauxPC >= 50 ? '✅' : '⚠️'} Assurance RCP {tauxPC >= 50 ? '(3 mois offerts)' : `(non couverte à ${tauxPC}%)`}</p>
          </div>
          {heuresPlat < 3200 && (
            <p className="text-xs text-primary mt-2">💡 Encore {3200 - heuresPlat}h pour atteindre 100% de prise en charge !</p>
          )}
        </div>
        <div className="mt-4">
          <JaugeProgression
            valeur={heuresPlat}
            max={3200}
            marqueurs={[800, 1600, 2400, 3200]}
            couleurBarre="bg-gradient-to-r from-rose to-primary"
            couleurFond="bg-primary/10"
          />
          <div className="flex justify-between text-[10px] text-muted-foreground mt-1">
            <span>0h</span><span>800h (25%)</span><span>1600h (50%)</span><span>2400h (75%)</span><span>3200h (100%)</span>
          </div>
        </div>
      </div>
    </LayoutApp>
  );
}
