import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlarmClock,
  ArrowRight,
  Bot,
  CalendarClock,
  CheckCircle2,
  Mail,
  MessageCircle,
  Phone,
  RefreshCw,
  UserCheck,
  UserRoundCog,
  XCircle,
} from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { toast } from 'sonner';

interface ResponsableCrm {
  user_id: string;
  nom: string;
  prenom: string;
  email: string;
}

interface TacheCrm {
  id: string;
  contact_id: string;
  type: string;
  canal: 'TELEPHONE' | 'EMAIL' | 'WHATSAPP' | 'AUTRE';
  statut: string;
  priorite: 'BASSE' | 'NORMALE' | 'HAUTE' | 'URGENTE';
  titre: string;
  echeance_le: string;
  assignee_a: string | null;
  sequence_etape: number;
  origine: string;
  contact_type: 'SOIGNANT' | 'ETABLISSEMENT';
  nom: string;
  profession: string | null;
  telephone: string | null;
  email: string | null;
  ville: string | null;
  departement: string | null;
  contact_statut: string;
  ne_plus_contacter: boolean;
  reponse: string | null;
}

interface ActiviteCrm {
  id: string;
  nom: string;
  action_type: string;
  canal: string | null;
  resultat: string | null;
  details: string | null;
  automatisee: boolean;
  cree_le: string;
}

interface TableauCrm {
  stats: {
    a_traiter: number;
    en_retard: number;
    sept_jours: number;
    sans_responsable: number;
    contacts_actifs: number;
    taux_conversion: number;
    emails_7j: number;
    actions_7j: number;
  };
  taches: TacheCrm[];
  activites: ActiviteCrm[];
  responsables: ResponsableCrm[];
  genere_le: string;
}

interface AdminCrmAutomationProps {
  onContactsChanged?: () => void;
}

const RESULTATS = {
  APPEL_REPONDU: 'A répondu',
  SANS_REPONSE: 'Sans réponse',
  INTERESSE: 'Intéressé(e)',
  INSCRIT: 'Inscrit(e)',
  PAS_INTERESSE: 'Pas intéressé(e)',
  STOP: 'STOP',
} as const;

function formatDate(value: string): string {
  return new Intl.DateTimeFormat('fr-FR', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
}

function estEnRetard(value: string): boolean {
  return new Date(value).getTime() < Date.now();
}

function lienWhatsApp(telephone: string): string {
  const chiffres = telephone.replace(/\D/g, '');
  const international = chiffres.startsWith('0') ? `33${chiffres.slice(1)}` : chiffres;
  return `https://wa.me/${international}`;
}

function contactCrmBloque(tache: TacheCrm): boolean {
  return tache.ne_plus_contacter || tache.contact_statut === 'PERDU';
}

function ouvrirGmail(tache: TacheCrm) {
  if (!tache.email || contactCrmBloque(tache)) return;
  const cible = tache.contact_type === 'ETABLISSEMENT' ? 'votre établissement' : 'vos prochaines missions';
  const sujet = tache.contact_type === 'ETABLISSEMENT'
    ? `Jolene — un point rapide pour ${tache.nom}`
    : 'Jolene — des missions peuvent vous correspondre';
  const corps = `Bonjour,\n\nJe me permets de revenir vers vous au sujet de ${cible}.\n\nJe reste disponible pour vous aider personnellement.\n\nBien à vous,\nGabrielle — Jolene`;
  window.open(`https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(tache.email)}&su=${encodeURIComponent(sujet)}&body=${encodeURIComponent(corps)}`, '_blank', 'noopener');
}

function badgePriorite(priorite: TacheCrm['priorite']): 'error' | 'warning' | 'info' {
  if (priorite === 'URGENTE') return 'error';
  if (priorite === 'HAUTE') return 'warning';
  return 'info';
}

export function AdminCrmAutomation({ onContactsChanged }: AdminCrmAutomationProps) {
  const [data, setData] = useState<TableauCrm | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [filtreCible, setFiltreCible] = useState<'TOUS' | 'SOIGNANT' | 'ETABLISSEMENT'>('TOUS');
  const [filtreResponsable, setFiltreResponsable] = useState('');
  const [voirFutures, setVoirFutures] = useState(false);

  const charger = useCallback(async (regenerer = false) => {
    setLoading(true);
    if (regenerer) {
      const { error: erreurGeneration } = await supabase.rpc('fn_crm_generer_taches' as never);
      if (erreurGeneration) toast.error(`Préparation des actions : ${erreurGeneration.message}`);
    }
    const { data: resultat, error } = await supabase.rpc('fn_admin_crm_tableau' as never, { p_limit: 200 } as never);
    setLoading(false);
    if (error) {
      toast.error(`CRM indisponible : ${error.message}`);
      setData(null);
      return;
    }
    setData(resultat as unknown as TableauCrm);
  }, []);

  useEffect(() => {
    charger(true);
  }, [charger]);

  const taches = useMemo(() => {
    const source = data?.taches || [];
    return source.filter((tache) =>
      !contactCrmBloque(tache)
      && (filtreCible === 'TOUS' || tache.contact_type === filtreCible)
      && (!filtreResponsable || tache.assignee_a === filtreResponsable)
      && (voirFutures || new Date(tache.echeance_le).getTime() <= Date.now()),
    );
  }, [data?.taches, filtreCible, filtreResponsable, voirFutures]);

  const rafraichirApresAction = useCallback(async () => {
    onContactsChanged?.();
    await charger(true);
  }, [charger, onContactsChanged]);

  const effectuerAction = async (tache: TacheCrm, resultat: keyof typeof RESULTATS) => {
    if (contactCrmBloque(tache)) {
      toast.error('Contact bloqué : aucune action autorisée.');
      return;
    }
    if ((resultat === 'PAS_INTERESSE' || resultat === 'STOP')
      && !window.confirm(`${RESULTATS[resultat]} : arrêter définitivement la séquence pour ${tache.nom} ?`)) return;
    setActionLoading(tache.id);
    const { error } = await supabase.rpc('fn_admin_crm_effectuer_action' as never, {
      p_tache_id: tache.id,
      p_resultat: resultat,
      p_notes: null,
      p_prochaine_action_le: null,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(`Suivi mis à jour : ${RESULTATS[resultat]}.`);
    await rafraichirApresAction();
  };

  const marquerEmailEnvoye = async (tache: TacheCrm) => {
    if (contactCrmBloque(tache)) {
      toast.error('Contact bloqué : aucun email ne peut être journalisé.');
      return;
    }
    setActionLoading(tache.id);
    const { error } = await supabase.rpc('fn_admin_crm_effectuer_action' as never, {
      p_tache_id: tache.id,
      p_resultat: 'EMAIL_ENVOYE',
      p_notes: 'Email confirmé envoyé depuis le cockpit CRM',
      p_prochaine_action_le: null,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success('Email journalisé et prochaine relance programmée.');
    await rafraichirApresAction();
  };

  const reporter = async (tache: TacheCrm, jours: number) => {
    if (contactCrmBloque(tache)) {
      toast.error('Contact bloqué : aucun rappel ne peut être programmé.');
      return;
    }
    setActionLoading(tache.id);
    const nouvelleDate = new Date();
    nouvelleDate.setDate(nouvelleDate.getDate() + jours);
    nouvelleDate.setHours(9, 0, 0, 0);
    const { error } = await supabase.rpc('fn_admin_crm_reporter_tache' as never, {
      p_tache_id: tache.id,
      p_echeance_le: nouvelleDate.toISOString(),
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(`Rappel reporté de ${jours} jour${jours > 1 ? 's' : ''}.`);
    await charger();
  };

  const assigner = async (tache: TacheCrm, responsableId: string) => {
    setActionLoading(tache.id);
    const { error } = await supabase.rpc('fn_admin_crm_assigner_contact' as never, {
      p_contact_id: tache.contact_id,
      p_responsable_id: responsableId || null,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success('Responsable mis à jour.');
    await charger();
  };

  if (loading && !data) {
    return (
      <div className="rounded-xl border border-border bg-card p-8 text-center text-sm text-muted-foreground" role="status">
        Préparation des actions du jour…
      </div>
    );
  }

  if (!data) {
    return <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-destructive" role="alert">Les actions commerciales n’ont pas pu être chargées.</div>;
  }

  return (
    <section className="space-y-5" aria-labelledby="crm-title">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 id="crm-title" className="flex items-center gap-2 font-bold text-foreground">
            <Bot className="h-5 w-5 text-primary" aria-hidden="true" /> Actions du jour
          </h2>
          <p className="text-xs text-muted-foreground">
            Jolene prépare les priorités et les rappels. Depuis cet écran, aucun appel, email ou message n’est envoyé sans une action humaine explicite.
          </p>
        </div>
        <BoutonY2K variant="ghost" size="sm" onClick={() => charger(true)} loading={loading} iconeGauche={<RefreshCw className="h-4 w-4" />}>
          Recalculer les priorités
        </BoutonY2K>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <CarteKPIY2K icone={<AlarmClock className="h-4 w-4" />} label="À traiter" valeur={data.stats.a_traiter} contexte={`${data.stats.en_retard} en retard`} variant="holographic" />
        <CarteKPIY2K icone={<CalendarClock className="h-4 w-4" />} label="À 7 jours" valeur={data.stats.sept_jours} contexte={`${data.stats.contacts_actifs} contacts actifs`} />
        <CarteKPIY2K icone={<UserCheck className="h-4 w-4" />} label="Conversion" valeur={`${data.stats.taux_conversion || 0} %`} contexte="Contacts passés inscrits" variant="soft" />
        <CarteKPIY2K icone={<MessageCircle className="h-4 w-4" />} label="Actions / 7 j" valeur={data.stats.actions_7j} contexte={`${data.stats.emails_7j} emails`} />
      </div>

      <div className="grid gap-3 rounded-xl border border-border bg-card p-3 sm:grid-cols-3">
        <div>
          <Label htmlFor="crm-cible" className="text-xs">Cible</Label>
          <select id="crm-cible" className="input-base mt-1 h-9 w-full" value={filtreCible} onChange={(event) => setFiltreCible(event.target.value as typeof filtreCible)}>
            <option value="TOUS">Toutes</option>
            <option value="ETABLISSEMENT">Établissements</option>
            <option value="SOIGNANT">Soignants</option>
          </select>
        </div>
        <div>
          <Label htmlFor="crm-responsable" className="text-xs">Responsable</Label>
          <select id="crm-responsable" className="input-base mt-1 h-9 w-full" value={filtreResponsable} onChange={(event) => setFiltreResponsable(event.target.value)}>
            <option value="">Tous</option>
            {data.responsables.map((responsable) => (
              <option key={responsable.user_id} value={responsable.user_id}>{responsable.prenom} {responsable.nom}</option>
            ))}
          </select>
        </div>
        <div className="flex items-end">
          <BoutonY2K size="sm" variant={voirFutures ? 'primary' : 'secondary'} aria-pressed={voirFutures} onClick={() => setVoirFutures((value) => !value)} className="w-full">
            {voirFutures ? 'Masquer les futures' : 'Voir les 7 prochains jours'}
          </BoutonY2K>
        </div>
      </div>

      <p className="text-xs text-muted-foreground">{taches.length} tâche(s) affichée(s)</p>

      {taches.length === 0 ? (
        <CardY2K hoverLift={false} noPadding>
          <CardY2KContent className="pt-6 text-center">
            <CheckCircle2 className="mx-auto mb-2 h-8 w-8 text-emerald-600" aria-hidden="true" />
            <p className="font-semibold text-foreground">File à jour</p>
            <p className="text-sm text-muted-foreground">Aucune action ne correspond aux filtres.</p>
          </CardY2KContent>
        </CardY2K>
      ) : (
        <div className="grid gap-3 xl:grid-cols-2">
          {taches.map((tache) => {
            const responsable = data.responsables.find((item) => item.user_id === tache.assignee_a);
            const busy = actionLoading === tache.id;
            const contactBloque = contactCrmBloque(tache);
            return (
              <CardY2K key={tache.id} hoverLift={false} noPadding className={estEnRetard(tache.echeance_le) ? 'border-destructive/40' : ''}>
                <CardY2KContent className="pt-6">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <BadgeY2K variant={badgePriorite(tache.priorite)}>{tache.priorite === 'URGENTE' ? 'Urgent' : tache.priorite === 'HAUTE' ? 'Prioritaire' : 'Planifié'}</BadgeY2K>
                        <BadgeY2K variant="info">{tache.canal === 'TELEPHONE' ? 'Téléphone' : tache.canal === 'EMAIL' ? 'Email' : tache.canal}</BadgeY2K>
                        {estEnRetard(tache.echeance_le) && <BadgeY2K variant="error">En retard</BadgeY2K>}
                        {contactBloque && <BadgeY2K variant="error">Contact bloqué</BadgeY2K>}
                      </div>
                      <h3 className="mt-2 font-bold text-foreground">{tache.nom}</h3>
                      <p className="text-xs text-muted-foreground">
                        {tache.contact_type === 'ETABLISSEMENT' ? 'Établissement' : getLabelProfession(tache.profession || '')}
                        {tache.ville ? ` · ${tache.ville}` : ''}{tache.departement ? ` (${tache.departement})` : ''}
                      </p>
                      <p className="mt-1 flex items-center gap-1 text-xs font-medium text-foreground">
                        <CalendarClock className="h-3.5 w-3.5" aria-hidden="true" /> {formatDate(tache.echeance_le)} · étape {tache.sequence_etape}
                      </p>
                    </div>
                    <div className="text-right text-[11px] text-muted-foreground">
                      <UserRoundCog className="ml-auto mb-1 h-4 w-4" aria-hidden="true" />
                      {responsable ? `${responsable.prenom} ${responsable.nom}` : 'Non assigné'}
                    </div>
                  </div>

                  {contactBloque ? (
                    <p className="mt-3 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm font-medium text-destructive" role="alert">
                      Contact bloqué — aucune action ni prise de contact autorisée.
                    </p>
                  ) : (
                    <>
                  <div className="mt-3 flex flex-wrap gap-2">
                    {tache.telephone && (
                      <>
                        <a href={`tel:${tache.telephone}`} className="inline-flex min-h-[44px] items-center gap-2 rounded-2xl bg-gradient-hero px-3 py-2 text-xs font-semibold text-white shadow-holographic focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                          <Phone className="h-4 w-4" aria-hidden="true" /> Appeler
                        </a>
                        <a href={lienWhatsApp(tache.telephone)} target="_blank" rel="noreferrer" className="inline-flex min-h-[44px] items-center gap-2 rounded-2xl border-2 border-jolene-rose-300 bg-card px-3 py-2 text-xs font-semibold text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                          <MessageCircle className="h-4 w-4" aria-hidden="true" /> WhatsApp
                        </a>
                      </>
                    )}
                    {tache.email && (
                      <BoutonY2K size="sm" variant="secondary" onClick={() => ouvrirGmail(tache)} iconeGauche={<Mail className="h-4 w-4" />}>
                        Préparer l’email
                      </BoutonY2K>
                    )}
                  </div>

                  {(tache.telephone || tache.email) && (
                    <p className="mt-1.5 flex flex-wrap gap-x-2 text-[11px]">
                      {tache.telephone && <a href={`tel:${tache.telephone}`} className="font-medium text-primary hover:underline">{tache.telephone}</a>}
                      {tache.email && <a href={`mailto:${tache.email}`} className="break-all font-medium text-primary hover:underline">{tache.email}</a>}
                    </p>
                  )}

                  <div className="mt-3 flex flex-wrap gap-2 border-t border-border pt-3" aria-label={`Résultat pour ${tache.nom}`}>
                    {tache.email && <BoutonY2K size="sm" onClick={() => marquerEmailEnvoye(tache)} loading={busy} iconeGauche={<Mail className="h-4 w-4" />}>Email envoyé</BoutonY2K>}
                    {tache.telephone && <BoutonY2K size="sm" variant="secondary" onClick={() => effectuerAction(tache, 'APPEL_REPONDU')} disabled={busy}>A répondu</BoutonY2K>}
                    <BoutonY2K size="sm" variant="ghost" onClick={() => effectuerAction(tache, 'SANS_REPONSE')} disabled={busy}>Sans réponse</BoutonY2K>
                    <BoutonY2K size="sm" variant="secondary" onClick={() => effectuerAction(tache, 'INTERESSE')} disabled={busy} iconeGauche={<UserCheck className="h-4 w-4" />}>Intéressé</BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => reporter(tache, 1)} disabled={busy} iconeGauche={<CalendarClock className="h-4 w-4" />}>Demain</BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => reporter(tache, 7)} disabled={busy}>Dans 7 j</BoutonY2K>
                  </div>

                  <details className="mt-3 rounded-lg bg-muted/40 p-2 text-xs">
                    <summary className="cursor-pointer font-medium text-muted-foreground">Plus d’actions</summary>
                    <div className="mt-2 flex flex-wrap items-end gap-2">
                      <div className="min-w-[180px] flex-1">
                        <Label htmlFor={`crm-owner-${tache.id}`} className="text-[11px]">Réattribuer</Label>
                        <select id={`crm-owner-${tache.id}`} className="input-base mt-1 h-9 w-full" value={tache.assignee_a || ''} onChange={(event) => assigner(tache, event.target.value)} disabled={busy}>
                          <option value="">Non assigné</option>
                          {data.responsables.map((item) => <option key={item.user_id} value={item.user_id}>{item.prenom} {item.nom}</option>)}
                        </select>
                      </div>
                      <BoutonY2K size="sm" variant="ghost" onClick={() => effectuerAction(tache, 'PAS_INTERESSE')} disabled={busy} iconeGauche={<XCircle className="h-4 w-4" />}>Pas intéressé</BoutonY2K>
                      <BoutonY2K size="sm" variant="secondary" onClick={() => effectuerAction(tache, 'INSCRIT')} disabled={busy} iconeGauche={<CheckCircle2 className="h-4 w-4" />}>Inscrit</BoutonY2K>
                      <BoutonY2K size="sm" variant="destructive" onClick={() => effectuerAction(tache, 'STOP')} disabled={busy}>STOP</BoutonY2K>
                    </div>
                  </details>
                    </>
                  )}
                </CardY2KContent>
              </CardY2K>
            );
          })}
        </div>
      )}

      <CardY2K hoverLift={false} noPadding>
        <CardY2KContent className="pt-6">
          <div className="mb-3 flex items-center justify-between gap-2">
            <div>
              <h3 className="font-bold text-foreground">Journal récent</h3>
              <p className="text-xs text-muted-foreground">Traçabilité des actions humaines et automatiques.</p>
            </div>
            <BadgeY2K variant="info">{data.activites.length} dernières</BadgeY2K>
          </div>
          <ol className="divide-y divide-border">
            {data.activites.slice(0, 12).map((activite) => (
              <li key={activite.id} className="flex items-start gap-3 py-2 text-xs">
                <span className="mt-0.5 rounded-full bg-primary/10 p-1.5 text-primary" aria-hidden="true">
                  {activite.automatisee ? <Bot className="h-3.5 w-3.5" /> : <ArrowRight className="h-3.5 w-3.5" />}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-foreground"><strong>{activite.nom}</strong> · {activite.resultat || activite.action_type}</p>
                  {activite.details && <p className="truncate text-muted-foreground">{activite.details}</p>}
                </div>
                <time dateTime={activite.cree_le} className="shrink-0 text-muted-foreground">{formatDate(activite.cree_le)}</time>
              </li>
            ))}
            {data.activites.length === 0 && <li className="py-4 text-center text-muted-foreground">Aucune action journalisée pour le moment.</li>}
          </ol>
        </CardY2KContent>
      </CardY2K>
    </section>
  );
}
