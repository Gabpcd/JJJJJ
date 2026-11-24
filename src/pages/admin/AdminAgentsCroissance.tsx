import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AlertTriangle, Bot, Copy, ExternalLink, Filter, Mail, Phone, PlayCircle, RefreshCw, Send, ShieldCheck, TrendingUp, X } from 'lucide-react';
import { toast } from 'sonner';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { AdminPageHeader } from '@/components/admin/AdminPageHeader';
import { AdminTabsList } from '@/components/admin/AdminTabs';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { Tabs, TabsContent, TabsTrigger } from '@/components/ui/tabs';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { supabase } from '@/integrations/supabase/client';
import {
  AGENTS,
  LIBELLE_CANAL,
  RESULTATS_APPEL,
  actionsPossibles,
  alerteCibles,
  estAppel,
  estEmail,
  etapesEtablissements,
  etapesSoignants,
  goulot,
  groupesSuggeres,
  libelleResultatAppel,
  libelleStatut,
  lienGmail,
  lienTel,
  lireCibles,
  lirePassage,
  raisonsCible,
  resumeAppels,
  resumeCibles,
  sourceFiche,
  telephoneFiche,
  type ActionBrouillon,
  type AgentCroissance,
  type BrouillonCroissance,
  type CiblesProspection,
  type PassageProspection,
  type EntonnoirCroissance,
  type EtapeEntonnoir,
  type ResultatAppel,
} from '@/lib/agentsCroissance';

type Vue = 'file' | 'entonnoir' | 'agents';
type FiltreAgent = AgentCroissance | 'TOUS';

interface Execution {
  id: number;
  agent: string;
  declencheur: string;
  debut_le: string;
  brouillons_crees: number;
  erreur: string | null;
  details?: Record<string, unknown> | null;
}

interface RapportCibles {
  le: string;
  cibles: CiblesProspection;
  passage: PassageProspection | null;
}

/** Durée pendant laquelle le lien d'appel direct reste affiché après une revérification réussie. */
const FENETRE_APPEL_MS = 2 * 60 * 1000;

interface Planification {
  actif: boolean;
  pg_cron: boolean;
  jobs: Array<{ jobname: string; schedule: string; active: boolean }>;
}

interface RapportHebdo {
  semaine_debut: string;
  donnees: EntonnoirCroissance;
}

const db = supabase as unknown as {
  from: (t: string) => any;
  rpc: (f: string, a?: Record<string, unknown>) => Promise<{ data: any; error: { message: string } | null }>;
};

const fmtDate = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' }) : '—';

function CarteBrouillon({ b, onChange }: { b: BrouillonCroissance; onChange: () => void }) {
  const [sujet, setSujet] = useState(b.sujet ?? '');
  const [corps, setCorps] = useState(b.corps);
  const [enCours, setEnCours] = useState<ActionBrouillon | null>(null);
  const [resultatEnCours, setResultatEnCours] = useState<ResultatAppel | null>(null);
  // Numéro que le serveur vient de revérifier : le lien d'appel direct n'existe que pendant deux minutes.
  const [numeroVerifie, setNumeroVerifie] = useState<string | null>(null);
  const [verification, setVerification] = useState(false);
  const derniereReponse = useRef<{ telephone?: string | null } | null>(null);
  useEffect(() => {
    if (!numeroVerifie) return undefined;
    const minuterie = window.setTimeout(() => setNumeroVerifie(null), FENETRE_APPEL_MS);
    return () => window.clearTimeout(minuterie);
  }, [numeroVerifie]);
  const modifie = sujet !== (b.sujet ?? '') || corps !== b.corps;
  const actions = actionsPossibles(b.statut);
  const raisons = raisonsCible(b);
  const groupes = groupesSuggeres(b.contexte);
  const appel = estAppel(b);
  const numero = appel ? telephoneFiche(b.contexte) : null;
  const source = appel ? sourceFiche(b.contexte) : null;
  const resultatNote = appel ? libelleResultatAppel(b.contexte?.resultat_appel) : null;

  const decider = async (action: ActionBrouillon, motif?: string) => {
    setEnCours(action);
    const { data, error } = await db.rpc('fn_admin_growth_brouillon_decider', {
      p_id: b.id,
      p_action: action,
      p_sujet: action === 'MODIFIER' || action === 'VALIDER' ? sujet : null,
      p_corps: action === 'MODIFIER' || action === 'VALIDER' ? corps : null,
      p_motif: motif ?? null,
    });
    setEnCours(null);
    if (error) {
      toast.error(error.message);
      return false;
    }
    if (data?.success === false) {
      toast.error(data.raison ?? 'Brouillon rejeté');
      onChange();
      return false;
    }
    derniereReponse.current = data ?? null;
    onChange();
    return true;
  };

  // Demande d'appel : la fiche est revérifiée côté serveur (opposition, cible passée au CRM,
  // numéro modifié) juste avant, puis le composeur s'ouvre sur le numéro que le serveur renvoie.
  // Rien n'est composé à la place de la fondatrice : elle confirme l'appel sur son téléphone.
  const appeler = async () => {
    setVerification(true);
    const ok = await decider('VALIDER');
    setVerification(false);
    if (!ok) { setNumeroVerifie(null); return; }
    const verifie = derniereReponse.current?.telephone ?? numero;
    const lien = lienTel(verifie);
    if (!lien) { toast.error('Numéro incomplet : appel impossible depuis cette fiche.'); return; }
    setNumeroVerifie(verifie ?? null);
    window.open(lien, '_self');
  };

  const validerEtOuvrir = async () => {
    const ok = await decider('VALIDER');
    if (!ok) return;
    if (appel) {
      // Aucun appel n'est lancé : le numéro devient un lien que la fondatrice touche elle-même.
      toast.success('Fiche validée. Appelez, puis notez le résultat de l’appel.');
    } else if (estEmail(b) && b.destinataire_email) {
      window.open(lienGmail(b.destinataire_email, sujet, corps), '_blank', 'noopener');
      toast.success('Validé. Envoyez depuis Gmail, puis cliquez sur « J’ai envoyé ».');
    } else {
      try {
        await navigator.clipboard.writeText(corps);
        toast.success('Validé et copié. Publiez-le, puis cliquez sur « J’ai publié ».');
      } catch {
        toast.success('Validé. Copiez le texte, publiez-le, puis cliquez sur « J’ai publié ».');
      }
    }
  };

  const rouvrir = async () => {
    if (estEmail(b) && b.destinataire_email) {
      // Revalider revérifie l'opposition (STOP) et les préférences avant d'ouvrir Gmail.
      const ok = await decider('VALIDER');
      if (!ok) return;
      window.open(lienGmail(b.destinataire_email, sujet, corps), '_blank', 'noopener');
    } else {
      try {
        await navigator.clipboard.writeText(corps);
        toast.success('Texte copié');
      } catch {
        toast.error('Copie impossible : sélectionnez le texte manuellement.');
      }
    }
  };

  const rejeter = async () => {
    const motif = window.prompt('Motif du rejet (facultatif)');
    if (motif === null) return; // « Annuler » ne rejette pas.
    if (await decider('REJETER', motif)) toast.success(appel ? 'Fiche d’appel écartée' : 'Brouillon rejeté');
  };

  // Constat d'appel : le résultat part dans p_motif, le serveur alimente le CRM existant.
  const noterAppel = async (resultat: (typeof RESULTATS_APPEL)[number]) => {
    if (resultat.definitif
      && !window.confirm(`${resultat.libelle} : ne plus jamais solliciter ${b.destinataire_nom ?? 'cet établissement'}, par téléphone comme par email ?`)) return;
    setResultatEnCours(resultat.code);
    const ok = await decider('MARQUER_ENVOYE', resultat.code);
    setResultatEnCours(null);
    if (!ok) return;
    toast.success(resultat.definitif
      ? 'Appel noté. Cet établissement ne sera plus sollicité.'
      : 'Appel noté dans le CRM. La suite est dans Prospects, « Actions du jour ».');
  };

  return (
    <CardY2K hoverLift={false} data-testid="brouillon-croissance">
      <CardY2KContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <BadgeY2K variant="info" size="sm">{AGENTS[b.agent].libelle}</BadgeY2K>
          <BadgeY2K variant="premium" size="sm">{LIBELLE_CANAL[b.canal]}</BadgeY2K>
          <BadgeY2K variant={b.statut === 'VALIDE' ? 'warning' : b.statut === 'ENVOYE' ? 'success' : b.statut === 'BROUILLON' ? 'info' : 'error'} size="sm">
            {libelleStatut(b)}
          </BadgeY2K>
          {b.sequence_etape ? <span className="text-xs text-muted-foreground">Étape {b.sequence_etape}/3</span> : null}
          <span className="ml-auto text-xs text-muted-foreground">Créé le {fmtDate(b.cree_le)}</span>
        </div>

        <div className="min-w-0">
          <p className="font-semibold text-foreground break-words">
            {b.destinataire_nom || (b.departement ? `Département ${b.departement}` : 'Public')}
            {b.profession ? ` · ${b.profession}` : ''}
          </p>
          {b.destinataire_email ? (
            <p className="text-sm text-muted-foreground break-all">{b.destinataire_email}</p>
          ) : null}
          {numero ? (
            <p className="text-sm text-muted-foreground">
              Téléphone : <span className="font-medium tabular-nums text-foreground">{numero}</span>
            </p>
          ) : null}
          {source ? <p className="text-xs text-muted-foreground">Source du numéro : {source}</p> : null}
          {raisons.length > 0 ? (
            <p className="mt-1 text-xs text-muted-foreground">Pourquoi : {raisons.join(' · ')}</p>
          ) : null}
        </div>

        {estEmail(b) ? (
          <div className="space-y-1">
            <label htmlFor={`sujet-${b.id}`} className="text-xs font-medium text-muted-foreground">Objet</label>
            <Input
              id={`sujet-${b.id}`}
              value={sujet}
              onChange={(e) => setSujet(e.target.value)}
              disabled={actions.length === 0}
              className="text-base md:text-sm"
            />
          </div>
        ) : null}
        <div className="space-y-1">
          <label htmlFor={`corps-${b.id}`} className="text-xs font-medium text-muted-foreground">
            {estEmail(b) ? 'Message' : appel ? 'Script d’appel' : 'Texte du post'}
          </label>
          <Textarea
            id={`corps-${b.id}`}
            value={corps}
            onChange={(e) => setCorps(e.target.value)}
            disabled={actions.length === 0}
            rows={estEmail(b) || appel ? 12 : 7}
            className="text-base md:text-sm font-normal"
          />
        </div>

        {groupes.length > 0 ? (
          <div className="text-xs text-muted-foreground">
            <p className="font-medium">Groupes suggérés (publication manuelle) :</p>
            <ul className="mt-1 space-y-1">
              {groupes.map((g) => (
                <li key={g.nom} className="break-words">
                  {g.url ? (
                    <a href={g.url} target="_blank" rel="noopener noreferrer" className="text-primary underline underline-offset-2">
                      {g.nom}
                    </a>
                  ) : g.nom}
                  {g.membres ? ` · ${g.membres.toLocaleString('fr-FR')} membres` : ''}
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {b.motif_rejet ? <p className="text-xs text-destructive">Motif : {b.motif_rejet}</p> : null}
        {resultatNote ? <p className="text-xs text-muted-foreground">Résultat de l’appel : {resultatNote}</p> : null}

        {actions.length > 0 ? (
          <div className="flex flex-wrap gap-2 pt-1">
            {b.statut === 'BROUILLON' ? (
              <BoutonY2K
                size="sm"
                onClick={validerEtOuvrir}
                loading={enCours === 'VALIDER'}
                iconeGauche={appel ? <Phone className="h-4 w-4" /> : estEmail(b) ? <Mail className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              >
                {appel ? 'Valider la fiche' : estEmail(b) ? 'Valider et ouvrir Gmail' : 'Valider et copier'}
              </BoutonY2K>
            ) : appel ? (
              <div className="w-full space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <BoutonY2K size="sm" onClick={appeler} loading={verification} iconeGauche={<Phone className="h-4 w-4" />}>
                    Appeler le {numero}
                  </BoutonY2K>
                  {numeroVerifie && lienTel(numeroVerifie) ? (
                    <span className="text-xs text-muted-foreground">
                      Fiche revérifiée à l’instant. Si l’appel ne s’est pas lancé :{' '}
                      <a href={lienTel(numeroVerifie) ?? undefined} className="font-medium text-primary underline underline-offset-2">
                        composer le {numeroVerifie}
                      </a>
                    </span>
                  ) : null}
                </div>
                <div role="group" aria-label="Résultat de l’appel" className="flex flex-wrap items-center gap-2">
                  <span className="text-xs font-medium text-muted-foreground">Après l’appel :</span>
                  {RESULTATS_APPEL.map((r) => (
                    <BoutonY2K
                      key={r.code}
                      size="sm"
                      variant={r.definitif ? 'ghost' : 'secondary'}
                      onClick={() => noterAppel(r)}
                      loading={resultatEnCours === r.code}
                      disabled={resultatEnCours !== null && resultatEnCours !== r.code}
                    >
                      {r.libelle}
                    </BoutonY2K>
                  ))}
                </div>
              </div>
            ) : (
              <>
                <BoutonY2K
                  size="sm"
                  onClick={async () => { if (await decider('MARQUER_ENVOYE')) toast.success(estEmail(b) ? 'Envoi enregistré dans le CRM' : 'Publication enregistrée'); }}
                  loading={enCours === 'MARQUER_ENVOYE'}
                  iconeGauche={<Send className="h-4 w-4" />}
                >
                  {estEmail(b) ? 'J’ai envoyé' : 'J’ai publié'}
                </BoutonY2K>
                <BoutonY2K size="sm" variant="secondary" onClick={rouvrir} iconeGauche={<ExternalLink className="h-4 w-4" />}>
                  {estEmail(b) ? 'Rouvrir Gmail' : 'Copier à nouveau'}
                </BoutonY2K>
              </>
            )}
            {modifie ? (
              <BoutonY2K size="sm" variant="secondary" onClick={async () => { if (await decider('MODIFIER')) toast.success('Modifications enregistrées'); }} loading={enCours === 'MODIFIER'}>
                Enregistrer
              </BoutonY2K>
            ) : null}
            <BoutonY2K size="sm" variant="ghost" onClick={rejeter} loading={enCours === 'REJETER'} iconeGauche={<X className="h-4 w-4" />}>
              {appel ? 'Ne pas appeler' : 'Rejeter'}
            </BoutonY2K>
          </div>
        ) : null}
      </CardY2KContent>
    </CardY2K>
  );
}

function BarreEntonnoir({ titre, etapesListe }: { titre: string; etapesListe: EtapeEntonnoir[] }) {
  const max = Math.max(1, ...etapesListe.map((e) => e.valeur));
  const g = goulot(etapesListe);
  return (
    <CardY2K hoverLift={false}>
      <CardY2KContent className="space-y-3">
        <h3 className="font-semibold text-foreground">{titre}</h3>
        <ol className="space-y-2" aria-label={titre}>
          {etapesListe.map((e) => (
            <li key={e.cle} className="space-y-1">
              <div className="flex items-baseline justify-between gap-2 text-sm">
                <span className={e.cle === g?.cle ? 'font-semibold text-destructive' : 'text-foreground'}>{e.libelle}</span>
                <span className="tabular-nums text-foreground">
                  {e.valeur.toLocaleString('fr-FR')}
                  {e.conversionPct !== null ? <span className="ml-2 text-xs text-muted-foreground">{e.conversionPct} %</span> : null}
                </span>
              </div>
              <div className="h-2 rounded-full bg-muted" aria-hidden="true">
                <div className="h-2 rounded-full bg-primary" style={{ width: `${Math.max(e.valeur > 0 ? 2 : 0, (e.valeur / max) * 100)}%` }} />
              </div>
            </li>
          ))}
        </ol>
        {g ? <p className="text-xs text-muted-foreground">Goulot actuel : <strong className="text-foreground">{g.libelle}</strong></p> : null}
      </CardY2KContent>
    </CardY2K>
  );
}

export default function AdminAgentsCroissance() {
  usePageTitle('Agents de croissance');
  const [searchParams, setSearchParams] = useSearchParams();
  const vueParam = searchParams.get('vue');
  const vue: Vue = vueParam === 'entonnoir' || vueParam === 'agents' ? vueParam : 'file';

  const [filtre, setFiltre] = useState<FiltreAgent>('TOUS');
  const [historique, setHistorique] = useState(false);
  const [brouillons, setBrouillons] = useState<BrouillonCroissance[] | null>(null);
  const [entonnoir, setEntonnoir] = useState<EntonnoirCroissance | null>(null);
  const [jours, setJours] = useState(7);
  const [rapports, setRapports] = useState<RapportHebdo[]>([]);
  const [executions, setExecutions] = useState<Execution[]>([]);
  const [lancement, setLancement] = useState(false);
  const [planif, setPlanif] = useState<Planification | null>(null);
  const [bascule, setBascule] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);
  const [rapportCibles, setRapportCibles] = useState<RapportCibles | null>(null);

  const chargerFile = useCallback(async () => {
    let q = db.from('growth_brouillons').select('*').order('cree_le', { ascending: false }).limit(150);
    q = historique ? q.in('statut', ['ENVOYE', 'REJETE', 'EXPIRE']) : q.in('statut', ['BROUILLON', 'VALIDE']);
    if (filtre !== 'TOUS') q = q.eq('agent', filtre);
    const { data, error } = await q;
    if (error) { setErreur(error.message); return; }
    setErreur(null);
    setBrouillons((data ?? []) as BrouillonCroissance[]);
  }, [filtre, historique]);

  const chargerEntonnoir = useCallback(async () => {
    const [live, hebdo] = await Promise.all([
      db.rpc('fn_admin_growth_entonnoir', { p_jours: jours }),
      db.from('growth_rapports_hebdo').select('semaine_debut, donnees').order('semaine_debut', { ascending: false }).limit(12),
    ]);
    if (live.error) { setErreur(live.error.message); return; }
    setErreur(null);
    setEntonnoir(live.data as EntonnoirCroissance);
    setRapports((hebdo.data ?? []) as RapportHebdo[]);
  }, [jours]);

  const chargerExecutions = useCallback(async () => {
    const [exec, plan] = await Promise.all([
      db.from('growth_agent_executions')
        .select('id, agent, declencheur, debut_le, brouillons_crees, erreur, details')
        .order('debut_le', { ascending: false }).limit(40),
      db.rpc('fn_admin_growth_planification', { p_actif: null }),
    ]);
    if (!exec.error) setExecutions((exec.data ?? []) as Execution[]);
    if (plan.error) setErreur(plan.error.message); else setPlanif(plan.data as Planification);
  }, []);

  // Décompte des cibles du dernier passage réussi de l'agent email : un zéro
  // brouillon s'explique en haut de page, quel que soit l'onglet ouvert.
  const chargerCibles = useCallback(async () => {
    const { data, error } = await db.from('growth_agent_executions')
      .select('debut_le, details')
      .eq('agent', 'PROSPECTION_ETABLISSEMENT')
      .is('erreur', null)
      .order('debut_le', { ascending: false })
      .limit(1);
    if (error) { setErreur(`Décompte des cibles illisible : ${error.message}`); return; }
    const dernier = ((data ?? []) as Array<{ debut_le: string; details: Record<string, unknown> | null }>)[0];
    const cibles = lireCibles(dernier?.details?.cibles);
    setRapportCibles(dernier && cibles ? { le: dernier.debut_le, cibles, passage: lirePassage(dernier.details) } : null);
  }, []);

  const basculerPlanification = async (actif: boolean) => {
    setBascule(true);
    const { data, error } = await db.rpc('fn_admin_growth_planification', { p_actif: actif });
    setBascule(false);
    if (error) { toast.error(error.message); return; }
    setPlanif(data as Planification);
    toast.success(actif
      ? 'Préparation automatique activée : brouillons chaque matin à 6 h 50, rapport le lundi. Aucun envoi.'
      : 'Préparation automatique en pause.');
  };

  useEffect(() => { void chargerCibles(); }, [chargerCibles]);
  useEffect(() => { if (vue === 'file') void chargerFile(); }, [vue, chargerFile]);
  useEffect(() => { if (vue === 'entonnoir') void chargerEntonnoir(); }, [vue, chargerEntonnoir]);
  useEffect(() => { if (vue === 'agents') void chargerExecutions(); }, [vue, chargerExecutions]);

  const changerVue = (v: string) => {
    const params = new URLSearchParams(searchParams);
    if (v === 'file') params.delete('vue'); else params.set('vue', v);
    setSearchParams(params, { replace: true });
  };

  const lancerAgents = async () => {
    setLancement(true);
    const { data, error } = await db.rpc('fn_admin_growth_executer_agents');
    setLancement(false);
    if (error) { toast.error(error.message); return; }
    const total = Object.values((data?.agents ?? {}) as Record<string, { brouillons_crees?: number }>)
      .reduce((s, a) => s + (a?.brouillons_crees ?? 0), 0);
    toast.success(`${total} nouveau(x) brouillon(s). Rien n’a été envoyé.`);
    void chargerExecutions();
    void chargerFile();
    void chargerCibles();
  };

  const alerte = alerteCibles(rapportCibles?.cibles ?? null, rapportCibles?.passage ?? null);
  const voirFichesAppel = () => {
    setHistorique(false);
    setFiltre('APPEL_ETABLISSEMENT');
    changerVue('file');
  };

  const comptes = useMemo(() => {
    const c: Record<string, number> = {};
    (brouillons ?? []).forEach((b) => { c[b.agent] = (c[b.agent] ?? 0) + 1; });
    return c;
  }, [brouillons]);

  const derniereParAgent = useMemo(() => {
    const m = new Map<string, Execution>();
    executions.forEach((e) => { if (!m.has(e.agent)) m.set(e.agent, e); });
    return m;
  }, [executions]);

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <AdminPageHeader
          eyebrow="Acquisition"
          title="Agents de croissance"
          description="Les agents préparent chaque jour des emails et des posts, et chaque semaine une liste d’appels. Rien ne part sans vous : vous relisez, validez, envoyez depuis votre Gmail, publiez ou appelez, puis vous le notez ici."
          icon={<Bot className="h-6 w-6" />}
          actions={
            <BoutonY2K size="sm" variant="secondary" onClick={lancerAgents} loading={lancement} iconeGauche={<PlayCircle className="h-4 w-4" />}>
              Préparer maintenant
            </BoutonY2K>
          }
        />

        <div className="flex items-start gap-2 rounded-xl border border-border bg-muted/30 p-3 text-sm text-muted-foreground">
          <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden="true" />
          <p>
            Aucun envoi automatique. Chaque email reste un brouillon jusqu’à votre validation, aucun appel n’est passé à votre place, et
            les contacts en opposition (STOP) sont exclus avant la rédaction puis vérifiés de nouveau à la validation.
          </p>
        </div>

        {alerte && rapportCibles ? (
          <div
            role="status"
            data-testid="alerte-cibles-prospection"
            className={`flex items-start gap-2 rounded-xl border p-3 text-sm ${alerte.niveau === 'alerte'
              ? 'border-amber-300/60 bg-amber-50/70 text-amber-900 dark:bg-amber-950/20 dark:text-amber-200'
              : 'border-border bg-muted/30 text-muted-foreground'}`}
          >
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            <div className="min-w-0 space-y-2">
              <p className="font-semibold">{alerte.titre}</p>
              <p>{alerte.texte}</p>
              <p className="text-xs">Constat du dernier passage de l’agent, le {fmtDate(rapportCibles.le)}.</p>
              {rapportCibles.cibles.telephones_utilisables > 0 ? (
                <BoutonY2K size="sm" variant="secondary" onClick={voirFichesAppel} iconeGauche={<Phone className="h-4 w-4" />}>
                  Voir les fiches d’appel
                </BoutonY2K>
              ) : null}
            </div>
          </div>
        ) : null}

        {erreur ? <p role="alert" className="text-sm text-destructive">{erreur}</p> : null}

        <Tabs value={vue} onValueChange={changerVue}>
          <AdminTabsList disposition="grid" colonnes={3} className="sm:w-fit" aria-label="Vues des agents de croissance">
            <TabsTrigger value="file">À valider</TabsTrigger>
            <TabsTrigger value="entonnoir">Entonnoir</TabsTrigger>
            <TabsTrigger value="agents">Agents</TabsTrigger>
          </AdminTabsList>

          <TabsContent value="file" className="mt-5 space-y-4">
            <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filtrer par agent">
              <Filter className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
              {(['TOUS', ...Object.keys(AGENTS)] as FiltreAgent[]).map((a) => (
                <BoutonY2K key={a} size="sm" variant={filtre === a ? 'primary' : 'secondary'} onClick={() => setFiltre(a)} aria-pressed={filtre === a}>
                  {a === 'TOUS' ? 'Tous' : AGENTS[a].libelle}
                  {a !== 'TOUS' && !historique && comptes[a] ? ` (${comptes[a]})` : ''}
                </BoutonY2K>
              ))}
              <BoutonY2K size="sm" variant="ghost" onClick={() => setHistorique((h) => !h)} aria-pressed={historique}>
                {historique ? 'Voir la file' : 'Voir l’historique'}
              </BoutonY2K>
              <BoutonY2K size="sm" variant="ghost" onClick={chargerFile} iconeGauche={<RefreshCw className="h-4 w-4" />} aria-label="Rafraîchir la file" />
            </div>

            {brouillons === null ? (
              <ChargementAdmin titre="Chargement des brouillons" />
            ) : brouillons.length === 0 ? (
              <CardY2K hoverLift={false}>
                <CardY2KContent className="py-8 text-center text-sm text-muted-foreground">
                  {historique
                    ? 'Aucun brouillon traité pour ce filtre.'
                    : filtre === 'PROSPECTION_ETABLISSEMENT' && alerte?.niveau === 'alerte'
                      ? 'Aucun email à valider : aucune adresse utilisable parmi les établissements ciblés (voir l’avertissement en haut de page).'
                      : 'Aucun brouillon en attente. Les agents passent chaque matin vers 6 h 50, ou cliquez sur « Préparer maintenant ».'}
                </CardY2KContent>
              </CardY2K>
            ) : (
              <div className="grid gap-4 lg:grid-cols-2">
                {brouillons.map((b) => <CarteBrouillon key={`${b.id}-${b.statut}`} b={b} onChange={chargerFile} />)}
              </div>
            )}
          </TabsContent>

          <TabsContent value="entonnoir" className="mt-5 space-y-4">
            <div className="flex flex-wrap items-center gap-2">
              {[7, 30, 90].map((j) => (
                <BoutonY2K key={j} size="sm" variant={jours === j ? 'primary' : 'secondary'} onClick={() => setJours(j)} aria-pressed={jours === j}>
                  {j} jours
                </BoutonY2K>
              ))}
              <span className="text-xs text-muted-foreground">Cohorte réelle uniquement : les comptes de test sont exclus.</span>
            </div>
            {entonnoir === null ? (
              <ChargementAdmin titre="Calcul de l’entonnoir" />
            ) : (
              <>
                <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                  <CarteKPIY2K label="Soignants inscrits (période)" valeur={entonnoir.soignants?.inscrits_periode ?? 0} contexte={`${entonnoir.soignants?.inscrits_total ?? 0} au total`} variant="holographic" />
                  <CarteKPIY2K label="Établissements inscrits (période)" valeur={entonnoir.etablissements?.inscrits_periode ?? 0} contexte={`${entonnoir.etablissements?.inscrits_total ?? 0} au total`} />
                  <CarteKPIY2K label="Missions publiées (période)" valeur={entonnoir.missions?.publiees_periode ?? 0} contexte={`${entonnoir.missions?.pourvues_periode ?? 0} pourvue(s)`} />
                  <CarteKPIY2K label="Emails de prospection (période)" valeur={Number(entonnoir.prospection?.emails_journalises_periode ?? 0)} contexte={`${Number(entonnoir.agents?.en_attente ?? 0)} brouillon(s) en attente`} />
                </div>
                <div className="grid gap-4 lg:grid-cols-2">
                  <BarreEntonnoir titre="Soignants (cumul)" etapesListe={etapesSoignants(entonnoir)} />
                  <BarreEntonnoir titre="Établissements (cumul)" etapesListe={etapesEtablissements(entonnoir)} />
                </div>
                <CardY2K hoverLift={false}>
                  <CardY2KContent className="space-y-2">
                    <h3 className="flex items-center gap-2 font-semibold text-foreground"><TrendingUp className="h-4 w-4" aria-hidden="true" /> Rapports hebdomadaires</h3>
                    {rapports.length === 0 ? (
                      <p className="text-sm text-muted-foreground">Le premier rapport sera figé lundi matin pour la semaine écoulée.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-sm">
                          <thead>
                            <tr className="text-left text-xs text-muted-foreground">
                              <th className="py-1 pr-3 font-medium">Semaine du</th>
                              <th className="py-1 pr-3 font-medium">Soignants</th>
                              <th className="py-1 pr-3 font-medium">Établissements</th>
                              <th className="py-1 pr-3 font-medium">Missions publiées</th>
                              <th className="py-1 pr-3 font-medium">Pourvues</th>
                              <th className="py-1 pr-3 font-medium">Emails envoyés</th>
                              <th className="py-1 pr-3 font-medium">Fiches d’appel notées</th>
                              <th className="py-1 pr-3 font-medium">Adresses utilisables</th>
                            </tr>
                          </thead>
                          <tbody>
                            {rapports.map((r) => (
                              <tr key={r.semaine_debut} className="border-t border-border tabular-nums">
                                <td className="py-1 pr-3">{new Date(r.semaine_debut).toLocaleDateString('fr-FR')}</td>
                                <td className="py-1 pr-3">{r.donnees?.soignants?.inscrits_periode ?? 0}</td>
                                <td className="py-1 pr-3">{r.donnees?.etablissements?.inscrits_periode ?? 0}</td>
                                <td className="py-1 pr-3">{r.donnees?.missions?.publiees_periode ?? 0}</td>
                                <td className="py-1 pr-3">{r.donnees?.missions?.pourvues_periode ?? 0}</td>
                                <td className="py-1 pr-3">{Number(r.donnees?.prospection?.emails_journalises_periode ?? 0)}</td>
                                <td className="py-1 pr-3">{Number(r.donnees?.prospection?.fiches_appel_notees_periode ?? 0)}</td>
                                <td className="py-1 pr-3">{lireCibles(r.donnees?.prospection?.cibles_agent)?.adresses_utilisables.toLocaleString('fr-FR') ?? '—'}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardY2KContent>
                </CardY2K>
              </>
            )}
          </TabsContent>

          <TabsContent value="agents" className="mt-5 space-y-4">
            <CardY2K hoverLift={false} data-testid="planification-croissance">
              <CardY2KContent className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div className="min-w-0 space-y-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="font-semibold text-foreground">Préparation automatique</h3>
                    {planif === null ? null : planif.actif
                      ? <BadgeY2K variant="success" size="sm">Activée</BadgeY2K>
                      : <BadgeY2K variant="warning" size="sm">En pause</BadgeY2K>}
                  </div>
                  <p className="text-sm text-muted-foreground">
                    {planif?.actif
                      ? 'Les agents préparent les brouillons chaque matin à 6 h 50 et figent le rapport le lundi. Rien n’est envoyé sans vous.'
                      : 'Les agents ne tournent que si vous cliquez sur « Préparer maintenant ». Activez la préparation pour recevoir les brouillons chaque matin.'}
                  </p>
                </div>
                {planif === null ? null : (
                  <BoutonY2K
                    size="sm"
                    variant={planif.actif ? 'secondary' : 'primary'}
                    onClick={() => basculerPlanification(!planif.actif)}
                    loading={bascule}
                  >
                    {planif.actif ? 'Mettre en pause' : 'Activer la préparation automatique'}
                  </BoutonY2K>
                )}
              </CardY2KContent>
            </CardY2K>
            <div className="grid gap-4 lg:grid-cols-2">
              {(Object.keys(AGENTS) as AgentCroissance[]).map((a) => {
                const derniere = derniereParAgent.get(a);
                const sansCible = a === 'PROSPECTION_ETABLISSEMENT' && alerte?.niveau === 'alerte';
                const appels = a === 'APPEL_ETABLISSEMENT' && !derniere?.erreur ? resumeAppels(derniere?.details) : null;
                return (
                  <CardY2K key={a} hoverLift={false}>
                    <CardY2KContent className="space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <h3 className="font-semibold text-foreground">{AGENTS[a].libelle}</h3>
                        {derniere?.erreur
                          ? <BadgeY2K variant="error" size="sm">Erreur</BadgeY2K>
                          : sansCible
                            ? <BadgeY2K variant="warning" size="sm">Aucune cible joignable</BadgeY2K>
                            : appels?.epuisee
                              ? <BadgeY2K variant="warning" size="sm">Liste épuisée</BadgeY2K>
                              : <BadgeY2K variant="success" size="sm">Brouillons seulement</BadgeY2K>}
                      </div>
                      <p className="text-sm text-muted-foreground">{AGENTS[a].description}</p>
                      <p className="text-xs text-muted-foreground">
                        Dernier passage : {derniere ? `${fmtDate(derniere.debut_le)} (${derniere.declencheur === 'CRON' ? 'automatique' : 'manuel'}) · ${derniere.brouillons_crees} brouillon(s)` : 'aucun pour l’instant'}
                      </p>
                      {derniere?.erreur ? <p className="text-xs text-destructive break-words">{derniere.erreur}</p> : null}
                      {appels ? <p className="text-xs text-muted-foreground" data-testid="passage-appels">{appels.texte}</p> : null}
                      {a === 'PROSPECTION_ETABLISSEMENT' && rapportCibles ? (
                        <p className="text-xs text-muted-foreground" data-testid="cibles-prospection">Cibles : {resumeCibles(rapportCibles.cibles)}</p>
                      ) : null}
                    </CardY2KContent>
                  </CardY2K>
                );
              })}
            </div>
            <p className="text-xs text-muted-foreground">
              Horaires (heure de Paris en hiver) : agents chaque jour à 6 h 50, liste d’appels complétée à ce passage dans la limite de la
              semaine, rapport hebdomadaire le lundi à 6 h 15. Réglages dans
              growth_config (départements cibles, quota quotidien, signature, mention d’opposition).
            </p>
          </TabsContent>
        </Tabs>
      </div>
    </LayoutAdmin>
  );
}
