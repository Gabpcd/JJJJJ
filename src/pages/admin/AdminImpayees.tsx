import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  AlertTriangle, ChevronDown, ChevronUp, Mail, Phone, Send, Clock,
  Building2,
} from 'lucide-react';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const fmtDate = (d: string | null) => d ? format(new Date(d), 'dd/MM/yyyy', { locale: fr }) : '—';
const fmtDateTime = (d: string | null) => d ? format(new Date(d), "dd MMM yyyy 'à' HH:mm", { locale: fr }) : '—';

interface FactureImpayee {
  id: string;
  numero_facture: string;
  montant_ht: number;
  montant_tva: number;
  montant_ttc: number;
  statut: string;
  date_emission: string | null;
  date_echeance: string | null;
  nombre_missions: number | null;
  etablissement_id: string;
  periode_debut: string | null;
  periode_fin: string | null;
  etablissement: {
    nom: string;
    email_contact: string | null;
    telephone_contact: string | null;
    type: string | null;
    adresse_ville: string | null;
    taux_commission_negocie: number | null;
    groupe_sante_id: string | null;
  } | null;
  missions: MissionDetail[];
  joursRetard: number;
  relances: number;
}

interface MissionDetail {
  id: string;
  intitule: string;
  debut_le: string | null;
  fin_le: string | null;
  duree_heures: number | null;
  taux_horaire_base: number | null;
  total_brut: number | null;
  montant_commission_ht: number | null;
  montant_commission_ttc: number | null;
  soignant_nom: string | null;
  profession_requise: string | null;
}

export default function AdminImpayees() {
  usePageTitle('Factures impayées');
  const navigate = useNavigate();
  const [factures, setFactures] = useState<FactureImpayee[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [sendingRelance, setSendingRelance] = useState<string | null>(null);
  const [sendingAll, setSendingAll] = useState(false);

  const charger = async () => {
    setLoading(true);

    const { data: rawFactures } = await supabase
      .from('factures')
      .select('id, numero_facture, montant_ht, montant_tva, montant_ttc, statut, date_emission, date_echeance, nombre_missions, etablissement_id, periode_debut, periode_fin')
      .in('statut', ['EMISE', 'EN_RETARD'])
      .order('date_echeance', { ascending: true });

    if (!rawFactures || rawFactures.length === 0) {
      setFactures([]);
      setLoading(false);
      return;
    }

    // Fetch établissements
    const etabIds = [...new Set(rawFactures.map(f => f.etablissement_id))];
    const { data: etabs } = await supabase
      .from('etablissements')
      .select('id, nom, email_contact, telephone_contact, type, adresse_ville, taux_commission_negocie, groupe_sante_id')
      .in('id', etabIds);

    const etabMap: Record<string, any> = {};
    for (const e of (etabs ?? [])) etabMap[e.id] = e;

    // Fetch missions liées aux factures
    const factureIds = rawFactures.map(f => f.id);
    const { data: missions } = await supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, montant_commission_ht, montant_commission_ttc, soignant_assigne_id, profession_requise, facture_id')
      .in('facture_id', factureIds);

    // Fetch soignant names
    const soignantIds = [...new Set((missions ?? []).map(m => m.soignant_assigne_id).filter(Boolean))];
    const { data: soignants } = soignantIds.length > 0
      ? await supabase.from('soignants').select('id, prenom, nom').in('id', soignantIds)
      : { data: [] };

    const soignantMap: Record<string, string> = {};
    for (const s of (soignants ?? [])) soignantMap[s.id] = `${s.prenom || ''} ${s.nom || ''}`.trim();

    // Fetch relance count from notifications
    // Accepte l'ancien 'RELANCE_FACTURE' (pré-fix) pour préserver l'historique.
    const { data: relances } = await supabase
      .from('notifications')
      .select('id, destinataire_id, type')
      .in('destinataire_id', etabIds)
      .in('type', ['RAPPEL_FACTURE', 'RELANCE_FACTURE']);

    const relanceCountMap: Record<string, number> = {};
    for (const r of (relances ?? [])) {
      relanceCountMap[r.destinataire_id] = (relanceCountMap[r.destinataire_id] || 0) + 1;
    }

    // Build mission map by facture_id
    const missionsByFacture: Record<string, MissionDetail[]> = {};
    for (const m of (missions ?? [])) {
      const fId = (m as any).facture_id;
      if (!fId) continue;
      if (!missionsByFacture[fId]) missionsByFacture[fId] = [];
      missionsByFacture[fId].push({
        id: m.id,
        intitule: m.intitule,
        debut_le: m.debut_le,
        fin_le: m.fin_le,
        duree_heures: m.duree_heures,
        taux_horaire_base: m.taux_horaire_base,
        total_brut: m.total_brut,
        montant_commission_ht: m.montant_commission_ht,
        montant_commission_ttc: m.montant_commission_ttc,
        soignant_nom: m.soignant_assigne_id ? soignantMap[m.soignant_assigne_id] || '—' : '—',
        profession_requise: m.profession_requise,
      });
    }

    const enriched: FactureImpayee[] = rawFactures.map(f => {
      const echeance = f.date_echeance ? new Date(f.date_echeance) : null;
      const joursRetard = echeance ? differenceInDays(new Date(), echeance) : 0;
      return {
        ...f,
        etablissement: etabMap[f.etablissement_id] || null,
        missions: missionsByFacture[f.id] || [],
        joursRetard: Math.max(0, joursRetard),
        relances: relanceCountMap[f.etablissement_id] || 0,
      };
    });

    // Sort: most overdue first
    enriched.sort((a, b) => b.joursRetard - a.joursRetard);
    setFactures(enriched);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const envoyerRelance = async (facture: FactureImpayee) => {
    if (!facture.etablissement?.email_contact) {
      toast.error('Pas d\'email de contact pour cet établissement');
      return;
    }
    setSendingRelance(facture.id);
    try {
      await supabase.functions.invoke('send-email', {
        body: {
          type: 'RAPPEL_FACTURE',
          data: {
            numero: facture.numero_facture,
            facture_id: facture.id,
            montant_ttc: facture.montant_ttc.toFixed(2),
            date_echeance: fmtDate(facture.date_echeance),
            jours_retard: facture.joursRetard,
            etablissement_nom: facture.etablissement.nom,
          },
          destinataire_email: facture.etablissement.email_contact,
        },
      });

      // Log notification
      await supabase.from('notifications').insert({
        destinataire_id: facture.etablissement_id,
        type: 'RAPPEL_FACTURE',
        type_destinataire: 'ETABLISSEMENT',
        titre: `Relance facture ${facture.numero_facture}`,
        corps: `Rappel : facture ${facture.numero_facture} de ${fmt(facture.montant_ttc)} en retard de ${facture.joursRetard} jour(s).`,
        lien: '/etablissement/facturation',
      } as any);

      toast.success(`Relance envoyée à ${facture.etablissement.nom}`);
      charger();
    } catch {
      toast.error('Erreur lors de l\'envoi');
    }
    setSendingRelance(null);
  };

  const envoyerToutesRelances = async () => {
    const facturesRelancables = factures.filter(f => f.etablissement?.email_contact && f.joursRetard > 0);
    if (facturesRelancables.length === 0) {
      toast.info('Aucune facture à relancer');
      return;
    }
    setSendingAll(true);
    let ok = 0;
    for (const f of facturesRelancables) {
      try {
        await envoyerRelance(f);
        ok++;
      } catch { /* continue */ }
    }
    toast.success(`${ok} relance(s) envoyée(s)`);
    setSendingAll(false);
    charger();
  };

  const marquerEnRetard = async (factureId: string) => {
    const { data, error } = await supabase.rpc('fn_admin_marquer_facture_en_retard' as any, { p_facture_id: factureId });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur lors de la mise à jour du statut');
      return;
    }
    toast.success('Facture marquée en retard');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Factures impayées" /></LayoutAdmin>;

  const totalImpaye = factures.reduce((s, f) => s + f.montant_ttc, 0);
  const nbEnRetard = factures.filter(f => f.joursRetard > 0).length;
  const retardMoyen = factures.length > 0
    ? Math.round(factures.reduce((s, f) => s + f.joursRetard, 0) / factures.length)
    : 0;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Factures impayées" />
      <div className="space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
              <AlertTriangle className="h-6 w-6 text-destructive" /> Factures impayées
            </h1>
            <p className="text-sm text-muted-foreground mt-1">{factures.length} facture{factures.length > 1 ? 's' : ''} en attente de paiement</p>
          </div>
          <BoutonY2K onClick={envoyerToutesRelances} disabled={sendingAll} loading={sendingAll} variant="destructive" className="gap-2" iconeGauche={sendingAll ? undefined : <Send className="h-4 w-4" />}>
            Relancer toutes les factures
          </BoutonY2K>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="p-4 rounded-xl border-2 border-destructive/30 bg-destructive/5">
            <p className="text-2xl font-bold text-destructive">{fmt(totalImpaye)}</p>
            <p className="text-xs text-muted-foreground">Total impayé</p>
          </div>
          <div className="p-4 rounded-xl border border-border bg-card">
            <p className="text-2xl font-bold text-foreground">{factures.length}</p>
            <p className="text-xs text-muted-foreground">Factures</p>
          </div>
          <div className="p-4 rounded-xl border border-border bg-card">
            <p className="text-2xl font-bold text-warning">{nbEnRetard}</p>
            <p className="text-xs text-muted-foreground">En retard</p>
          </div>
          <div className="p-4 rounded-xl border border-border bg-card">
            <p className="text-2xl font-bold text-foreground">{retardMoyen}j</p>
            <p className="text-xs text-muted-foreground">Retard moyen</p>
          </div>
        </div>

        {/* Liste des factures */}
        {factures.length === 0 ? (
          <div className="py-12 text-center">
            <p className="text-lg font-semibold text-success">Aucune facture impayée</p>
            <p className="text-sm text-muted-foreground mt-1">Tout est à jour</p>
          </div>
        ) : (
          <div className="space-y-3">
            {factures.map(f => {
              const isExpanded = expandedId === f.id;
              const urgenceLevel = f.joursRetard >= 60 ? 'critique' : f.joursRetard >= 30 ? 'haute' : f.joursRetard >= 7 ? 'moyenne' : 'basse';
              const urgenceColor = urgenceLevel === 'critique' ? 'border-destructive/60 bg-destructive/5' :
                urgenceLevel === 'haute' ? 'border-warning/60 bg-warning/5' :
                urgenceLevel === 'moyenne' ? 'border-orange-300/60 bg-orange-50 dark:bg-orange-900/10' :
                'border-border bg-card';

              return (
                <CardY2K noPadding key={f.id} className={`${urgenceColor} transition-all`}>
                  <CardY2KContent className="pt-4 space-y-0">
                    {/* Header cliquable */}
                    <button
                      onClick={() => setExpandedId(isExpanded ? null : f.id)}
                      className="w-full text-left"
                    >
                      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                        <div className="flex items-center gap-3">
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="font-bold text-foreground text-lg">{f.numero_facture}</span>
                              <Badge variant={f.statut === 'EN_RETARD' ? 'destructive' : 'secondary'}>
                                {f.statut === 'EN_RETARD' ? `${f.joursRetard}j de retard` : 'Émise'}
                              </Badge>
                              {f.relances > 0 && (
                                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-warning/10 text-warning">
                                  {f.relances} relance{f.relances > 1 ? 's' : ''}
                                </span>
                              )}
                            </div>
                            <p className="text-sm text-muted-foreground mt-0.5">
                              <Building2 className="h-3 w-3 inline mr-1" />
                              {f.etablissement?.nom || '—'}
                              {f.etablissement?.adresse_ville && ` · ${f.etablissement.adresse_ville}`}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-3">
                          <div className="text-right">
                            <p className="text-xl font-bold text-destructive">{fmt(f.montant_ttc)}</p>
                            <p className="text-[10px] text-muted-foreground">
                              HT: {fmt(f.montant_ht)} · TVA: {fmt(f.montant_tva)}
                            </p>
                          </div>
                          {isExpanded ? <ChevronUp className="h-4 w-4 text-muted-foreground" /> : <ChevronDown className="h-4 w-4 text-muted-foreground" />}
                        </div>
                      </div>
                    </button>

                    {/* Détails expanded */}
                    {isExpanded && (
                      <div className="mt-4 space-y-4 border-t border-border pt-4">
                        {/* Infos facture */}
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                          <div>
                            <p className="text-xs text-muted-foreground">Émise le</p>
                            <p className="font-medium text-foreground">{fmtDate(f.date_emission)}</p>
                          </div>
                          <div>
                            <p className="text-xs text-muted-foreground">Échéance</p>
                            <p className="font-medium text-destructive">{fmtDate(f.date_echeance)}</p>
                          </div>
                          <div>
                            <p className="text-xs text-muted-foreground">Période</p>
                            <p className="font-medium text-foreground">{fmtDate(f.periode_debut)} → {fmtDate(f.periode_fin)}</p>
                          </div>
                          <div>
                            <p className="text-xs text-muted-foreground">Taux commission</p>
                            <p className="font-medium text-foreground">{f.etablissement?.taux_commission_negocie ?? 15}%</p>
                          </div>
                        </div>

                        {/* Missions détaillées */}
                        {f.missions.length > 0 && (
                          <div>
                            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">
                              Missions ({f.missions.length})
                            </p>
                            {/* Desktop table */}
                            <div className="hidden md:block overflow-x-auto">
                              <table className="w-full text-xs">
                                <thead>
                                  <tr className="border-b border-border text-muted-foreground">
                                    <th className="pb-1.5 text-left font-medium">Mission</th>
                                    <th className="pb-1.5 text-left font-medium">Soignant</th>
                                    <th className="pb-1.5 text-center font-medium">Dates</th>
                                    <th className="pb-1.5 text-center font-medium">Heures</th>
                                    <th className="pb-1.5 text-right font-medium">Taux/h</th>
                                    <th className="pb-1.5 text-right font-medium">Brut</th>
                                    <th className="pb-1.5 text-right font-medium">Com. TTC</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  {f.missions.map(m => (
                                    <tr key={m.id} className="border-b border-border/30">
                                      <td className="py-1.5">
                                        <button onClick={() => navigate(`/admin/missions`)} className="text-primary hover:underline text-left">
                                          {m.intitule}
                                        </button>
                                        {m.profession_requise && <p className="text-[10px] text-muted-foreground">{m.profession_requise}</p>}
                                      </td>
                                      <td className="py-1.5 text-foreground">{m.soignant_nom}</td>
                                      <td className="py-1.5 text-center text-muted-foreground">
                                        {m.debut_le ? fmtDate(m.debut_le) : '—'}
                                      </td>
                                      <td className="py-1.5 text-center font-medium">{m.duree_heures ?? '—'}h</td>
                                      <td className="py-1.5 text-right text-muted-foreground">{m.taux_horaire_base ? `${m.taux_horaire_base}€` : '—'}</td>
                                      <td className="py-1.5 text-right font-medium">{m.total_brut ? fmt(m.total_brut) : '—'}</td>
                                      <td className="py-1.5 text-right font-bold text-foreground">{m.montant_commission_ttc ? fmt(m.montant_commission_ttc) : '—'}</td>
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                            </div>
                            {/* Mobile cards */}
                            <div className="md:hidden space-y-2">
                              {f.missions.map(m => (
                                <div key={m.id} className="rounded-lg border border-border/50 bg-muted/20 p-3 space-y-2">
                                  <div>
                                    <button onClick={() => navigate(`/admin/missions`)} className="text-primary hover:underline text-left text-xs font-medium">
                                      {m.intitule}
                                    </button>
                                    {m.profession_requise && <p className="text-[10px] text-muted-foreground">{m.profession_requise}</p>}
                                  </div>
                                  <p className="text-xs text-foreground">{m.soignant_nom}</p>
                                  <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                                    <div>
                                      <p className="text-muted-foreground">Début</p>
                                      <p className="text-foreground">{m.debut_le ? fmtDate(m.debut_le) : '—'}</p>
                                    </div>
                                    <div>
                                      <p className="text-muted-foreground">Heures</p>
                                      <p className="font-medium text-foreground">{m.duree_heures ?? '—'}h</p>
                                    </div>
                                    <div>
                                      <p className="text-muted-foreground">Taux/h</p>
                                      <p className="text-foreground">{m.taux_horaire_base ? `${m.taux_horaire_base}€` : '—'}</p>
                                    </div>
                                    <div>
                                      <p className="text-muted-foreground">Brut</p>
                                      <p className="font-medium text-foreground">{m.total_brut ? fmt(m.total_brut) : '—'}</p>
                                    </div>
                                    <div className="col-span-2">
                                      <p className="text-muted-foreground">Com. TTC</p>
                                      <p className="font-bold text-foreground">{m.montant_commission_ttc ? fmt(m.montant_commission_ttc) : '—'}</p>
                                    </div>
                                  </div>
                                </div>
                              ))}
                            </div>
                          </div>
                        )}

                        {f.missions.length === 0 && (
                          <p className="text-xs text-muted-foreground italic">Aucune mission liée à cette facture</p>
                        )}

                        {/* Contact + Actions */}
                        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-t border-border pt-3">
                          <div className="flex flex-wrap gap-2 text-xs">
                            {f.etablissement?.email_contact && (
                              <a href={`mailto:${f.etablissement.email_contact}`} className="inline-flex items-center gap-1 text-primary hover:underline">
                                <Mail className="h-3 w-3" /> {f.etablissement.email_contact}
                              </a>
                            )}
                            {f.etablissement?.telephone_contact && (
                              <a href={`tel:${f.etablissement.telephone_contact}`} className="inline-flex items-center gap-1 text-primary hover:underline">
                                <Phone className="h-3 w-3" /> {f.etablissement.telephone_contact}
                              </a>
                            )}
                          </div>
                          <div className="flex flex-wrap gap-2">
                            <BoutonY2K
                              size="sm" variant="destructive" className="gap-1 text-xs"
                              onClick={() => envoyerRelance(f)}
                              disabled={sendingRelance === f.id}
                              loading={sendingRelance === f.id}
                              iconeGauche={sendingRelance === f.id ? undefined : <Send className="h-3 w-3" />}
                            >
                              Envoyer une relance
                            </BoutonY2K>
                            {f.statut === 'EMISE' && f.joursRetard > 0 && (
                              <BoutonY2K size="sm" variant="secondary" className="gap-1 text-xs" onClick={() => marquerEnRetard(f.id)} iconeGauche={<Clock className="h-3 w-3" />}>
                                Marquer en retard
                              </BoutonY2K>
                            )}
                            <BoutonY2K size="sm" variant="secondary" className="gap-1 text-xs" onClick={() => navigate(`/admin/utilisateurs/${f.etablissement_id}`)} iconeGauche={<Building2 className="h-3 w-3" />}>
                              Fiche établissement
                            </BoutonY2K>
                          </div>
                        </div>
                      </div>
                    )}
                  </CardY2KContent>
                </CardY2K>
              );
            })}
          </div>
        )}
      </div>
    </LayoutAdmin>
  );
}
