import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Building2, Save, Loader2, ChevronDown, TrendingUp, CreditCard, Users, Mail, Percent, Activity, Euro, Calendar, Send } from 'lucide-react';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';

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
        // Stats par clinique
        for (const etab of (etabs ?? [])) {
          const [resMissions, resFactures] = await Promise.all([
            supabase.from('missions')
              .select('id, statut, soignant_assigne_id, montant_commission_ht, montant_commission_ttc')
              .eq('etablissement_id', etab.id),
            supabase.from('factures')
              .select('montant_ttc, statut')
              .eq('etablissement_id', etab.id),
          ]);

          const missions = resMissions.data ?? [];
          const factures = resFactures.data ?? [];

          const nbMissions = missions.length;
          // Enum réel : OUVERTE, ASSIGNEE, EN_COURS, TERMINEE, ANNULEE_*, ABSENCE, LITIGE
          const nbEnCours = missions.filter(m => ['OUVERTE', 'ASSIGNEE', 'EN_COURS'].includes(m.statut)).length;
          const nbTerminees = missions.filter(m => m.statut === 'TERMINEE').length;
          // CA commissions = somme des commissions des missions terminées (valeur réelle, pas juste factures)
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
    const { error } = await supabase
      .from('etablissements')
      .update({ taux_commission_negocie: taux } as any)
      .eq('id', editingTaux.etabId);
    setSavingTaux(false);
    if (error) { toast.error('Erreur'); return; }
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
    // Récupérer les cliniques du groupe
    const { data: etabs } = await supabase
      .from('etablissements')
      .select('id')
      .eq('groupe_sante_id', groupeId)
      .is('supprime_le', null);

    if (etabs && etabs.length > 0) {
      const { error } = await supabase
        .from('etablissements')
        .update({ taux_commission_negocie: taux } as any)
        .in('id', etabs.map(e => e.id));
      if (error) { toast.error('Erreur mise à jour groupe'); setSavingTaux(false); return; }
      toast.success(`Taux de ${taux}% appliqué à ${etabs.length} clinique(s) du groupe`);
    }
    setSavingTaux(false);
    setEditingTauxGroupe(null);
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
          <Card key={g.id}>
            <CardContent className="pt-6 space-y-5">
              {/* Header */}
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                <div>
                  <h2 className="text-xl font-bold text-foreground">{g.nom}</h2>
                  <div className="flex flex-wrap gap-3 text-xs text-muted-foreground mt-1">
                    {g.siren && <span>SIREN: {g.siren}</span>}
                    <span>Formule: <strong className="text-foreground">{g.formule_abonnement || '—'}</strong></span>
                    <span>Remise groupe: <strong className="text-foreground">{fmtPct(g.remise_groupe_pourcent)}</strong></span>
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
                      <Button size="sm" onClick={() => modifierTauxGroupe(g.id)} disabled={savingTaux} className="h-8 text-xs gap-1">
                        {savingTaux ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
                        Appliquer au groupe
                      </Button>
                      <Button size="sm" variant="ghost" className="h-8 text-xs" onClick={() => setEditingTauxGroupe(null)}>Annuler</Button>
                    </div>
                  ) : (
                    <Button size="sm" variant="outline" className="gap-1 text-xs" onClick={() => setEditingTauxGroupe({ groupeId: g.id, taux: String(g.cliniques[0]?.taux_commission_negocie ?? 15) })}>
                      <Percent className="h-3.5 w-3.5" /> Modifier taux du groupe
                    </Button>
                  )}
                  <Button size="sm" variant="outline" className="gap-1 text-xs" onClick={() => {
                    setEmailGroupeId(g.id);
                    setEmailClinicId(null);
                  }}>
                    <Mail className="h-3.5 w-3.5" /> Email au groupe
                  </Button>
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
                    <Button size="sm" onClick={() => envoyerEmail(
                      g.cliniques.map(c => c.email_contact).filter(Boolean) as string[],
                      g.nom
                    )} disabled={sendingEmail} className="gap-1">
                      {sendingEmail ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Send className="h-3.5 w-3.5" />}
                      Envoyer
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => setEmailGroupeId(null)}>Annuler</Button>
                  </div>
                </div>
              )}

              {/* Tableau cliniques */}
              <div>
                <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-3">
                  Détail par clinique
                </h3>
                <div className="overflow-x-auto">
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
                              <p className="text-[10px] text-muted-foreground">{c.adresse_ville} · {c.type}</p>
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
                                  <Button size="sm" variant="ghost" className="h-7 w-7 p-0" onClick={modifierTaux} disabled={savingTaux}>
                                    {savingTaux ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
                                  </Button>
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
                                <Button size="sm" variant="ghost" className="h-7 px-2 text-xs" onClick={() => {
                                  setEmailClinicId(c.id);
                                  setEmailGroupeId(g.id);
                                }}>
                                  <Mail className="h-3 w-3" />
                                </Button>
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
                                    <Button size="sm" onClick={() => envoyerEmail(
                                      c.email_contact ? [c.email_contact] : [],
                                      c.nom
                                    )} disabled={sendingEmail} className="gap-1 text-xs">
                                      {sendingEmail ? <Loader2 className="h-3 w-3 animate-spin" /> : <Send className="h-3 w-3" />}
                                      Envoyer
                                    </Button>
                                    <Button size="sm" variant="ghost" className="text-xs" onClick={() => setEmailClinicId(null)}>Annuler</Button>
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
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </LayoutAdmin>
  );
}
