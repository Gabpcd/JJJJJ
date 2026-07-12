import React, { useState, useEffect, useMemo } from 'react';
import { Search, Eye, Ban, RefreshCw, Mail, Phone, ShieldCheck, ShieldX, Clock, Users, FlaskConical, ArrowRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { usePageTitle } from '@/hooks/usePageTitle';
import { capturerErreurSentry } from '@/lib/sentry';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { estUtilisateurTestAdmin, libelleTypeEtablissementAdmin } from '@/lib/adminPresentation';
import { getLabelProfession } from '@/lib/constantes';

export default function AdminUtilisateurs() {
  const navigate = useNavigate();
  usePageTitle('Utilisateurs');
  const [soignants, setSoignants] = useState<any[]>([]);
  const [etabs, setEtabs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [recherche, setRecherche] = useState('');

  const charger = async () => {
    setLoading(true);
    const [resSoignants, resEtabs] = await Promise.all([
      supabase
        .from('soignants')
        .select('id, prenom, nom, profession, numero_rpps, rpps_verifie, score_fiabilite, total_missions_terminees, email, telephone, supprime_le, est_compte_test')
        .order('cree_le', { ascending: false })
        .limit(500),
      supabase
        .from('etablissements')
        .select('id, nom, type, siret, email_contact, telephone_contact, supprime_le, statut_verification, siret_verifie, siret_raison_sociale, siret_code_naf, peut_publier_missions, cree_le, est_compte_test')
        .order('cree_le', { ascending: false })
        .limit(500),
    ]);

    if (resSoignants.data) setSoignants(resSoignants.data);
    // File de travail (Session D) : les établissements en attente de vérification
    // passent en tête de l'onglet, le reste garde l'ordre anté-chronologique.
    if (resEtabs.data) {
      setEtabs([...(resEtabs.data as any[])].sort((a, b) => {
        const pa = a.statut_verification === 'EN_ATTENTE' && !a.supprime_le ? 0 : 1;
        const pb = b.statut_verification === 'EN_ATTENTE' && !b.supprime_le ? 0 : 1;
        return pa - pb;
      }));
    }
    setLoading(false);
  };

  useEffect(() => {
    charger();
  }, []);

  const filteredSoignants = useMemo(() => {
    const q = recherche.toLowerCase();
    if (!q) return soignants;
    return soignants.filter((s) =>
      `${s.prenom} ${s.nom} ${s.profession} ${s.email || ''} ${s.telephone || ''}`.toLowerCase().includes(q)
    );
  }, [soignants, recherche]);

  const filteredEtabs = useMemo(() => {
    const q = recherche.toLowerCase();
    if (!q) return etabs;
    return etabs.filter((e) =>
      `${e.nom} ${e.siret} ${e.type} ${e.email_contact || ''} ${e.telephone_contact || ''}`.toLowerCase().includes(q)
    );
  }, [etabs, recherche]);

  const etabsEnAttente = useMemo(() =>
    etabs.filter(e => e.statut_verification === 'EN_ATTENTE' && !e.supprime_le),
  [etabs]);

  // Lot 21 : suspension derrière confirmation + motif OBLIGATOIRE (journalisé côté RPC).
  const [suspendModal, setSuspendModal] = useState<{ table: string; id: string; nom: string } | null>(null);
  const [suspendMotif, setSuspendMotif] = useState('');

  const suspendre = (table: string, id: string, nom: string) => {
    setSuspendModal({ table, id, nom });
    setSuspendMotif('');
  };

  const confirmerSuspension = async () => {
    if (!suspendModal || !suspendMotif.trim()) return;
    try {
      const { data, error } = await supabase.rpc('fn_admin_suspendre_utilisateur' as any, {
        p_table: suspendModal.table,
        p_id: suspendModal.id,
        p_suspendre: true,
        p_motif: suspendMotif.trim(),
      });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Utilisateur suspendu');
      setSuspendModal(null);
      setSuspendMotif('');
      charger();
    } catch (err) {
      capturerErreurSentry(err, 'AdminUtilisateurs', 'suspendre');
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    }
  };

  const reactiver = async (table: string, id: string) => {
    try {
      const { data, error } = await supabase.rpc('fn_admin_suspendre_utilisateur' as any, {
        p_table: table,
        p_id: id,
        p_suspendre: false,
      });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Utilisateur réactivé');
      charger();
    } catch (err) {
      capturerErreurSentry(err, 'AdminUtilisateurs', 'reactiver');
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    }
  };

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Gestion utilisateurs" /></LayoutAdmin>;

  const colonnesSoignants: ColonneTableau<any>[] = [
    { cle: 'nom', titre: 'Nom' },
    { cle: 'profession', titre: 'Profession' },
    { cle: 'rpps', titre: 'RPPS' },
    { cle: 'score', titre: 'Score' },
    { cle: 'missions', titre: 'Missions' },
    { cle: 'statut', titre: 'Statut' },
    { cle: 'actions', titre: 'Actions', align: 'right' },
  ];

  const colonnesEtabs: ColonneTableau<any>[] = [
    { cle: 'nom', titre: 'Nom' },
    { cle: 'type', titre: 'Type' },
    { cle: 'siret', titre: 'SIRET' },
    { cle: 'verification', titre: 'Vérification' },
    { cle: 'statut', titre: 'Statut' },
    { cle: 'actions', titre: 'Actions', align: 'right' },
  ];

  const renduVerificationBadge = (statut: string) =>
    statut === 'VERIFIE' ? (
      <BadgeY2K variant="success" size="sm" icone={<ShieldCheck className="h-3 w-3" />}>
        Vérifié
      </BadgeY2K>
    ) : statut === 'REJETE' ? (
      <BadgeY2K variant="error" size="sm" icone={<ShieldX className="h-3 w-3" />}>
        Rejeté
      </BadgeY2K>
    ) : (
      <BadgeY2K variant="warning" size="sm" icone={<Clock className="h-3 w-3" />}>
        En attente
      </BadgeY2K>
    );

  const renduStatutBadge = (supprime: boolean) =>
    supprime ? <BadgeY2K variant="error" size="sm">Suspendu</BadgeY2K>
             : <BadgeY2K variant="success" size="sm">Actif</BadgeY2K>;

  return (
    <>
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Utilisateurs" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Gestion utilisateurs</h1>

        {/* Une seule maison pour le vetting : la file dédiée. */}
        {etabsEnAttente.length > 0 && (
          <div className="flex flex-col gap-3 rounded-xl border-2 border-amber-300 bg-amber-50 p-4 dark:border-amber-700 dark:bg-amber-950/20 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-2">
              <Clock className="h-5 w-5 text-amber-600 dark:text-amber-300" />
              <p className="font-bold text-amber-800 dark:text-amber-300">
                {etabsEnAttente.length} établissement{etabsEnAttente.length > 1 ? 's' : ''} à examiner dans la file de vérification
              </p>
            </div>
            <BoutonY2K onClick={() => navigate('/admin/verification-etablissements')} iconeDroite={<ArrowRight className="h-4 w-4" />}>
              Ouvrir la file
            </BoutonY2K>
          </div>
        )}

        {/* Une seule recherche dans cette page ; la recherche globale reste disponible via ⌘K. */}
        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input aria-label="Rechercher un utilisateur" placeholder="Rechercher un utilisateur…" value={recherche} onChange={(e) => setRecherche(e.target.value)} className="pl-10 min-h-[44px]" />
        </div>

        <Tabs defaultValue="soignants">
          <TabsList>
            <TabsTrigger value="soignants">Soignants ({filteredSoignants.length})</TabsTrigger>
            <TabsTrigger value="etablissements">Établissements ({filteredEtabs.length})</TabsTrigger>
          </TabsList>

          <TabsContent value="soignants">
            <TableOuCartes
              colonnes={colonnesSoignants}
              donnees={filteredSoignants}
              getId={(s) => s.id}
              etatVide={
                <EmptyState
                  icone={<Users />}
                  mascotte="empty"
                  titre="Aucun soignant trouvé"
                  description="Aucun soignant ne correspond à votre recherche."
                  compact
                />
              }
              renduCellule={(s, col) => {
                switch (col.cle) {
                  case 'nom':
                    return <span className="inline-flex items-center gap-2 font-medium">{s.prenom} {s.nom}{estUtilisateurTestAdmin(s) && <BadgeY2K variant="warning" size="sm" icone={<FlaskConical className="h-3 w-3" />}>Test</BadgeY2K>}</span>;
                  case 'profession':
                    return <span className="text-sm">{getLabelProfession(s.profession)}</span>;
                  case 'rpps':
                    return s.rpps_verifie
                      ? <BadgeY2K variant="success" size="sm">Vérifié</BadgeY2K>
                      : <BadgeY2K variant="info" size="sm">Non</BadgeY2K>;
                  case 'score':
                    return <span className="text-sm">{s.score_fiabilite != null && s.total_missions_terminees > 0 ? `${s.score_fiabilite}/100` : '—'}</span>;
                  case 'missions':
                    return <span className="text-sm">{s.total_missions_terminees}</span>;
                  case 'statut':
                    return renduStatutBadge(!!s.supprime_le);
                  case 'actions':
                    return (
                      <div className="flex items-center justify-end gap-1 flex-wrap" onClick={(e) => e.stopPropagation()}>
                        <BoutonY2K size="sm" onClick={() => navigate(`/admin/utilisateurs/${s.id}`)} className="min-h-[44px]" iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                          Détails
                        </BoutonY2K>
                        {s.email && (
                          <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                            <a href={`mailto:${s.email}`}><Mail className="h-3.5 w-3.5 mr-1" />Email</a>
                          </Button>
                        )}
                        {s.telephone && (
                          <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                            <a href={`tel:${s.telephone}`}><Phone className="h-3.5 w-3.5 mr-1" />Appeler</a>
                          </Button>
                        )}
                        {s.supprime_le ? (
                          <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('soignants', s.id)} className="min-h-[44px]" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                            Réactiver
                          </BoutonY2K>
                        ) : (
                          <BoutonY2K size="sm" variant="ghost" onClick={() => suspendre('soignants', s.id, `${s.prenom} ${s.nom}`)} className="min-h-[44px]" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                            Suspendre
                          </BoutonY2K>
                        )}
                      </div>
                    );
                  default:
                    return null;
                }
              }}
              renduCarte={(s) => (
                <div className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="font-semibold text-foreground truncate">{s.prenom} {s.nom}</p>
                      <p className="text-xs text-muted-foreground">{getLabelProfession(s.profession)}</p>
                    </div>
                    {renduStatutBadge(!!s.supprime_le)}
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5">
                    {s.rpps_verifie
                      ? <BadgeY2K variant="success" size="sm">RPPS Vérifié</BadgeY2K>
                      : <BadgeY2K variant="info" size="sm">RPPS Non vérifié</BadgeY2K>}
                    {s.score_fiabilite != null && s.total_missions_terminees > 0 && (
                      <BadgeY2K variant="info" size="sm">Score {s.score_fiabilite}/100</BadgeY2K>
                    )}
                    <BadgeY2K variant="info" size="sm">{s.total_missions_terminees} mission{s.total_missions_terminees > 1 ? 's' : ''}</BadgeY2K>
                    {estUtilisateurTestAdmin(s) && <BadgeY2K variant="warning" size="sm" icone={<FlaskConical className="h-3 w-3" />}>Donnée de test</BadgeY2K>}
                  </div>
                  <div className="grid grid-cols-2 gap-2 pt-2 border-t border-border">
                    {s.email && (
                      <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                        <a href={`mailto:${s.email}`}><Mail className="h-3.5 w-3.5 mr-1" />Email</a>
                      </Button>
                    )}
                    {s.telephone && (
                      <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                        <a href={`tel:${s.telephone}`}><Phone className="h-3.5 w-3.5 mr-1" />Appeler</a>
                      </Button>
                    )}
                    <BoutonY2K size="sm" onClick={() => navigate(`/admin/utilisateurs/${s.id}`)} className="min-h-[44px]" iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                      Détails
                    </BoutonY2K>
                    {s.supprime_le ? (
                      <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('soignants', s.id)} className="min-h-[44px]" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                        Réactiver
                      </BoutonY2K>
                    ) : (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => suspendre('soignants', s.id, `${s.prenom} ${s.nom}`)} className="min-h-[44px]" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                        Suspendre
                      </BoutonY2K>
                    )}
                  </div>
                </div>
              )}
            />
          </TabsContent>

          <TabsContent value="etablissements">
            <TableOuCartes
              colonnes={colonnesEtabs}
              donnees={filteredEtabs}
              getId={(e) => e.id}
              etatVide={
                <EmptyState
                  icone={<Users />}
                  mascotte="empty"
                  titre="Aucun établissement trouvé"
                  description="Aucun établissement ne correspond à votre recherche."
                  compact
                />
              }
              renduCellule={(e, col) => {
                switch (col.cle) {
                  case 'nom':
                    return <span className="inline-flex items-center gap-2 font-medium">{e.nom}{estUtilisateurTestAdmin(e) && <BadgeY2K variant="warning" size="sm" icone={<FlaskConical className="h-3 w-3" />}>Test</BadgeY2K>}</span>;
                  case 'type':
                    return <span className="text-sm">{libelleTypeEtablissementAdmin(e.type)}</span>;
                  case 'siret':
                    return <span className="font-mono text-xs">{e.siret}</span>;
                  case 'verification':
                    return renduVerificationBadge(e.statut_verification);
                  case 'statut':
                    return renduStatutBadge(!!e.supprime_le);
                  case 'actions':
                    return (
                      <div className="flex items-center justify-end gap-1 flex-wrap" onClick={(ev) => ev.stopPropagation()}>
                        <BoutonY2K size="sm" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)} className="min-h-[44px]" iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                          Détails
                        </BoutonY2K>
                        {e.email_contact && (
                          <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                            <a href={`mailto:${e.email_contact}`}><Mail className="h-3.5 w-3.5 mr-1" />Email</a>
                          </Button>
                        )}
                        {e.telephone_contact && (
                          <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                            <a href={`tel:${e.telephone_contact}`}><Phone className="h-3.5 w-3.5 mr-1" />Appeler</a>
                          </Button>
                        )}
                        {e.supprime_le ? (
                          <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('etablissements', e.id)} className="min-h-[44px]" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                            Réactiver
                          </BoutonY2K>
                        ) : (
                          <BoutonY2K size="sm" variant="ghost" onClick={() => suspendre('etablissements', e.id, e.nom)} className="min-h-[44px]" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                            Suspendre
                          </BoutonY2K>
                        )}
                      </div>
                    );
                  default:
                    return null;
                }
              }}
              renduCarte={(e) => (
                <div className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="font-semibold text-foreground truncate">{e.nom}</p>
                      <p className="text-xs text-muted-foreground">{libelleTypeEtablissementAdmin(e.type)}</p>
                      <p className="text-xs text-muted-foreground font-mono">{e.siret}</p>
                    </div>
                    {renduStatutBadge(!!e.supprime_le)}
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5">
                    {renduVerificationBadge(e.statut_verification)}
                    {estUtilisateurTestAdmin(e) && <BadgeY2K variant="warning" size="sm" icone={<FlaskConical className="h-3 w-3" />}>Donnée de test</BadgeY2K>}
                  </div>
                  <div className="grid grid-cols-2 gap-2 pt-2 border-t border-border">
                    <BoutonY2K size="sm" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)} className="min-h-[44px]" iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                      Détails
                    </BoutonY2K>
                    {e.email_contact && (
                      <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                        <a href={`mailto:${e.email_contact}`}><Mail className="h-3.5 w-3.5 mr-1" />Email</a>
                      </Button>
                    )}
                    {e.telephone_contact && (
                      <Button asChild size="sm" variant="outline" className="min-h-[44px]">
                        <a href={`tel:${e.telephone_contact}`}><Phone className="h-3.5 w-3.5 mr-1" />Appeler</a>
                      </Button>
                    )}
                    {e.supprime_le ? (
                      <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('etablissements', e.id)} className="min-h-[44px]" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                        Réactiver
                      </BoutonY2K>
                    ) : (
                      <BoutonY2K size="sm" variant="ghost" onClick={() => suspendre('etablissements', e.id, e.nom)} className="min-h-[44px]" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                        Suspendre
                      </BoutonY2K>
                    )}
                  </div>
                </div>
              )}
            />
          </TabsContent>
        </Tabs>
      </div>
    </LayoutAdmin>

    {/* Modale suspension — motif OBLIGATOIRE (journalisé dans journaux_audit côté RPC) */}
    <Dialog open={!!suspendModal} onOpenChange={() => setSuspendModal(null)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Suspendre le compte{suspendModal?.nom ? ` — ${suspendModal.nom}` : ''}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-muted-foreground">
            Le compte sera suspendu (accès bloqué, réversible). Indiquez le <strong>motif</strong> — il est obligatoire et journalisé dans l'audit.
          </p>
          <Textarea
            aria-label="Motif de la suspension"
            value={suspendMotif}
            onChange={e => setSuspendMotif(e.target.value)}
            placeholder="Motif de la suspension (obligatoire)…"
            maxLength={500}
            autoFocus
          />
        </div>
        <DialogFooter>
          <BoutonY2K variant="secondary" onClick={() => setSuspendModal(null)}>Annuler</BoutonY2K>
          <BoutonY2K variant="destructive" onClick={confirmerSuspension} disabled={!suspendMotif.trim()}>
            Suspendre le compte
          </BoutonY2K>
        </DialogFooter>
      </DialogContent>
    </Dialog>
    </>
  );
}
