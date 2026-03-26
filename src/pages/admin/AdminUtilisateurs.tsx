import React, { useState, useEffect, useMemo } from 'react';
import { Search, Eye, Ban, RefreshCw, Mail, Phone, ShieldCheck, ShieldX, Clock } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { usePageTitle } from '@/hooks/usePageTitle';
import { capturerErreurSentry } from '@/lib/sentry';
import { logger } from '@/lib/logger';

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
    if (resEtabs.data) setEtabs(resEtabs.data);
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

  return (
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
                <div key={e.id} className="flex items-center justify-between bg-card rounded-lg p-3 border">
                  <div>
                    <p className="font-medium text-foreground">{e.nom}</p>
                    <p className="text-xs text-muted-foreground font-mono">{e.siret} · {e.type}</p>
                    {e.siret_raison_sociale && <p className="text-xs text-muted-foreground">INSEE: {e.siret_raison_sociale}</p>}
                    {e.siret_code_naf && <p className="text-xs text-muted-foreground">NAF: {e.siret_code_naf}</p>}
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" onClick={() => validerEtablissement(e.id)} className="bg-green-600 hover:bg-green-700 text-white">
                      <ShieldCheck className="h-3.5 w-3.5 mr-1" />Valider
                    </Button>
                    <Button size="sm" variant="destructive" onClick={() => { setRejectModalId(e.id); setRejectMotif(''); }}>
                      <ShieldX className="h-3.5 w-3.5 mr-1" />Rejeter
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)}>
                      <Eye className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input placeholder="Rechercher…" value={recherche} onChange={(e) => setRecherche(e.target.value)} className="pl-10" />
        </div>

        <Tabs defaultValue="soignants">
          <TabsList>
            <TabsTrigger value="soignants">Soignants ({filteredSoignants.length})</TabsTrigger>
            <TabsTrigger value="etablissements">Établissements ({filteredEtabs.length})</TabsTrigger>
          </TabsList>

          <TabsContent value="soignants">
            <div className="rounded-lg border overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nom</TableHead>
                    <TableHead>Profession</TableHead>
                    <TableHead>RPPS</TableHead>
                    <TableHead>Score</TableHead>
                    <TableHead>Missions</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredSoignants.map((s) => (
                    <TableRow key={s.id}>
                      <TableCell className="font-medium">{s.prenom} {s.nom}</TableCell>
                      <TableCell>{s.profession}</TableCell>
                      <TableCell>{s.rpps_verifie ? <Badge className="bg-success text-success-foreground text-[10px]">Vérifié</Badge> : <Badge variant="outline" className="text-[10px]">Non</Badge>}</TableCell>
                      <TableCell>{s.score_fiabilite}/100</TableCell>
                      <TableCell>{s.total_missions_terminees}</TableCell>
                      <TableCell>{s.supprime_le ? <Badge variant="destructive" className="text-[10px]">Suspendu</Badge> : <Badge className="bg-success text-success-foreground text-[10px]">Actif</Badge>}</TableCell>
                      <TableCell className="text-right space-x-1 whitespace-nowrap">
                        {s.email && (
                          <Button asChild size="sm" variant="outline">
                            <a href={`mailto:${s.email}`}>
                              <Mail className="h-3.5 w-3.5 mr-1" />Email
                            </a>
                          </Button>
                        )}
                        {s.telephone && (
                          <Button asChild size="sm" variant="outline">
                            <a href={`tel:${s.telephone}`}>
                              <Phone className="h-3.5 w-3.5 mr-1" />Appeler
                            </a>
                          </Button>
                        )}
                        {s.supprime_le ? (
                          <Button size="sm" variant="outline" onClick={() => reactiver('soignants', s.id)}>
                            <RefreshCw className="h-3.5 w-3.5 mr-1" />Réactiver
                          </Button>
                        ) : (
                          <Button size="sm" variant="destructive" onClick={() => suspendre('soignants', s.id)}>
                            <Ban className="h-3.5 w-3.5 mr-1" />Suspendre
                          </Button>
                        )}
                        <Button size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${s.id}`)}>
                          <Eye className="h-3.5 w-3.5" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </TabsContent>

          <TabsContent value="etablissements">
            <div className="rounded-lg border overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nom</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>SIRET</TableHead>
                    <TableHead>Vérification</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredEtabs.map((e) => (
                    <TableRow key={e.id}>
                      <TableCell className="font-medium">{e.nom}</TableCell>
                      <TableCell>{e.type}</TableCell>
                      <TableCell className="font-mono text-xs">{e.siret}</TableCell>
                      <TableCell>
                        {e.statut_verification === 'VERIFIE' ? (
                          <Badge className="bg-success text-success-foreground text-[10px]">
                            <ShieldCheck className="h-3 w-3 mr-1" />Vérifié
                          </Badge>
                        ) : e.statut_verification === 'REJETE' ? (
                          <Badge variant="destructive" className="text-[10px]">
                            <ShieldX className="h-3 w-3 mr-1" />Rejeté
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-amber-600 border-amber-300 text-[10px]">
                            <Clock className="h-3 w-3 mr-1" />En attente
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell>{e.supprime_le ? <Badge variant="destructive" className="text-[10px]">Suspendu</Badge> : <Badge className="bg-success text-success-foreground text-[10px]">Actif</Badge>}</TableCell>
                      <TableCell className="text-right space-x-1 whitespace-nowrap">
                        {e.statut_verification === 'EN_ATTENTE' && (
                          <>
                            <Button size="sm" onClick={() => validerEtablissement(e.id)} className="bg-green-600 hover:bg-green-700 text-white">
                              <ShieldCheck className="h-3.5 w-3.5 mr-1" />Valider
                            </Button>
                            <Button size="sm" variant="destructive" onClick={() => { setRejectModalId(e.id); setRejectMotif(''); }}>
                              <ShieldX className="h-3.5 w-3.5 mr-1" />Rejeter
                            </Button>
                          </>
                        )}
                        {e.email_contact && (
                          <Button asChild size="sm" variant="outline">
                            <a href={`mailto:${e.email_contact}`}>
                              <Mail className="h-3.5 w-3.5 mr-1" />Email
                            </a>
                          </Button>
                        )}
                        {e.telephone_contact && (
                          <Button asChild size="sm" variant="outline">
                            <a href={`tel:${e.telephone_contact}`}>
                              <Phone className="h-3.5 w-3.5 mr-1" />Appeler
                            </a>
                          </Button>
                        )}
                        {e.supprime_le ? (
                          <Button size="sm" variant="outline" onClick={() => reactiver('etablissements', e.id)}>
                            <RefreshCw className="h-3.5 w-3.5 mr-1" />Réactiver
                          </Button>
                        ) : (
                          <Button size="sm" variant="destructive" onClick={() => suspendre('etablissements', e.id)}>
                            <Ban className="h-3.5 w-3.5 mr-1" />Suspendre
                          </Button>
                        )}
                        <Button size="sm" variant="ghost" onClick={() => navigate(`/admin/utilisateurs/${e.id}`)}>
                          <Eye className="h-3.5 w-3.5" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
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
          <Button variant="outline" onClick={() => setRejectModalId(null)}>Annuler</Button>
          <Button variant="destructive" onClick={rejeterEtablissement}>Confirmer le rejet</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
    </>
  );
}
