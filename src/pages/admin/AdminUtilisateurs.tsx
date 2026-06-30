import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Search, Eye, Ban, RefreshCw, Mail, Phone, ShieldCheck, ShieldX, Clock, Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
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
import { useDebounce } from '@/hooks/useDebounce';
import { capturerErreurSentry } from '@/lib/sentry';
import { logger } from '@/lib/logger';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';

export default function AdminUtilisateurs() {
  const navigate = useNavigate();
  usePageTitle('Utilisateurs');
  const [soignants, setSoignants] = useState<any[]>([]);
  const [etabs, setEtabs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [recherche, setRecherche] = useState('');

  // Task 13 — server-side search
  const [serverQuery, setServerQuery] = useState('');
  const serverQueryDeb = useDebounce(serverQuery, 350);
  const [serverResults, setServerResults] = useState<any[]>([]);
  const [serverLoading, setServerLoading] = useState(false);
  const [showServerDropdown, setShowServerDropdown] = useState(false);
  const serverInputRef = useRef<HTMLInputElement>(null);

  const charger = async () => {
    setLoading(true);
    const [resSoignants, resEtabs] = await Promise.all([
      supabase
        .from('soignants')
        .select('id, prenom, nom, profession, numero_rpps, rpps_verifie, score_fiabilite, total_missions_terminees, email, telephone, supprime_le')
        .order('cree_le', { ascending: false })
        .limit(500),
      supabase
        .from('etablissements')
        .select('id, nom, type, siret, email_contact, telephone_contact, supprime_le, statut_verification, siret_verifie, siret_raison_sociale, siret_code_naf, peut_publier_missions, cree_le')
        .order('cree_le', { ascending: false })
        .limit(500),
    ]);

    if (resSoignants.data) setSoignants(resSoignants.data);
    // File de travail (Session D) : les établissements en attente de vérification
    // passent en tête de l'onglet, le reste garde l'ordre anté-chronologique.
    if (resEtabs.data) {
      setEtabs([...resEtabs.data].sort((a, b) => {
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

  // Task 13 — server-side search effect
  useEffect(() => {
    if (serverQueryDeb.length < 2) { setServerResults([]); setShowServerDropdown(false); return; }
    setServerLoading(true);
    setShowServerDropdown(true);
    supabase.rpc('fn_rechercher_utilisateurs' as any, { p_query: serverQueryDeb })
      .then(({ data, error }) => {
        if (!error && data) setServerResults(data as any[]);
        else setServerResults([]);
        setServerLoading(false);
      });
  }, [serverQueryDeb]);

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

  const [rejectModalId, setRejectModalId] = useState<string | null>(null);
  const [rejectMotif, setRejectMotif] = useState('');

  const suspendre = async (table: string, id: string) => {
    try {
      const { data, error } = await supabase.rpc('fn_admin_suspendre_utilisateur' as any, {
        p_table: table,
        p_id: id,
        p_suspendre: true,
      });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Utilisateur suspendu');
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

  const validerEtablissement = async (id: string) => {
    try {
      const { data, error } = await supabase.rpc('fn_admin_valider_etablissement' as any, {
        p_etablissement_id: id,
      });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Établissement validé — peut publier des missions');
      charger();
    } catch (err) {
      capturerErreurSentry(err, 'AdminUtilisateurs', 'valider_etablissement');
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    }
  };

  const rejeterEtablissement = async () => {
    if (!rejectModalId) return;
    try {
      const { data, error } = await supabase.rpc('fn_admin_rejeter_etablissement' as any, {
        p_etablissement_id: rejectModalId,
        p_motif: rejectMotif.trim() || 'Non conforme',
      });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Établissement rejeté');
      setRejectModalId(null);
      setRejectMotif('');
      charger();
    } catch (err) {
      capturerErreurSentry(err, 'AdminUtilisateurs', 'rejeter_etablissement');
      toast.error('Une erreur est survenue. Veuillez réessayer.');
    }
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

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

        {/* Bandeau établissements en attente */}
        {etabsEnAttente.length > 0 && (
          <div className="rounded-xl border-2 border-amber-300 bg-amber-50 dark:bg-amber-950/20 dark:border-amber-700 p-4">
            <div className="flex items-center gap-2 mb-3">
              <Clock className="h-5 w-5 text-amber-600" />
              <h2 className="font-bold text-amber-800 dark:text-amber-300">
                {etabsEnAttente.length} établissement{etabsEnAttente.length > 1 ? 's' : ''} en attente de vérification
              </h2>
            </div>
            <div className="space-y-2">
              {etabsEnAttente.map(e => (
                <div key={e.id} className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 bg-card rounded-lg p-3 border">
                  <div>
                    <p className="font-medium text-foreground">{e.nom}</p>
                    <p className="text-xs text-muted-foreground font-mono">{e.siret} · {e.type}</p>
                    {e.siret_raison_sociale && <p className="text-xs text-muted-foreground">INSEE: {e.siret_raison_sociale}</p>}
                    {e.siret_code_naf && <p className="text-xs text-muted-foreground">NAF: {e.siret_code_naf}</p>}
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <BoutonY2K size="sm" onClick={() => validerEtablissement(e.id)} className="bg-green-600 hover:bg-green-700 text-white min-h-[40px]" iconeGauche={<ShieldCheck className="h-3.5 w-3.5" />}>
                      Valider
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="destructive" onClick={() => { setRejectModalId(e.id); setRejectMotif(''); }} className="min-h-[40px]" iconeGauche={<ShieldX className="h-3.5 w-3.5" />}>
                      Rejeter
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)} className="min-h-[40px]" aria-label="Détails">
                      <Eye className="h-3.5 w-3.5" />
                    </BoutonY2K>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Task 13 — Server-side search avec dropdown */}
        <div className="relative max-w-md mb-2">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            ref={serverInputRef}
            placeholder="Recherche serveur (≥2 car.)…"
            value={serverQuery}
            onChange={(e) => setServerQuery(e.target.value)}
            onFocus={() => { if (serverResults.length > 0) setShowServerDropdown(true); }}
            onBlur={() => setTimeout(() => setShowServerDropdown(false), 200)}
            className="pl-10"
            aria-label="Rechercher un utilisateur (serveur)"
          />
          {showServerDropdown && (
            <div className="absolute z-50 top-full left-0 right-0 mt-1 bg-card border border-border rounded-xl shadow-lg overflow-y-auto max-h-72">
              {serverLoading && <p className="text-xs text-muted-foreground p-3">Recherche en cours…</p>}
              {!serverLoading && serverResults.length === 0 && serverQueryDeb.length >= 2 && (
                <p className="text-xs text-muted-foreground p-3">Aucun résultat.</p>
              )}
              {serverResults.map((r: any) => (
                <button
                  key={r.id}
                  type="button"
                  onMouseDown={() => { navigate(`/admin/utilisateurs/${r.id}`); setServerQuery(''); setShowServerDropdown(false); }}
                  className="w-full text-left px-3 py-2.5 hover:bg-muted transition-colors flex items-center gap-2"
                >
                  {r.avatar_url && (
                    <img src={r.avatar_url} alt="" className="w-7 h-7 rounded-full object-cover shrink-0" />
                  )}
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{r.prenom} {r.nom}</p>
                    <p className="text-[11px] text-muted-foreground truncate">{r.email}{r.profession ? ` · ${r.profession}` : ''} · {r.type}</p>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Filtre local existant */}
        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input placeholder="Filtrer liste locale…" value={recherche} onChange={(e) => setRecherche(e.target.value)} className="pl-10" />
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
                    return <span className="font-medium">{s.prenom} {s.nom}</span>;
                  case 'profession':
                    return <span className="text-sm">{s.profession}</span>;
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
                        {s.email && (
                          <Button asChild size="sm" variant="outline" className="h-8">
                            <a href={`mailto:${s.email}`}><Mail className="h-3.5 w-3.5 mr-1" />Email</a>
                          </Button>
                        )}
                        {s.telephone && (
                          <Button asChild size="sm" variant="outline" className="h-8">
                            <a href={`tel:${s.telephone}`}><Phone className="h-3.5 w-3.5 mr-1" />Appeler</a>
                          </Button>
                        )}
                        {s.supprime_le ? (
                          <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('soignants', s.id)} className="h-8" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                            Réactiver
                          </BoutonY2K>
                        ) : (
                          <BoutonY2K size="sm" variant="destructive" onClick={() => suspendre('soignants', s.id)} className="h-8" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                            Suspendre
                          </BoutonY2K>
                        )}
                        <BoutonY2K size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${s.id}`)} className="h-8 w-8 p-0" aria-label="Détails">
                          <Eye className="h-3.5 w-3.5" />
                        </BoutonY2K>
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
                      <p className="text-xs text-muted-foreground">{s.profession}</p>
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
                    {s.supprime_le ? (
                      <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('soignants', s.id)} className="min-h-[44px]" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                        Réactiver
                      </BoutonY2K>
                    ) : (
                      <BoutonY2K size="sm" variant="destructive" onClick={() => suspendre('soignants', s.id)} className="min-h-[44px]" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                        Suspendre
                      </BoutonY2K>
                    )}
                    <BoutonY2K size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${s.id}`)} className="min-h-[44px]" iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                      Détails
                    </BoutonY2K>
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
                    return <span className="font-medium">{e.nom}</span>;
                  case 'type':
                    return <span className="text-sm">{e.type}</span>;
                  case 'siret':
                    return <span className="font-mono text-xs">{e.siret}</span>;
                  case 'verification':
                    return renduVerificationBadge(e.statut_verification);
                  case 'statut':
                    return renduStatutBadge(!!e.supprime_le);
                  case 'actions':
                    return (
                      <div className="flex items-center justify-end gap-1 flex-wrap" onClick={(ev) => ev.stopPropagation()}>
                        {e.statut_verification === 'EN_ATTENTE' && (
                          <>
                            <BoutonY2K size="sm" onClick={() => validerEtablissement(e.id)} className="bg-green-600 hover:bg-green-700 text-white h-8" iconeGauche={<ShieldCheck className="h-3.5 w-3.5" />}>
                              Valider
                            </BoutonY2K>
                            <BoutonY2K size="sm" variant="destructive" onClick={() => { setRejectModalId(e.id); setRejectMotif(''); }} className="h-8" iconeGauche={<ShieldX className="h-3.5 w-3.5" />}>
                              Rejeter
                            </BoutonY2K>
                          </>
                        )}
                        {e.email_contact && (
                          <Button asChild size="sm" variant="outline" className="h-8">
                            <a href={`mailto:${e.email_contact}`}><Mail className="h-3.5 w-3.5 mr-1" />Email</a>
                          </Button>
                        )}
                        {e.telephone_contact && (
                          <Button asChild size="sm" variant="outline" className="h-8">
                            <a href={`tel:${e.telephone_contact}`}><Phone className="h-3.5 w-3.5 mr-1" />Appeler</a>
                          </Button>
                        )}
                        {e.supprime_le ? (
                          <BoutonY2K size="sm" variant="secondary" onClick={() => reactiver('etablissements', e.id)} className="h-8" iconeGauche={<RefreshCw className="h-3.5 w-3.5" />}>
                            Réactiver
                          </BoutonY2K>
                        ) : (
                          <BoutonY2K size="sm" variant="destructive" onClick={() => suspendre('etablissements', e.id)} className="h-8" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                            Suspendre
                          </BoutonY2K>
                        )}
                        <BoutonY2K size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)} className="h-8 w-8 p-0" aria-label="Détails">
                          <Eye className="h-3.5 w-3.5" />
                        </BoutonY2K>
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
                      <p className="text-xs text-muted-foreground">{e.type}</p>
                      <p className="text-xs text-muted-foreground font-mono">{e.siret}</p>
                    </div>
                    {renduStatutBadge(!!e.supprime_le)}
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5">
                    {renduVerificationBadge(e.statut_verification)}
                  </div>
                  <div className="grid grid-cols-2 gap-2 pt-2 border-t border-border">
                    {e.statut_verification === 'EN_ATTENTE' && (
                      <>
                        <BoutonY2K size="sm" onClick={() => validerEtablissement(e.id)} className="bg-green-600 hover:bg-green-700 text-white min-h-[44px]" iconeGauche={<ShieldCheck className="h-3.5 w-3.5" />}>
                          Valider
                        </BoutonY2K>
                        <BoutonY2K size="sm" variant="destructive" onClick={() => { setRejectModalId(e.id); setRejectMotif(''); }} className="min-h-[44px]" iconeGauche={<ShieldX className="h-3.5 w-3.5" />}>
                          Rejeter
                        </BoutonY2K>
                      </>
                    )}
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
                      <BoutonY2K size="sm" variant="destructive" onClick={() => suspendre('etablissements', e.id)} className="min-h-[44px]" iconeGauche={<Ban className="h-3.5 w-3.5" />}>
                        Suspendre
                      </BoutonY2K>
                    )}
                    <BoutonY2K size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)} className="min-h-[44px]" iconeGauche={<Eye className="h-3.5 w-3.5" />}>
                      Détails
                    </BoutonY2K>
                  </div>
                </div>
              )}
            />
          </TabsContent>
        </Tabs>
      </div>
    </LayoutAdmin>

    {/* Modale rejet établissement */}
    <Dialog open={!!rejectModalId} onOpenChange={() => setRejectModalId(null)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Rejeter l'établissement</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-muted-foreground">Indiquez le motif du rejet (optionnel) :</p>
          <Textarea
            value={rejectMotif}
            onChange={e => setRejectMotif(e.target.value)}
            placeholder="Motif du rejet..."
            maxLength={500}
          />
        </div>
        <DialogFooter>
          <BoutonY2K variant="secondary" onClick={() => setRejectModalId(null)}>Annuler</BoutonY2K>
          <BoutonY2K variant="destructive" onClick={rejeterEtablissement}>Confirmer le rejet</BoutonY2K>
        </DialogFooter>
      </DialogContent>
    </Dialog>
    </>
  );
}
