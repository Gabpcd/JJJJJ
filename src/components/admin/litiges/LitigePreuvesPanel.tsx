import React, { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { toast } from 'sonner';
import {
  Building2,
  Euro,
  FileText,
  MapPin,
  MessageSquare,
  Stethoscope,
  Timer,
  User,
} from 'lucide-react';
import type { LitigeEnrichi } from './types';

type PreuvesAgregees = {
  litige: Record<string, any> | null;
  mission: Record<string, any> | null;
  soignant: Record<string, any> | null;
  etablissement: Record<string, any> | null;
  pointages: Array<Record<string, any>>;
  heures: {
    prevues: Record<string, any> | null;
    declarees: Record<string, any> | null;
  } | null;
  factures_liees: Array<Record<string, any>>;
  messages: Array<Record<string, any>>;
};

type Props = {
  litige: LitigeEnrichi | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

const formatDT = (d?: string | null) =>
  d
    ? new Date(d).toLocaleString('fr-FR', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

const formatMontant = (v: number | null | undefined): string => {
  if (v == null || Number.isNaN(Number(v))) return '—';
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
  }).format(Number(v));
};

function Section({
  icon,
  title,
  children,
  testid,
}: {
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
  testid?: string;
}) {
  return (
    <section
      className="rounded-lg border bg-background p-4"
      data-testid={testid}
    >
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-foreground">
        {icon}
        {title}
      </div>
      <div className="space-y-2 text-sm text-muted-foreground">{children}</div>
    </section>
  );
}

function Line({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex flex-wrap justify-between gap-2">
      <span className="text-xs uppercase tracking-wide">{label}</span>
      <span className="text-foreground">{value ?? '—'}</span>
    </div>
  );
}

export function LitigePreuvesPanel({ litige, open, onOpenChange }: Props) {
  const [loading, setLoading] = useState(false);
  const [preuves, setPreuves] = useState<PreuvesAgregees | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !litige) {
      setPreuves(null);
      setError(null);
      return;
    }

    let annule = false;
    setLoading(true);
    setError(null);

    (async () => {
      try {
        const { data, error } = await supabase.rpc(
          'fn_litige_preuves_agregees' as any,
          { p_litige_id: litige.id },
        );
        if (annule) return;
        if (error) {
          logger.error('fn_litige_preuves_agregees error', error);
          setError(error.message || 'Erreur chargement preuves');
          toast.error('Impossible de charger les preuves du litige.');
          return;
        }
        setPreuves(data as PreuvesAgregees);
      } catch (err: any) {
        if (annule) return;
        logger.error('fn_litige_preuves_agregees throw', err);
        setError(err?.message || 'Erreur inattendue');
      } finally {
        if (!annule) setLoading(false);
      }
    })();

    return () => {
      annule = true;
    };
  }, [open, litige]);

  const l = preuves?.litige;
  const m = preuves?.mission;
  const s = preuves?.soignant;
  const e = preuves?.etablissement;
  const h = preuves?.heures;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Preuves agrégées — litige</DialogTitle>
          <DialogDescription>
            Contexte complet chargé en une seule requête via{' '}
            <code>fn_litige_preuves_agregees</code>.
          </DialogDescription>
        </DialogHeader>

        {loading && <ChargementPage />}
        {error && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            {error}
          </div>
        )}

        {!loading && !error && preuves && (
          <div className="space-y-4" data-testid="preuves-content">
            <Section
              icon={<FileText className="h-4 w-4" />}
              title="Litige"
              testid="section-litige"
            >
              <Line label="Type" value={l?.type_litige} />
              <Line label="Catégorie" value={l?.categorie_litige} />
              <Line label="Statut" value={l?.statut} />
              <Line label="Initié par" value={l?.initie_par} />
              <Line label="Ouvert le" value={formatDT(l?.cree_le)} />
              <Line
                label="Informatif"
                value={l?.est_informatif ? 'Oui' : 'Non'}
              />
              <div className="pt-2">
                <p className="text-xs uppercase tracking-wide">Motif</p>
                <p className="mt-1 text-foreground">{l?.motif || '—'}</p>
              </div>
            </Section>

            <Section
              icon={<Stethoscope className="h-4 w-4" />}
              title="Mission"
              testid="section-mission"
            >
              <Line label="Intitulé" value={m?.intitule} />
              <Line label="Service" value={m?.service} />
              <Line label="Profession" value={m?.profession_requise} />
              <Line label="Début" value={formatDT(m?.debut_le)} />
              <Line label="Fin" value={formatDT(m?.fin_le)} />
              <Line
                label="Taux horaire"
                value={m?.taux_horaire_base ? formatMontant(m.taux_horaire_base) + '/h' : '—'}
              />
              <Line label="Type contrat" value={m?.type_contrat_applique} />
              <Line label="Statut mission" value={m?.statut} />
            </Section>

            <Section
              icon={<User className="h-4 w-4" />}
              title="Soignant"
              testid="section-soignant"
            >
              <Line
                label="Nom"
                value={
                  s
                    ? `${s.prenom ?? ''} ${s.nom ?? ''}`.trim() || '—'
                    : '—'
                }
              />
              <Line label="RPPS" value={s?.rpps} />
              <Line label="Profession" value={s?.profession} />
              <Line
                label="Note moyenne"
                value={s?.note_moyenne != null ? `${s.note_moyenne}/5` : '—'}
              />
              <Line label="Téléphone" value={s?.telephone} />
              <Line
                label="Salarié établissement"
                value={s?.est_salarie_etablissement ? 'Oui' : 'Non'}
              />
            </Section>

            <Section
              icon={<Building2 className="h-4 w-4" />}
              title="Établissement"
              testid="section-etablissement"
            >
              <Line label="Nom" value={e?.nom} />
              <Line label="SIRET" value={e?.siret} />
              <Line label="Adresse" value={e?.adresse} />
              <Line label="Email" value={e?.email_contact} />
              <Line label="Téléphone" value={e?.telephone_contact} />
              <Line
                label="Secteur public"
                value={e?.est_secteur_public ? 'Oui' : 'Non'}
              />
            </Section>

            <Section
              icon={<MapPin className="h-4 w-4" />}
              title={`Pointages GPS (${preuves.pointages.length})`}
              testid="section-pointages"
            >
              {preuves.pointages.length === 0 ? (
                <p className="italic">Aucun pointage rattaché à ce litige.</p>
              ) : (
                <ul className="space-y-2">
                  {preuves.pointages.map((p, i) => (
                    <li
                      key={`${p.id}-${p.type ?? i}`}
                      className="rounded border bg-muted/30 p-2 text-xs"
                    >
                      <div className="flex flex-wrap gap-x-3 gap-y-1">
                        <span className="font-medium text-foreground">
                          {p.type ?? '—'}
                        </span>
                        <span>{formatDT(p.horodatage)}</span>
                        {p.latitude != null && p.longitude != null && (
                          <a
                            href={`https://www.google.com/maps?q=${p.latitude},${p.longitude}`}
                            target="_blank"
                            rel="noreferrer"
                            className="text-primary underline underline-offset-2"
                          >
                            {Number(p.latitude).toFixed(5)}, {Number(p.longitude).toFixed(5)}
                          </a>
                        )}
                        {p.precision_gps_m != null && (
                          <span>± {p.precision_gps_m} m</span>
                        )}
                        {p.methode && <span>({p.methode})</span>}
                        {p.is_geo_ok != null && (
                          <BadgeY2K
                            variant={p.is_geo_ok ? 'success' : 'error'}
                            size="sm"
                          >
                            {p.is_geo_ok ? 'Géo OK' : 'Hors zone'}
                          </BadgeY2K>
                        )}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            <Section
              icon={<Timer className="h-4 w-4" />}
              title="Heures — prévues vs déclarées"
              testid="section-heures"
            >
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="rounded border bg-muted/30 p-2">
                  <p className="text-xs font-semibold uppercase">Prévues</p>
                  {h?.prevues ? (
                    <div className="mt-1 space-y-0.5 text-xs">
                      <p>Début : {formatDT(h.prevues.debut)}</p>
                      <p>Fin : {formatDT(h.prevues.fin)}</p>
                      <p>Durée : {h.prevues.duree_h ?? '—'} h</p>
                    </div>
                  ) : (
                    <p className="italic">—</p>
                  )}
                </div>
                <div className="rounded border bg-muted/30 p-2">
                  <p className="text-xs font-semibold uppercase">Déclarées</p>
                  {h?.declarees ? (
                    <div className="mt-1 space-y-0.5 text-xs">
                      <p>Début : {formatDT(h.declarees.debut)}</p>
                      <p>Fin : {formatDT(h.declarees.fin)}</p>
                      <p>
                        Durée nette : {h.declarees.duree_nette_min ?? '—'} min (
                        {h.declarees.heures_reelles ?? '—'} h réelles)
                      </p>
                      {h.declarees.retard_min != null && (
                        <p>Retard : {h.declarees.retard_min} min</p>
                      )}
                      {h.declarees.depart_anticipe_min != null && (
                        <p>Départ anticipé : {h.declarees.depart_anticipe_min} min</p>
                      )}
                      <p>
                        Validé étab :{' '}
                        {h.declarees.valide_par_etablissement ? 'oui' : 'non'}
                        {h.declarees.valide_le
                          ? ` (${formatDT(h.declarees.valide_le)})`
                          : ''}
                      </p>
                    </div>
                  ) : (
                    <p className="italic">—</p>
                  )}
                </div>
              </div>
            </Section>

            <Section
              icon={<Euro className="h-4 w-4" />}
              title={`Factures liées (${preuves.factures_liees.length})`}
              testid="section-factures"
            >
              {preuves.factures_liees.length === 0 ? (
                <p className="italic">Aucune facture liée.</p>
              ) : (
                <ul className="space-y-2">
                  {preuves.factures_liees.map((f) => (
                    <li
                      key={f.id}
                      className="rounded border bg-muted/30 p-2 text-xs"
                    >
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-mono text-foreground">
                          {f.numero_facture ?? 'BROUILLON'}
                        </span>
                        <BadgeY2K variant="info" size="sm">
                          {f.type_document ?? '—'}
                        </BadgeY2K>
                        <BadgeY2K variant="info" size="sm">
                          {f.statut ?? '—'}
                        </BadgeY2K>
                        {f.statut_litige && (
                          <BadgeY2K variant="warning" size="sm">
                            Litige : {f.statut_litige}
                          </BadgeY2K>
                        )}
                        <span>HT {formatMontant(f.montant_ht)}</span>
                        <span>TTC {formatMontant(f.montant_ttc)}</span>
                        {f.date_emission && <span>{formatDT(f.date_emission)}</span>}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            <Section
              icon={<MessageSquare className="h-4 w-4" />}
              title={`Messages (${preuves.messages.length})`}
              testid="section-messages"
            >
              {preuves.messages.length === 0 ? (
                <p className="italic">Aucun message.</p>
              ) : (
                <ul className="space-y-2">
                  {preuves.messages.map((msg) => (
                    <li
                      key={msg.id}
                      className="rounded border bg-muted/30 p-2 text-xs"
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-foreground">
                          {msg.auteur_nom ?? '—'}{' '}
                          <span className="text-muted-foreground">
                            ({msg.auteur_type})
                          </span>
                        </span>
                        <span>{formatDT(msg.cree_le)}</span>
                      </div>
                      <p className="mt-1 text-foreground whitespace-pre-wrap">
                        {msg.contenu}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </Section>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
