import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Rocket, ExternalLink, Download, Check, Circle, Loader2, PartyPopper, ClipboardList } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { JaugeProgression } from '@/components/JaugeProgression';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { Checkbox } from '@/components/ui/checkbox';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import ImportHeuresExternes from '@/components/ImportHeuresExternes';
import { extraireMessageErreur } from '@/lib/erreurs';

function fmt(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function PasserEnLiberal() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [soignant, setSoignant] = useState<any>(null);
  const [profData, setProfData] = useState<any>(null);
  const [freeTransition, setFreeTransition] = useState<any>(null);
  const [siret, setSiret] = useState('');
  const [saving, setSaving] = useState(false);
  const [showConfetti, setShowConfetti] = useState(false);
  const [heuresExternes, setHeuresExternes] = useState<any[]>([]);
  const [assujettiTVA, setAssujettiTVA] = useState(false);
  const [numeroTVA, setNumeroTVA] = useState('');

  const [checklist, setChecklist] = useState({
    siret: false, cpam: false, ordre: false, rcp: false, banque: false, compta: false,
  });

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const [{ data: sg }, { data: prof }, { data: ft }, { data: he }] = await Promise.all([
        supabase.from('soignants').select('prenom, nom, profession, siret_liberal, statut_liberal, type_contrat, heures_cumulees, eligible_conversion_3200h, assujetti_tva, numero_tva').eq('id', user.id).single(),
        supabase.from('professions_liberal_eligible').select('profession, code_ape, libelle_urssaf, nom_ordre, ordre_obligatoire, plafond_micro').limit(20),
        supabase.rpc('fn_calculer_taux_free_transition_safe', { p_soignant_id: user.id }),
        supabase.from('heures_externes').select('id, soignant_id, employeur_nom, employeur_type, heures_declarees, date_debut, date_fin, statut, motif_rejet, type_preuve').eq('soignant_id', user.id).order('date_debut', { ascending: false }),
      ]);
      if (sg) {
        setSoignant(sg);
        setSiret(sg.siret_liberal || '');
        setAssujettiTVA(sg.assujetti_tva || false);
        setNumeroTVA(sg.numero_tva || '');
      }
      if (prof) {
        const match = (prof as any[]).find((p: any) => p.profession === sg?.profession);
        setProfData(match || null);
      }
      if (ft) setFreeTransition(ft);
      if (he) setHeuresExternes(he);

      // Audit
      supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: null, p_details: { page: 'passer_en_liberal' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });

      setLoading(false);
    };
    load();
  }, [user]);

  const handleSaveSiret = async () => {
    if (!user || siret.length !== 14) return;
    const { data, error } = await supabase.rpc('fn_enregistrer_siret_liberal' as any, {
      p_siret: siret,
    });
    if (error || data?.error) {
      afficherNotification({ type: 'erreur', message: data?.error || 'Erreur lors de l\'enregistrement du SIRET' });
      return;
    }
    setChecklist(prev => ({ ...prev, siret: true }));
    afficherNotification({ type: 'succes', message: 'SIRET enregistré !' });
  };

  const handleActiverLiberal = async () => {
    if (!user || !profData) return;
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('fn_activer_liberal' as any, {
        p_siret: siret,
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      setShowConfetti(true);
      afficherNotification({ type: 'succes', message: '🎉 Profil libéral activé avec succès !' });
      setTimeout(() => navigate('/soignant/tableau-de-bord'), 3000);
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err.message || 'Erreur lors de l\'activation' });
    } finally {
      setSaving(false);
    }
  };

  const handleDownloadGuide = () => {
    supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT',
      p_action: 'DONNEES_PERSO_EXPORT',
      p_type_ressource: 'soignant', p_id_ressource: user!.id,
      p_cle_s3: null, p_details: { type: 'guide_liberal_pdf' },
      p_ip: null, p_navigateur: navigator.userAgent,
    });
    window.print();
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  if (!profData) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="text-center py-12">
          <p className="text-lg font-semibold text-foreground mb-2">Votre profession n'est pas éligible au libéral</p>
          <p className="text-sm text-muted-foreground">Les professions éligibles sont : IDE, IBODE, IADE, Sage-Femme, Kiné, Médecin, Diététicien, Ergothérapeute, Psychomotricien, Orthophoniste.</p>
          <button onClick={() => navigate(-1)} className="btn-secondary mt-4">Retour</button>
        </div>
      </LayoutApp>
    );
  }

  const heures = soignant?.heures_plateforme || 0;
  const tauxPC = freeTransition?.taux_prise_en_charge || 0;
  const montantPC = freeTransition?.montant_pris_en_charge || 0;
  const canActivate = siret.length === 14;

  return (
    <LayoutApp role="SOIGNANT">
      {showConfetti && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <div className="text-center animate-in fade-in zoom-in">
            <PartyPopper className="h-20 w-20 text-primary mx-auto mb-4" />
            <h2 className="text-2xl font-bold text-foreground mb-2">🎉 Félicitations !</h2>
            <p className="text-muted-foreground">Votre profil libéral est maintenant actif.</p>
            <p className="text-sm text-muted-foreground mt-2">Redirection en cours...</p>
          </div>
        </div>
      )}

      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Rocket className="h-6 w-6 text-primary" /> Passer en libéral
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Module de conversion en 3 étapes</p>
      </div>

      {/* Section 0: Heures d'expérience */}
      <div className="card-base mb-6">
        <h2 className="text-base font-bold text-foreground mb-3 flex items-center gap-2"><ClipboardList className="h-5 w-5 text-primary" /> Mes heures d'expérience</h2>
        <div className="space-y-2 text-sm">
          <div className="flex justify-between"><span className="text-muted-foreground">Heures sur Soin Direct :</span><span className="font-bold text-foreground">{soignant?.heures_plateforme || 0}h ✅</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Heures externes validées :</span><span className="font-bold text-foreground">{heuresExternes.filter(h => h.statut === 'VALIDEE').reduce((s: number, h: any) => s + (h.heures_declarees || 0), 0)}h</span></div>
          <div className="border-t border-border pt-2 flex justify-between"><span className="font-bold text-foreground">TOTAL :</span><span className="font-bold text-primary">{soignant?.heures_cumulees || 0}h</span></div>
          {(soignant?.heures_cumulees || 0) < 3200 && <p className="text-xs text-primary">💡 Encore {3200 - (soignant?.heures_cumulees || 0)}h pour le palier 3 200h (100%)</p>}
        </div>
        <div className="mt-3">
          <ImportHeuresExternes onDone={() => { supabase.from('heures_externes').select('id, soignant_id, employeur_nom, employeur_type, heures_declarees, date_debut, date_fin, statut, motif_rejet, type_preuve').eq('soignant_id', user!.id).order('date_debut', { ascending: false }).then(({ data }) => { if (data) setHeuresExternes(data); }); }} />
        </div>
        {heuresExternes.length > 0 && (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-xs">
              <thead><tr className="border-b border-border text-muted-foreground"><th className="pb-1 text-left">Employeur</th><th className="pb-1 text-left">Période</th><th className="pb-1 text-right">Heures</th><th className="pb-1 text-right">Statut</th></tr></thead>
              <tbody>{heuresExternes.map((h: any) => (
                <tr key={h.id} className="border-b border-border/50">
                  <td className="py-1.5">{h.employeur_nom}</td>
                  <td className="py-1.5 text-muted-foreground">{h.date_debut} → {h.date_fin}</td>
                  <td className="py-1.5 text-right">{h.heures_declarees}h</td>
                  <td className="py-1.5 text-right">{h.statut === 'VALIDEE' ? '✅' : h.statut === 'REJETEE' ? '❌' : '⏳'}</td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </div>

      {/* Section 1: Free Transition */}
      <div className="rounded-2xl bg-gradient-to-r from-purple-50 to-primary/5 border border-purple-200 p-5 mb-6">
        <h2 className="text-base font-bold text-foreground mb-3">🎁 Votre Free Transition</h2>
        <div className="space-y-2 text-sm">
          <p className="text-muted-foreground">Heures sur Soin Direct : <span className="font-bold text-foreground">{heures}h</span></p>
          <p className="text-muted-foreground">Taux de prise en charge : <span className="font-bold text-primary">{tauxPC}%</span></p>
          <p className="text-muted-foreground">
            Soin Direct prend en charge <span className="font-bold text-primary">{fmt(montantPC)}</span> de vos frais d'installation :
          </p>
          <div className="space-y-1 mt-2">
            <p className="text-xs">{tauxPC >= 75 ? '✅' : '⚠️'} Comptabilité Indy {tauxPC >= 75 ? '(6 mois offerts)' : `(non couvert à ${tauxPC}%)`}</p>
            <p className="text-xs">{tauxPC >= 75 ? '✅' : '⚠️'} Banque pro Qonto {tauxPC >= 75 ? '(6 mois offerts)' : `(non couverte à ${tauxPC}%)`}</p>
            <p className="text-xs">{tauxPC >= 50 ? '✅' : '⚠️'} Assurance RCP {tauxPC >= 50 ? '(3 mois offerts)' : `(non couverte à ${tauxPC}%)`}</p>
          </div>
          {heures < 3200 && (
            <p className="text-xs text-primary mt-2">💡 Encore {3200 - heures}h pour atteindre 100% de prise en charge !</p>
          )}
        </div>

        <div className="mt-4">
          <JaugeProgression
            valeur={heures}
            max={3200}
            marqueurs={[800, 1600, 2400, 3200]}
            couleurBarre="bg-gradient-to-r from-primary to-primary-dark"
            couleurFond="bg-primary/10"
          />
          <div className="flex justify-between text-[10px] text-muted-foreground mt-1">
            <span>0h</span><span>800h (25%)</span><span>1600h (50%)</span><span>2400h (75%)</span><span>3200h (100%)</span>
          </div>
        </div>
      </div>

      {/* Section 2: Guide étape par étape */}
      <div className="mb-6">
        <h2 className="text-base font-bold text-foreground mb-3">📋 Guide étape par étape</h2>
        <Accordion type="single" collapsible className="space-y-2">
          <AccordionItem value="etape1" className="card-base !p-0 overflow-hidden border">
            <AccordionTrigger className="px-4 py-3 hover:no-underline">
              <span className="text-sm font-semibold">Étape 1 : Créer votre statut auto-entrepreneur</span>
            </AccordionTrigger>
            <AccordionContent className="px-4 pb-4 space-y-3">
              <p className="text-sm text-muted-foreground">Rendez-vous sur autoentrepreneur.urssaf.fr pour créer votre statut.</p>
              <div className="bg-muted/30 rounded-xl p-3 space-y-1 text-xs">
                <p><span className="font-medium">Activité :</span> {profData.libelle_urssaf}</p>
                <p><span className="font-medium">Code APE :</span> {profData.code_ape}</p>
                <p><span className="font-medium">Catégorie :</span> BNC</p>
              </div>
              <div className="flex gap-2">
                <a href="https://autoentrepreneur.urssaf.fr" target="_blank" rel="noopener noreferrer" className="btn-primary text-xs flex items-center gap-1">
                  Ouvrir le site URSSAF <ExternalLink className="h-3.5 w-3.5" />
                </a>
                <button onClick={handleDownloadGuide} className="btn-secondary text-xs flex items-center gap-1">
                  <Download className="h-3.5 w-3.5" /> Télécharger le guide PDF
                </button>
              </div>
            </AccordionContent>
          </AccordionItem>

          <AccordionItem value="etape2" className="card-base !p-0 overflow-hidden border">
            <AccordionTrigger className="px-4 py-3 hover:no-underline">
              <span className="text-sm font-semibold">Étape 2 : Saisir votre SIRET</span>
            </AccordionTrigger>
            <AccordionContent className="px-4 pb-4 space-y-3">
              <p className="text-sm text-muted-foreground">Vous le recevrez par courrier de l'URSSAF sous 1 à 4 semaines.</p>
              <div className="flex gap-2">
                <input
                  value={siret}
                  onChange={e => setSiret(e.target.value.replace(/\D/g, '').slice(0, 14))}
                  placeholder="14 chiffres"
                  className="input-base flex-1"
                />
                <button onClick={handleSaveSiret} disabled={siret.length !== 14} className="btn-primary text-sm disabled:opacity-50">Enregistrer</button>
              </div>
              {siret && siret.length !== 14 && <p className="text-xs text-destructive">Le SIRET doit contenir exactement 14 chiffres</p>}
            </AccordionContent>
          </AccordionItem>

          <AccordionItem value="etape3" className="card-base !p-0 overflow-hidden border">
            <AccordionTrigger className="px-4 py-3 hover:no-underline">
              <span className="text-sm font-semibold">Étape 3 : S'affilier à la CPAM</span>
            </AccordionTrigger>
            <AccordionContent className="px-4 pb-4 space-y-3">
              <p className="text-sm text-muted-foreground">En tant que libéral(e), vous devez vous affilier à la CPAM de votre lieu d'exercice.</p>
              <a href="https://www.ameli.fr" target="_blank" rel="noopener noreferrer" className="btn-primary text-xs inline-flex items-center gap-1">
                Ouvrir ameli.fr <ExternalLink className="h-3.5 w-3.5" />
              </a>
            </AccordionContent>
          </AccordionItem>

          {profData.ordre_obligatoire && (
            <AccordionItem value="etape4" className="card-base !p-0 overflow-hidden border">
              <AccordionTrigger className="px-4 py-3 hover:no-underline">
                <span className="text-sm font-semibold">Étape 4 : S'inscrire à l'Ordre</span>
              </AccordionTrigger>
              <AccordionContent className="px-4 pb-4 space-y-3">
                <p className="text-sm text-muted-foreground">L'inscription au {profData.nom_ordre || "Conseil de l'Ordre"} est obligatoire pour exercer en libéral.</p>
                <a href="https://www.conseil-national.medecin.fr/" target="_blank" rel="noopener noreferrer" className="btn-primary text-xs inline-flex items-center gap-1">
                  Ouvrir le site de l'Ordre <ExternalLink className="h-3.5 w-3.5" />
                </a>
              </AccordionContent>
            </AccordionItem>
          )}

          <AccordionItem value="etape5" className="card-base !p-0 overflow-hidden border">
            <AccordionTrigger className="px-4 py-3 hover:no-underline">
              <span className="text-sm font-semibold">Étape 5 : Souscrire une assurance RCP</span>
            </AccordionTrigger>
            <AccordionContent className="px-4 pb-4 space-y-3">
              <p className="text-sm text-muted-foreground">L'assurance RCP est OBLIGATOIRE pour exercer en libéral.</p>
              {tauxPC >= 50 && <p className="text-xs text-primary font-medium">🎁 Soin Direct prend en charge 3 mois</p>}
              <a href="https://www.macsf.fr" target="_blank" rel="noopener noreferrer" className="btn-primary text-xs inline-flex items-center gap-1">
                Obtenir un devis MACSF <ExternalLink className="h-3.5 w-3.5" />
              </a>
            </AccordionContent>
          </AccordionItem>

          <AccordionItem value="etape6" className="card-base !p-0 overflow-hidden border">
            <AccordionTrigger className="px-4 py-3 hover:no-underline">
              <span className="text-sm font-semibold">Étape 6 : Ouvrir un compte bancaire pro</span>
            </AccordionTrigger>
            <AccordionContent className="px-4 pb-4 space-y-3">
              <p className="text-sm text-muted-foreground">Obligatoire dès 10 000€ de chiffre d'affaires annuel.</p>
              {tauxPC >= 75 && <p className="text-xs text-primary font-medium">🎁 Soin Direct offre 6 mois de Qonto</p>}
              <a href="https://qonto.com" target="_blank" rel="noopener noreferrer" className="btn-primary text-xs inline-flex items-center gap-1">
                Ouvrir un compte Qonto <ExternalLink className="h-3.5 w-3.5" />
              </a>
            </AccordionContent>
          </AccordionItem>

          <AccordionItem value="etape7" className="card-base !p-0 overflow-hidden border">
            <AccordionTrigger className="px-4 py-3 hover:no-underline">
              <span className="text-sm font-semibold">Étape 7 : Configurer la comptabilité</span>
            </AccordionTrigger>
            <AccordionContent className="px-4 pb-4 space-y-3">
              <p className="text-sm text-muted-foreground">Un logiciel de comptabilité spécialisé libéral simplifie vos déclarations.</p>
              {tauxPC >= 75 && <p className="text-xs text-primary font-medium">🎁 Soin Direct offre 6 mois d'Indy</p>}
              <a href="https://www.indy.fr" target="_blank" rel="noopener noreferrer" className="btn-primary text-xs inline-flex items-center gap-1">
                Créer mon compte Indy <ExternalLink className="h-3.5 w-3.5" />
              </a>
            </AccordionContent>
          </AccordionItem>
        </Accordion>
      </div>

      {/* Section 3: Checklist */}
      <div className="card-base mb-6">
        <h2 className="text-base font-bold text-foreground mb-3">✅ Checklist de finalisation</h2>
        <div className="space-y-3">
          {[
            { key: 'siret', label: 'SIRET reçu et saisi', auto: siret.length === 14 },
            { key: 'cpam', label: 'CPAM affilié(e)' },
            ...(profData.ordre_obligatoire ? [{ key: 'ordre', label: 'Ordre inscrit(e)' }] : []),
            { key: 'rcp', label: 'RCP souscrite' },
            { key: 'banque', label: 'Banque pro ouverte' },
            { key: 'compta', label: 'Comptabilité configurée' },
          ].map((item: any) => (
            <label key={item.key} className="flex items-center gap-3 cursor-pointer">
              <Checkbox
                checked={item.auto || (checklist as any)[item.key]}
                onCheckedChange={(val) => setChecklist(prev => ({ ...prev, [item.key]: !!val }))}
                disabled={item.auto}
              />
              <span className="text-sm text-foreground">{item.label}</span>
            </label>
          ))}
        </div>
      </div>

      {/* D1: TVA libéral */}
      <div className="card-base mb-6">
        <h2 className="text-base font-bold text-foreground mb-3">🧾 TVA</h2>
        <p className="text-sm text-muted-foreground mb-3">Êtes-vous assujetti à la TVA ? (Si votre CA dépasse 36 800€/an)</p>
        <div className="flex items-center gap-3 mb-3">
          <label className="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" checked={assujettiTVA} onChange={e => setAssujettiTVA(e.target.checked)} className="h-4 w-4 rounded border-border accent-primary" />
            <span className="text-sm text-foreground">{assujettiTVA ? 'Oui, je suis assujetti à la TVA' : 'Non, franchise en base de TVA'}</span>
          </label>
        </div>
        {assujettiTVA && (
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Numéro de TVA intracommunautaire</label>
            <input value={numeroTVA} onChange={e => setNumeroTVA(e.target.value.toUpperCase().slice(0, 15))} placeholder="FR XX XXXXXXXXX" className="input-base" />
          </div>
        )}
        <button
          type="button"
          onClick={async () => {
            const { data, error } = await supabase.rpc('fn_modifier_tva_liberal' as any, {
              p_assujetti_tva: assujettiTVA,
              p_numero_tva: assujettiTVA ? numeroTVA || null : null,
            });
            if (error) {
              afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
            } else if (data?.error) {
              afficherNotification({ type: 'erreur', message: data.error });
            } else {
              afficherNotification({ type: 'succes', message: 'TVA mise à jour.' });
            }
          }}
          className="btn-secondary text-xs mt-3"
        >
          Enregistrer TVA
        </button>
      </div>

      {/* Bouton final */}
      <button
        onClick={handleActiverLiberal}
        disabled={!canActivate || saving}
        className="btn-primary w-full py-4 text-base disabled:opacity-50"
      >
        {saving ? <Loader2 className="h-5 w-5 animate-spin mx-auto" /> : '✅ Activer mon profil libéral'}
      </button>
      {!canActivate && <p className="text-xs text-muted-foreground text-center mt-2">Saisissez votre SIRET pour activer votre profil libéral</p>}

      {/* Print styles for guide PDF */}
      <div className="hidden print:block">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold">Félicitations {soignant?.prenom} !</h1>
          <p className="text-lg mt-2">Votre guide pour devenir {profData?.libelle_urssaf} libéral(e)</p>
          <p className="text-sm text-muted-foreground mt-1">Généré par Soin Direct le {new Date().toLocaleDateString('fr-FR')}</p>
        </div>
        <div className="space-y-6">
          <div>
            <h2 className="text-lg font-bold">1. Créer votre statut auto-entrepreneur</h2>
            <p>Site : autoentrepreneur.urssaf.fr</p>
            <p>Activité : {profData?.libelle_urssaf}</p>
            <p>Code APE : {profData?.code_ape}</p>
            <p>Catégorie : BNC</p>
          </div>
          <div>
            <h2 className="text-lg font-bold">2. Attendre votre SIRET</h2>
            <p>Vous recevrez votre numéro SIRET par courrier sous 1 à 4 semaines.</p>
          </div>
          <div>
            <h2 className="text-lg font-bold">3. S'affilier à la CPAM</h2>
            <p>Site : ameli.fr — Affiliez-vous à la CPAM de votre lieu d'exercice.</p>
          </div>
          {profData?.ordre_obligatoire && (
            <div>
              <h2 className="text-lg font-bold">4. S'inscrire à l'Ordre</h2>
              <p>L'inscription au {profData.nom_ordre} est obligatoire.</p>
            </div>
          )}
          <div>
            <h2 className="text-lg font-bold">5. Souscrire une assurance RCP</h2>
            <p>L'assurance RCP est OBLIGATOIRE pour exercer en libéral.</p>
          </div>
          <div>
            <h2 className="text-lg font-bold">6. Banque pro + Comptabilité</h2>
            <p>Ouvrez un compte pro et configurez votre comptabilité.</p>
          </div>
        </div>
      </div>
    </LayoutApp>
  );
}
