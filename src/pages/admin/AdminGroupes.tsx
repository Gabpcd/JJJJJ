import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Building2, Save, Loader2, ChevronDown, TrendingUp, CreditCard, Users, Mail, Percent, Activity, Euro, Calendar, Send, Edit3 } from 'lucide-react';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';
import { getLabelTypeEtablissement } from '@/lib/constantes';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const fmtPct = (v: number) => `${v.toFixed(1)}%`;

interface GroupeData {
  id: string;
  nom: string;
  siren: string | null;
  nom_marque: string | null;
  remise_groupe_pourcent: number;
  formule_abonnement: string | null;
  bfa_eligible: boolean;
  email_admin: string | null;
  telephone_admin: string | null;
  cliniques: CliniqueStat[];
  totals: {
    missions: number;
    missions_en_cours: number;
    missions_terminees: number;
    ca_commissions: number;
    ca_commissions_payees: number;
    ca_commissions_impayees: number;
    soignants_uniques: number;
  };
}

interface CliniqueStat {
  id: string;
  nom: string;
  adresse_ville: string | null;
  type: string | null;
  email_contact: string | null;
  taux_commission_negocie: number | null;
  nb_missions: number;
  nb_missions_en_cours: number;
  nb_missions_terminees: number;
  ca_commissions: number;
  ca_payees: number;
  ca_impayees: number;
  nb_soignants: number;
}

export default function AdminGroupes() {
  usePageTitle('Groupes de santé');
  const navigate = useNavigate();
  const [groupes, setGroupes] = useState<GroupeData[]>([]);
  const [loading, setLoading] = useState(true);
  const [editingTaux, setEditingTaux] = useState<{ etabId: string; taux: string } | null>(null);
  const [savingTaux, setSavingTaux] = useState(false);
  const [emailGroupeId, setEmailGroupeId] = useState<string | null>(null);
  const [emailClinicId, setEmailClinicId] = useState<string | null>(null);
  const [emailSubject, setEmailSubject] = useState('');
  const [emailBody, setEmailBody] = useState('');
  const [sendingEmail, setSendingEmail] = useState(false);

  const charger = async () => {
    setLoading(true);

    const { data: rawGroupes } = await supabase
      .from('groupes_sante')
      .select('id, nom, siren, nom_marque, remise_groupe_pourcent, formule_abonnement, bfa_eligible, email_admin, telephone_admin')
      .is('supprime_le', null)
      .order('nom');

    if (!rawGroupes) { setLoading(false); return; }

    const enriched: GroupeData[] = [];

    for (const g of rawGroupes) {
      // Cliniques du groupe
      const { data: etabs } = await supabase
        .from('etablissements')
        .select('id, nom, adresse_ville, type, email_contact, taux_commission_negocie')
        .eq('groupe_sante_id', g.id)
        .is('supprime_le', null)
        .order('nom');

      const etabIds = (etabs ?? []).map(e => e.id);
      let cliniques: CliniqueStat[] = [];
      let totalMissions = 0, totalEnCours = 0, totalTerminees = 0;
      let totalCa = 0, totalPayees = 0, totalImpayees = 0;
      let allSoignantIds = new Set<string>();

      if (etabIds.length > 0) {
        // 2 requêtes batch au lieu de N×2 requêtes par clinique
        const [resMissions, resFactures] = await Promise.all([
          supabase.from('missions')
            .select('id, statut, soignant_assigne_id, montant_commission_ht, montant_commission_ttc, etablissement_id')
            .in('etablissement_id', etabIds),
          supabase.from('factures')
            .select('montant_ttc, statut, etablissement_id')
            .in('etablissement_id', etabIds),
        ]);

        const allMissions = resMissions.data ?? [];
        const allFactures = resFactures.data ?? [];

        for (const etab of (etabs ?? [])) {
          const missions = allMissions.filter(m => m.etablissement_id === etab.id);
          const factures = allFactures.filter(f => f.etablissement_id === etab.id);

          const nbMissions = missions.length;
          const nbEnCours = missions.filter(m => ['OUVERTE', 'ASSIGNEE', 'EN_COURS'].includes(m.statut)).length;
          const nbTerminees = missions.filter(m => m.statut === 'TERMINEE').length;
          const caCommissions = missions
            .filter(m => m.statut === 'TERMINEE')
            .reduce((s, m) => s + (Number(m.montant_commission_ttc) || 0), 0);
          const caPayees = factures.filter(f => f.statut === 'PAYEE').reduce((s, f) => s + (Number(f.montant_ttc) || 0), 0);
          const caImpayees = factures.filter(f => ['EMISE', 'EN_RETARD'].includes(f.statut)).reduce((s, f) => s + (Number(f.montant_ttc) || 0), 0);
          const soignantIds = new Set(missions.map(m => m.soignant_assigne_id).filter(Boolean));

          cliniques.push({
            id: etab.id,
            nom: etab.nom,
            adresse_ville: etab.adresse_ville,
            type: etab.type,
            email_contact: etab.email_contact,
            taux_commission_negocie: etab.taux_commission_negocie,
            nb_missions: nbMissions,
            nb_missions_en_cours: nbEnCours,
            nb_missions_terminees: nbTerminees,
            ca_commissions: caCommissions,
            ca_payees: caPayees,
            ca_impayees: caImpayees,
            nb_soignants: soignantIds.size,
          });

          totalMissions += nbMissions;
          totalEnCours += nbEnCours;
          totalTerminees += nbTerminees;
          totalCa += caCommissions;
          totalPayees += caPayees;
          totalImpayees += caImpayees;
          soignantIds.forEach(id => allSoignantIds.add(id));
        }
      }

      // File de travail (Session D) : cliniques avec impayés en tête (montant
      // décroissant), puis par activité en cours — l'alphabétique noyait les relances.
      cliniques.sort((a, b) =>
        (b.ca_impayees - a.ca_impayees)
        || (b.nb_missions_en_cours - a.nb_missions_en_cours)
        || a.nom.localeCompare(b.nom));

      enriched.push({
        ...g,
        remise_groupe_pourcent: Number(g.remise_groupe_pourcent) || 0,
        cliniques,
        totals: {
          missions: totalMissions,
          missions_en_cours: totalEnCours,
          missions_terminees: totalTerminees,
          ca_commissions: totalCa,
          ca_commissions_payees: totalPayees,
          ca_commissions_impayees: totalImpayees,
          soignants_uniques: allSoignantIds.size,
        },
      });
    }

    // Même logique au niveau groupe : CA impayé décroissant d'abord.
    enriched.sort((a, b) =>
      (b.totals.ca_commissions_impayees - a.totals.ca_commissions_impayees)
      || a.nom.localeCompare(b.nom));

    setGroupes(enriched);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const modifierTaux = async () => {
    if (!editingTaux) return;
    const taux = parseFloat(editingTaux.taux);
    if (isNaN(taux) || taux < 0 || taux > 50) {
      toast.error('Le taux doit être entre 0% et 50%');
      return;
    }
    setSavingTaux(true);
    const { data, error } = await supabase.rpc('fn_admin_modifier_taux_commission' as any, {
      p_etablissement_id: editingTaux.etabId,
      p_groupe_id: null,
      p_nouveau_taux: taux,
      p_raison: 'Modification depuis interface admin',
    });
    setSavingTaux(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur'); return; }
    toast.success(`Taux mis à jour : ${taux}%`);
    setEditingTaux(null);
    charger();
  };

  const [editingTauxGroupe, setEditingTauxGroupe] = useState<{ groupeId: string; taux: string } | null>(null);

  const modifierTauxGroupe = async (groupeId: string) => {
    if (!editingTauxGroupe) return;
    const taux = parseFloat(editingTauxGroupe.taux);
    if (isNaN(taux) || taux < 0 || taux > 50) {
      toast.error('Le taux doit être entre 0% et 50%');
      return;
    }
    setSavingTaux(true);
    const { data, error } = await supabase.rpc('fn_admin_modifier_taux_commission' as any, {
      p_etablissement_id: null,
      p_groupe_id: groupeId,
      p_nouveau_taux: taux,
      p_raison: 'Modification groupe depuis interface admin',
    });
    setSavingTaux(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur mise à jour groupe'); return; }
    toast.success(`Taux de ${taux}% appliqué au groupe`);
    setEditingTauxGroupe(null);
    charger();
  };

  const [editingRemise, setEditingRemise] = useState<{ groupeId: string; remise: string } | null>(null);
  const [savingRemise, setSavingRemise] = useState(false);

  const modifierRemise = async (groupeId: string) => {
    if (!editingRemise) return;
    const remise = parseFloat(editingRemise.remise);
    if (isNaN(remise) || remise < 0 || remise > 100) {
      toast.error('La remise doit être entre 0 % et 100 %');
      return;
    }
    setSavingRemise(true);
    const { data, error } = await supabase.rpc('fn_admin_modifier_remise_groupe' as any, {
      p_groupe_id: groupeId,
      p_remise: remise,
      p_raison: 'Modification depuis interface admin',
    });
    setSavingRemise(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur mise à jour remise'); return; }
    toast.success(`Remise groupe : ${remise} %`);
    setEditingRemise(null);
    charger();
  };

  const envoyerEmail = async (destinataires: string[], groupeNom: string) => {
    if (!emailSubject.trim() || !emailBody.trim()) {
      toast.error('Sujet et contenu requis');
      return;
    }
    setSendingEmail(true);
    try {
      for (const email of destinataires.filter(Boolean)) {
        await supabase.functions.invoke('send-email', {
          body: {
            type: 'ADMIN_BROADCAST',
            data: { subject: emailSubject, body: emailBody, groupe: groupeNom },
            destinataire_email: email,
          },
        });
      }
      toast.success(`Email envoyé à ${destinataires.filter(Boolean).length} destinataire(s)`);
      setEmailGroupeId(null);
      setEmailClinicId(null);
      setEmailSubject('');
      setEmailBody('');
    } catch {
      toast.error('Erreur lors de l\'envoi');
    }
    setSendingEmail(false);
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Groupes" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
          <Building2 className="h-6 w-6 text-primary" /> Groupes de santé
        </h1>

        {groupes.length === 0 && (
          <p className="text-sm text-muted-foreground text-center py-8">Aucun groupe de santé enregistré.</p>
        )}

        {groupes.map(g => (
          <CardY2K noPadding key={g.id}>
            <CardY2KContent className="pt-6 space-y-5">
              {/* Header */}
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                <div>
                  <h2 className="text-xl font-bold text-foreground">{g.nom}</h2>
                  <div className="flex flex-wrap gap-3 text-xs text-muted-foreground mt-1">
                    {g.siren && <span>SIREN: {g.siren}</span>}
                    <span>Formule: <strong className="text-foreground">{g.formule_abonnement || '—'}</strong></span>
                    {editingRemise?.groupeId === g.id ? (
                      <span className="inline-flex items-center gap-1">
                        Remise groupe:
                        <Input
                          type="number" step="0.5" min="0" max="100"
                          value={editingRemise.remise}
                          onChange={e => setEditingRemise({ ...editingRemise, remise: e.target.value })}
                          className="w-16 h-6 text-xs text-center inline-block"
                        />%
                        <button onClick={() => modifierRemise(g.id)} disabled={savingRemise} className="text-primary font-semibold hover:underline disabled:opacity-50">{savingRemise ? '…' : 'OK'}</button>
                        <button onClick={() => setEditingRemise(null)} className="text-muted-foreground hover:underline">Annuler</button>
                      </span>
                    ) : (
                      <span>
                        Remise groupe: <strong className="text-foreground">{fmtPct(g.remise_groupe_pourcent)}</strong>
                        <button
                          onClick={() => setEditingRemise({ groupeId: g.id, remise: String(g.remise_groupe_pourcent ?? 0) })}
                          className="ml-1 text-primary hover:underline"
                          title="Modifier la remise du groupe"
                          aria-label="Modifier le groupe"
                        ><Edit3 className="h-4 w-4" /></button>
                      </span>
                    )}
                    <span>{g.cliniques.length} clinique{g.cliniques.length > 1 ? 's' : ''}</span>
                  </div>
                </div>
                <div className="flex flex-wrap gap-2">
                  {editingTauxGroupe?.groupeId === g.id ? (
                    <div className="flex items-center gap-1">
                      <span className="text-xs text-muted-foreground">Taux groupe :</span>
                      <Input
                        type="number" step="0.5" min="0" max="50"
                        value={editingTauxGroupe.taux}
                        onChange={e => setEditingTauxGroupe({ ...editingTauxGroupe, taux: e.target.value })}
                        className="w-20 h-8 text-xs text-center"
                      />
                      <span className="text-xs">%</span>
                      <BoutonY2K size="sm" onClick={() => modifierTauxGroupe(g.id)} disabled={savingTaux} loading={savingTaux} className="h-8 text-xs gap-1" iconeGauche={savingTaux ? undefined : <Save className="h-3 w-3" />}>
                        Appliquer au groupe
                      </BoutonY2K>
                      <BoutonY2K size="sm" variant="ghost" className="h-8 text-xs" onClick={() => setEditingTauxGroupe(null)}>Annuler</BoutonY2K>
                    </div>
                  ) : (
                    <BoutonY2K size="sm" variant="secondary" className="gap-1 text-xs" onClick={() => setEditingTauxGroupe({ groupeId: g.id, taux: String(g.cliniques[0]?.taux_commission_negocie ?? 15) })} iconeGauche={<Percent className="h-3.5 w-3.5" />}>
                      Modifier taux du groupe
                    </BoutonY2K>
                  )}
                  <BoutonY2K size="sm" variant="secondary" className="gap-1 text-xs" onClick={() => {
                    setEmailGroupeId(g.id);
                    setEmailClinicId(null);
                  }} iconeGauche={<Mail className="h-3.5 w-3.5" />}>
                    Email au groupe
                  </BoutonY2K>
                </div>
              </div>

              {/* KPIs groupe — cliquables */}
              <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
                <button
                  type="button"
                  onClick={() => navigate(`/admin/missions?groupe=${g.id}`)}
                  className="text-left p-3 rounded-xl bg-primary/5 border border-primary/20 hover:border-primary/50 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-foreground">{g.totals.missions}</p>
                  <p className="text-[10px] text-muted-foreground">Missions</p>
                </button>
                <button
                  type="button"
                  onClick={() => navigate(`/admin/missions?groupe=${g.id}&statut=EN_COURS`)}
                  className="text-left p-3 rounded-xl bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 hover:border-blue-400 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-foreground">{g.totals.missions_en_cours}</p>
                  <p className="text-[10px] text-muted-foreground">En cours</p>
                </button>
                <button
                  type="button"
                  onClick={() => navigate(`/admin/missions?groupe=${g.id}&statut=TERMINEE`)}
                  className="text-left p-3 rounded-xl bg-success/5 border border-success/20 hover:border-success/50 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-foreground">{g.totals.missions_terminees}</p>
                  <p className="text-[10px] text-muted-foreground">Terminées</p>
                </button>
                <button
                  type="button"
                  onClick={() => navigate('/admin/finances')}
                  className="text-left p-3 rounded-xl bg-primary/5 border border-primary/20 hover:border-primary/50 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-foreground">{fmt(g.totals.ca_commissions)}</p>
                  <p className="text-[10px] text-muted-foreground">CA commissions</p>
                </button>
                <button
                  type="button"
                  onClick={() => navigate('/admin/facturation')}
                  className="text-left p-3 rounded-xl bg-success/5 border border-success/20 hover:border-success/50 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-success">{fmt(g.totals.ca_commissions_payees)}</p>
                  <p className="text-[10px] text-muted-foreground">Payées</p>
                </button>
                <button
                  type="button"
                  onClick={() => navigate('/admin/impayees')}
                  className="text-left p-3 rounded-xl bg-destructive/5 border border-destructive/20 hover:border-destructive/50 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-destructive">{fmt(g.totals.ca_commissions_impayees)}</p>
                  <p className="text-[10px] text-muted-foreground">Impayées</p>
                </button>
                <button
                  type="button"
                  onClick={() => navigate('/admin/utilisateurs')}
                  className="text-left p-3 rounded-xl bg-muted/50 border border-border hover:border-muted-foreground/30 transition-colors cursor-pointer"
                >
                  <p className="text-lg font-bold text-foreground">{g.totals.soignants_uniques}</p>
                  <p className="text-[10px] text-muted-foreground">Soignants</p>
                </button>
              </div>

              {/* BFA projection */}
              {g.bfa_eligible && (
                <div className="rounded-lg bg-primary/5 border border-primary/20 p-3 flex items-center gap-2">
                  <TrendingUp className="h-4 w-4 text-primary shrink-0" />
                  <p className="text-xs text-primary font-medium">BFA éligible — projection calculable via fn_calculer_bfa</p>
                </div>
              )}

              {/* Email form */}
              {emailGroupeId === g.id && !emailClinicId && (
                <div className="rounded-lg border border-primary/20 bg-primary/5 p-4 space-y-3">
                  <p className="text-sm font-semibold text-foreground flex items-center gap-1.5">
                    <Mail className="h-4 w-4 text-primary" /> Email à tout le groupe ({g.cliniques.length} clinique{g.cliniques.length > 1 ? 's' : ''})
                  </p>
                  <Input value={emailSubject} onChange={e => setEmailSubject(e.target.value)} placeholder="Sujet" className="text-sm" />
                  <textarea
                    value={emailBody} onChange={e => setEmailBody(e.target.value)}
                    placeholder="Contenu du message..."
                    rows={4}
                    className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
                  />
                  <div className="flex gap-2">
                    <BoutonY2K size="sm" onClick={() => envoyerEmail(
                      g.cliniques.map(c => c.email_contact).filter(Boolean) as string[],
                      g.nom
                    )} disabled={sendingEmail} loading={sendingEmail} className="gap-1" iconeGauche={sendingEmail ? undefined : <Send className="h-3.5 w-3.5" />}>
                      Envoyer
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => setEmailGroupeId(null)}>Annuler</BoutonY2K>
                  </div>
                </div>
              )}

              {/* Tableau cliniques */}
              <div>
                <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-3">
                  Détail par clinique
                </h3>
                {/* Desktop : table 9 colonnes */}
                <div className="hidden md:block overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border text-left text-xs text-muted-foreground">
                        <th className="pb-2 font-medium">Clinique</th>
                        <th className="pb-2 font-medium text-center">Missions</th>
                        <th className="pb-2 font-medium text-center">En cours</th>
                        <th className="pb-2 font-medium text-center">Soignants</th>
                        <th className="pb-2 font-medium text-right">CA com.</th>
                        <th className="pb-2 font-medium text-right">Payé</th>
                        <th className="pb-2 font-medium text-right">Impayé</th>
                        <th className="pb-2 font-medium text-center">Taux com.</th>
                        <th className="pb-2 font-medium text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {g.cliniques.map(c => (
                        <React.Fragment key={c.id}>
                          <tr className="border-b border-border/50 hover:bg-muted/30">
                            <td className="py-2.5">
                              <button onClick={() => navigate(`/admin/utilisateurs/${c.id}`)} className="text-primary hover:underline text-left">
                                <p className="font-medium">{c.nom}</p>
                              </button>
                              <p className="text-[10px] text-muted-foreground">{c.adresse_ville} · {getLabelTypeEtablissement(c.type)}</p>
                            </td>
                            <td className="py-2.5 text-center font-medium">{c.nb_missions}</td>
                            <td className="py-2.5 text-center">
                              {c.nb_missions_en_cours > 0 ? (
                                <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400">{c.nb_missions_en_cours}</span>
                              ) : '—'}
                            </td>
                            <td className="py-2.5 text-center">{c.nb_soignants}</td>
                            <td className="py-2.5 text-right font-medium">{fmt(c.ca_commissions)}</td>
                            <td className="py-2.5 text-right text-success font-medium">{fmt(c.ca_payees)}</td>
                            <td className="py-2.5 text-right">
                              {c.ca_impayees > 0 ? (
                                <span className="text-destructive font-bold">{fmt(c.ca_impayees)}</span>
                              ) : '—'}
                            </td>
                            <td className="py-2.5 text-center">
                              {editingTaux?.etabId === c.id ? (
                                <div className="flex items-center gap-1 justify-center">
                                  <Input
                                    type="number" step="0.5" min="0" max="50"
                                    value={editingTaux.taux}
                                    onChange={e => setEditingTaux({ ...editingTaux, taux: e.target.value })}
                                    className="w-16 h-7 text-xs text-center"
                                  />
                                  <span className="text-xs">%</span>
                                  <BoutonY2K size="sm" variant="ghost" className="h-7 w-7 p-0" onClick={modifierTaux} disabled={savingTaux} loading={savingTaux} aria-label="Enregistrer">
                                    {!savingTaux && <Save className="h-3 w-3" />}
                                  </BoutonY2K>
                                </div>
                              ) : (
                                <button
                                  onClick={() => setEditingTaux({ etabId: c.id, taux: String(c.taux_commission_negocie ?? 15) })}
                                  className="text-xs font-bold text-primary hover:underline"
                                >
                                  {c.taux_commission_negocie ?? 15}%
                                </button>
                              )}
                            </td>
                            <td className="py-2.5 text-right">
                              <div className="flex gap-1 justify-end">
                                <BoutonY2K size="sm" variant="ghost" className="h-7 px-2 text-xs" onClick={() => {
                                  setEmailClinicId(c.id);
                                  setEmailGroupeId(g.id);
                                }} aria-label="Envoyer un email">
                                  <Mail className="h-3 w-3" />
                                </BoutonY2K>
                              </div>
                            </td>
                          </tr>
                          {/* Email form pour clinique */}
                          {emailClinicId === c.id && emailGroupeId === g.id && (
                            <tr>
                              <td colSpan={9} className="py-2 px-2">
                                <div className="rounded-lg border border-border bg-muted/30 p-3 space-y-2">
                                  <p className="text-xs font-semibold">Email à {c.nom}</p>
                                  <Input value={emailSubject} onChange={e => setEmailSubject(e.target.value)} placeholder="Sujet" className="text-xs h-8" />
                                  <textarea
                                    value={emailBody} onChange={e => setEmailBody(e.target.value)}
                                    placeholder="Contenu..." rows={3}
                                    className="w-full rounded-lg border border-border bg-background px-3 py-2 text-xs resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
                                  />
                                  <div className="flex gap-2">
                                    <BoutonY2K size="sm" onClick={() => envoyerEmail(
                                      c.email_contact ? [c.email_contact] : [],
                                      c.nom
                                    )} disabled={sendingEmail} loading={sendingEmail} className="gap-1 text-xs" iconeGauche={sendingEmail ? undefined : <Send className="h-3 w-3" />}>
                                      Envoyer
                                    </BoutonY2K>
                                    <BoutonY2K size="sm" variant="ghost" className="text-xs" onClick={() => setEmailClinicId(null)}>Annuler</BoutonY2K>
                                  </div>
                                </div>
                              </td>
                            </tr>
                          )}
                        </React.Fragment>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* Mobile : cards par clinique */}
                <div className="md:hidden space-y-3">
                  {g.cliniques.length === 0 ? (
                    <p className="text-center text-muted-foreground py-6 text-sm">Aucune clinique</p>
                  ) : g.cliniques.map(c => (
                    <div key={c.id} className={`rounded-xl border p-3 space-y-3 ${c.ca_impayees > 0 ? 'border-destructive/40 bg-destructive/5' : 'border-border bg-card'}`}>
                      <div className="flex items-start justify-between gap-2">
                        <button
                          type="button"
                          onClick={() => navigate(`/admin/utilisateurs/${c.id}`)}
                          className="text-left flex-1 min-w-0"
                        >
                          <p className="text-primary hover:underline font-semibold text-sm truncate">{c.nom}</p>
                          <p className="text-[10px] text-muted-foreground">{c.adresse_ville} · {getLabelTypeEtablissement(c.type)}</p>
                        </button>
                        {c.nb_missions_en_cours > 0 && (
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400 shrink-0">
                            {c.nb_missions_en_cours} en cours
                          </span>
                        )}
                      </div>

                      <div className="grid grid-cols-2 gap-2 text-xs">
                        <div>
                          <p className="text-muted-foreground">Missions</p>
                          <p className="font-semibold">{c.nb_missions} · {c.nb_soignants} soignant(s)</p>
                        </div>
                        <div>
                          <p className="text-muted-foreground">Taux com.</p>
                          {editingTaux?.etabId === c.id ? (
                            <div className="flex items-center gap-1">
                              <Input
                                type="number" step="0.5" min="0" max="50"
                                value={editingTaux.taux}
                                onChange={e => setEditingTaux({ ...editingTaux, taux: e.target.value })}
                                className="w-14 h-7 text-xs text-center"
                              />
                              <span className="text-xs">%</span>
                              <BoutonY2K size="sm" variant="ghost" className="h-7 w-7 p-0" onClick={modifierTaux} disabled={savingTaux} loading={savingTaux} aria-label="Enregistrer">
                                {!savingTaux && <Save className="h-3 w-3" />}
                              </BoutonY2K>
                            </div>
                          ) : (
                            <button
                              type="button"
                              onClick={() => setEditingTaux({ etabId: c.id, taux: String(c.taux_commission_negocie ?? 15) })}
                              className="font-bold text-primary hover:underline min-h-[28px] text-sm"
                            >
                              {c.taux_commission_negocie ?? 15}%
                            </button>
                          )}
                        </div>
                        <div>
                          <p className="text-muted-foreground">CA com.</p>
                          <p className="font-semibold">{fmt(c.ca_commissions)}</p>
                        </div>
                        <div>
                          <p className="text-muted-foreground">Payé</p>
                          <p className="font-semibold text-success">{fmt(c.ca_payees)}</p>
                        </div>
                      </div>

                      {c.ca_impayees > 0 && (
                        <p className="text-center text-destructive font-bold text-sm py-1.5 bg-destructive/10 rounded-lg">
                          Impayé : {fmt(c.ca_impayees)}
                        </p>
                      )}

                      <BoutonY2K
                        size="sm"
                        variant="secondary"
                        className="w-full gap-1 text-xs min-h-[36px]"
                        onClick={() => {
                          setEmailClinicId(c.id);
                          setEmailGroupeId(g.id);
                        }}
                        iconeGauche={<Mail className="h-3 w-3" />}
                      >
                        Envoyer un email
                      </BoutonY2K>

                      {emailClinicId === c.id && emailGroupeId === g.id && (
                        <div className="rounded-lg border border-border bg-muted/30 p-3 space-y-2">
                          <p className="text-xs font-semibold">Email à {c.nom}</p>
                          <Input value={emailSubject} onChange={e => setEmailSubject(e.target.value)} placeholder="Sujet" className="text-xs h-8" />
                          <textarea
                            value={emailBody} onChange={e => setEmailBody(e.target.value)}
                            placeholder="Contenu..." rows={3}
                            className="w-full rounded-lg border border-border bg-background px-3 py-2 text-xs resize-none focus:outline-none focus:ring-2 focus:ring-primary/50"
                          />
                          <div className="flex gap-2">
                            <BoutonY2K size="sm" onClick={() => envoyerEmail(
                              c.email_contact ? [c.email_contact] : [],
                              c.nom
                            )} disabled={sendingEmail} loading={sendingEmail} className="gap-1 text-xs flex-1 min-h-[36px]" iconeGauche={sendingEmail ? undefined : <Send className="h-3 w-3" />}>
                              Envoyer
                            </BoutonY2K>
                            <BoutonY2K size="sm" variant="ghost" className="text-xs min-h-[36px]" onClick={() => setEmailClinicId(null)}>Annuler</BoutonY2K>
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </CardY2KContent>
          </CardY2K>
        ))}
      </div>
    </LayoutAdmin>
  );
}
