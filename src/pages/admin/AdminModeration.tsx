import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { resoudreUserIdEtablissement } from '@/hooks/useOuvrirConversation';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { logger } from '@/lib/logger';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';
import { FileCheck, MessageSquare, Check, X, Eye, Mail, Phone, Building2, User, MessageCircle, ShieldAlert } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { AdminMissionChatPanel } from '@/components/admin/AdminMissionChatPanel';
import { useNavigate } from 'react-router-dom';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

type LitigeEnrichi = {
  id: string;
  motif: string;
  reponse: string | null;
  statut: string;
  cree_le: string;
  soignant_id: string;
  etablissement_id: string;
  mission_id: string;
  initie_par: 'SOIGNANT' | 'ETABLISSEMENT';
  resolution: string | null;
  resolu_le: string | null;
  soignant?: {
    id: string;
    prenom: string | null;
    nom: string | null;
    email: string | null;
    telephone: string | null;
    profession: string | null;
  } | null;
  etablissement?: {
    id: string;
    nom: string;
    email_contact: string | null;
    telephone_contact: string | null;
    type: string | null;
  } | null;
  mission?: {
    id: string;
    intitule: string;
    profession_requise: string;
    service: string | null;
    debut_le: string;
    fin_le: string;
    statut: string | null;
  } | null;
};

const formatDate = (d?: string | null) => d ? new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
const formatDateTime = (d?: string | null) => d ? new Date(d).toLocaleString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—';
const formatStatutLitige = (statut: string) => statut.replace(/_/g, ' ');

const contacterDepuisLitige = async (userId: string, navigate: ReturnType<typeof useNavigate>, isEtablissement?: boolean) => {
  let resolvedId = userId;
  if (isEtablissement) {
    const resolved = await resoudreUserIdEtablissement(userId);
    if (!resolved) {
      toast.error("Impossible de trouver l'interlocuteur de l'établissement.");
      return;
    }
    resolvedId = resolved;
  }
  logger.debug('contacterDepuisLitige params:', { userId, resolvedId, isEtablissement });
  const { data, error } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: resolvedId, p_mission_id: null });
  logger.debug('contacterDepuisLitige result:', { data, error });
  if (error) {
    logger.error('fn_obtenir_conversation error:', error);
    toast.error('Impossible d\'ouvrir la conversation. Veuillez réessayer.');
    return;
  }
  if (!data) {
    toast.error("La conversation n'a pas pu être créée. Vérifiez que l'utilisateur existe.");
    return;
  }
  navigate(`/admin/messagerie?conv=${data}`);
};

export default function AdminModeration() {
  usePageTitle('Modération');
  const navigate = useNavigate();
  const [litiges, setLitiges] = useState<LitigeEnrichi[]>([]);
  const [evaluations, setEvaluations] = useState<any[]>([]);
  const [documents, setDocuments] = useState<any[]>([]);
  const [incoherences, setIncoherences] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLitigeId, setActionLitigeId] = useState<string | null>(null);
  // Resolution form state
  const [resolutionFormId, setResolutionFormId] = useState<string | null>(null);
  const [resolutionText, setResolutionText] = useState('');
  const [enFaveurDe, setEnFaveurDe] = useState<string>('');
  const [ajusterHeures, setAjusterHeures] = useState('');
  const [ajusterTaux, setAjusterTaux] = useState('');
  const charger = async () => {
    setLoading(true);

    const [resLitiges, resEvals, resDocs, resIncoherences] = await Promise.all([
      supabase
        .from('litiges')
        .select('id, motif, reponse, statut, cree_le, soignant_id, etablissement_id, mission_id, initie_par, resolution, resolu_le')
        .in('statut', ['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE'])
        .order('cree_le', { ascending: false }),
      supabase
        .from('evaluations')
        .select('id, note, commentaire, type_evaluateur, mission_id, cree_le')
        .eq('visible', false)
        .order('cree_le', { ascending: true })
        .limit(50),
      supabase
        .from('documents_soignants')
        .select('id, nom_fichier, type_document, soignant_id, televerse_le')
        .eq('statut_verification', 'EN_ATTENTE')
        .is('supprime_le', null)
        .order('televerse_le', { ascending: true })
        .limit(50),
      supabase.rpc('fn_admin_incoherences_identite' as any),
    ]);

    if (resLitiges.error || resEvals.error || resDocs.error) {
      toast.error('Impossible de charger les données de modération.');
    }
    if (resIncoherences.data) setIncoherences(resIncoherences.data as any[] || []);

    const litigesBruts = (resLitiges.data ?? []) as LitigeEnrichi[];

    if (litigesBruts.length > 0) {
      const soignantIds = [...new Set(litigesBruts.map((litige) => litige.soignant_id).filter(Boolean))];
      const etablissementIds = [...new Set(litigesBruts.map((litige) => litige.etablissement_id).filter(Boolean))];
      const missionIds = [...new Set(litigesBruts.map((litige) => litige.mission_id).filter(Boolean))];

      const [resSoignants, resEtablissements, resMissions] = await Promise.all([
        soignantIds.length
          ? supabase.from('soignants').select('id, prenom, nom, email, telephone, profession').in('id', soignantIds)
          : Promise.resolve({ data: [], error: null } as any),
        etablissementIds.length
          ? supabase.from('etablissements').select('id, nom, email_contact, telephone_contact, type').in('id', etablissementIds)
          : Promise.resolve({ data: [], error: null } as any),
        missionIds.length
          ? supabase.from('missions').select('id, intitule, profession_requise, service, debut_le, fin_le, statut').in('id', missionIds)
          : Promise.resolve({ data: [], error: null } as any),
      ]);

      const soignantsMap = new Map<string, LitigeEnrichi['soignant']>((resSoignants.data ?? []).map((item: any) => [item.id, item]));
      const etablissementsMap = new Map<string, LitigeEnrichi['etablissement']>((resEtablissements.data ?? []).map((item: any) => [item.id, item]));
      const missionsMap = new Map<string, LitigeEnrichi['mission']>((resMissions.data ?? []).map((item: any) => [item.id, item]));

      const litigesEnrichis: LitigeEnrichi[] = litigesBruts.map((litige) => ({
        ...litige,
        soignant: soignantsMap.get(litige.soignant_id) ?? null,
        etablissement: etablissementsMap.get(litige.etablissement_id) ?? null,
        mission: missionsMap.get(litige.mission_id) ?? null,
      }));

      setLitiges(litigesEnrichis);
    } else {
      setLitiges([]);
    }

    if (resEvals.data) setEvaluations(resEvals.data);
    if (resDocs.data) setDocuments(resDocs.data);
    setLoading(false);
  };

  useEffect(() => {
    charger();
  }, []);

  const openResolutionForm = (id: string) => {
    setResolutionFormId(id);
    setResolutionText('');
    setEnFaveurDe('');
    setAjusterHeures('');
    setAjusterTaux('');
  };

  const resoudreLitige = async () => {
    if (!resolutionFormId || !resolutionText.trim() || !enFaveurDe) {
      toast.error('Veuillez remplir la résolution et choisir en faveur de qui.');
      return;
    }
    if (resolutionText.trim().length < 10) {
      toast.error('La résolution doit contenir au moins 10 caractères.');
      return;
    }
    setActionLitigeId(resolutionFormId);

    const { data, error } = await supabase.rpc('fn_admin_resoudre_litige' as any, {
      p_litige_id: resolutionFormId,
      p_resolution: resolutionText.trim(),
      p_en_faveur_de: enFaveurDe,
      p_ajuster_heures: ajusterHeures ? parseFloat(ajusterHeures) : null,
      p_ajuster_taux: ajusterTaux ? parseFloat(ajusterTaux) : null,
    });

    if (error) {
      toast.error('Une erreur est survenue. Veuillez réessayer.');
      setActionLitigeId(null);
      return;
    }
    if ((data as any)?.error) {
      toast.error((data as any).error);
      setActionLitigeId(null);
      return;
    }

    toast.success('Litige résolu avec succès.');
    setResolutionFormId(null);
    await charger();
    setActionLitigeId(null);
  };

  const publierEvaluation = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_evaluation' as any, { p_evaluation_id: id, p_action: 'PUBLIER' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Évaluation publiée');
    charger();
  };

  const supprimerEvaluation = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_evaluation' as any, { p_evaluation_id: id, p_action: 'SUPPRIMER' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Évaluation supprimée');
    charger();
  };

  const validerDocument = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, { p_document_id: id, p_action: 'VALIDER' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Document validé');
    charger();
  };

  const rejeterDocument = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_admin_moderer_document' as any, { p_document_id: id, p_action: 'REJETER', p_motif: 'Rejeté par admin' });
    if (error || (data as any)?.error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Document rejeté');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Modération" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Modération</h1>

        <Tabs defaultValue="litiges">
          <TabsList>
            <TabsTrigger value="litiges" className="gap-1.5"><MessageSquare className="h-4 w-4" />Litiges ({litiges.length})</TabsTrigger>
            <TabsTrigger value="evaluations" className="gap-1.5"><Eye className="h-4 w-4" />Évaluations ({evaluations.length})</TabsTrigger>
            <TabsTrigger value="documents" className="gap-1.5"><FileCheck className="h-4 w-4" />Documents ({documents.length})</TabsTrigger>
            <TabsTrigger value="incoherences" className="gap-1.5"><ShieldAlert className="h-4 w-4" />Identité ({incoherences.length})</TabsTrigger>
          </TabsList>

          <TabsContent value="litiges" className="space-y-4">
            {litiges.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">Aucun litige ouvert 🎉</p>}

            {litiges.map((litige) => {
              const demandeLabel = litige.initie_par === 'SOIGNANT' ? 'Demande du soignant' : 'Demande de l\'établissement';
              const reponseLabel = litige.initie_par === 'SOIGNANT' ? 'Réponse de l\'établissement' : 'Réponse du soignant';

              return (
                <Card key={litige.id}>
                  <CardContent className="space-y-5 pt-6">
                    <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                      <div className="space-y-2">
                        <p className="text-xl font-semibold text-foreground">{litige.motif}</p>
                        <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                          <span>{formatDateTime(litige.cree_le)}</span>
                          <span>•</span>
                          <span>Litige initié par {litige.initie_par === 'SOIGNANT' ? 'le soignant' : 'l\'établissement'}</span>
                        </div>
                      </div>
                      <div className="flex flex-col items-end gap-1">
                        <Badge variant={litige.statut === 'OUVERT' ? 'destructive' : litige.statut === 'EN_MEDIATION' ? 'default' : 'secondary'}>
                          {formatStatutLitige(litige.statut)}
                        </Badge>
                        {litige.statut === 'EN_MEDIATION' && (
                          <span className="text-[10px] text-success font-medium">Les deux parties sont d'accord</span>
                        )}
                      </div>
                    </div>

                    <div className="grid gap-4 xl:grid-cols-[1.15fr_0.85fr]">
                      <div className="grid gap-4">
                        <div className="rounded-lg border bg-background p-4">
                          <p className="text-xs uppercase tracking-wide text-muted-foreground">{demandeLabel}</p>
                          <p className="mt-2 text-sm leading-6 text-foreground">{litige.motif}</p>
                        </div>

                        <div className="rounded-lg border bg-background p-4">
                          <p className="text-xs uppercase tracking-wide text-muted-foreground">{reponseLabel}</p>
                          <p className="mt-2 text-sm leading-6 text-foreground">{litige.reponse || 'Aucune réponse enregistrée pour le moment.'}</p>
                        </div>

                        {litige.resolution && litige.resolu_le && (
                          <div className="rounded-lg border bg-background p-4">
                            <p className="text-xs uppercase tracking-wide text-muted-foreground">Résolution actuelle</p>
                            <p className="mt-2 text-sm leading-6 text-foreground">{litige.resolution}</p>
                            <p className="mt-2 text-xs text-muted-foreground">Résolu le {formatDateTime(litige.resolu_le)}</p>
                          </div>
                        )}
                      </div>

                      <div className="grid gap-4">
                        <div className="rounded-lg border bg-background p-4">
                          <p className="text-xs uppercase tracking-wide text-muted-foreground">Mission concernée</p>
                          <p className="mt-2 font-medium text-foreground">{litige.mission?.intitule || 'Mission liée au litige'}</p>
                          <div className="mt-3 space-y-1 text-sm text-muted-foreground">
                            <p>{litige.mission?.profession_requise || 'Profession non renseignée'}{litige.mission?.service ? ` · ${litige.mission.service}` : ''}</p>
                            <p>Début : {formatDateTime(litige.mission?.debut_le)}</p>
                            <p>Fin : {formatDateTime(litige.mission?.fin_le)}</p>
                            <p>Statut mission : {litige.mission?.statut || '—'}</p>
                          </div>
                        </div>

                        <div className="rounded-lg border bg-background p-4 space-y-3">
                          <p className="text-xs uppercase tracking-wide text-muted-foreground">Parties prenantes</p>

                          <div className="rounded-md bg-muted/40 p-3">
                            <div className="flex items-center gap-2">
                              <User className="h-4 w-4 text-muted-foreground" />
                              <p className="text-sm font-medium text-foreground">Soignant</p>
                            </div>
                            <div className="mt-2 space-y-1 text-sm text-muted-foreground">
                              <p className="text-foreground">{litige.soignant ? `${litige.soignant.prenom || ''} ${litige.soignant.nom || ''}`.trim() || 'Soignant introuvable' : 'Soignant introuvable'}</p>
                              <p>{litige.soignant?.profession || 'Profession non renseignée'}</p>
                              <p>{litige.soignant?.email || 'Email non renseigné'}</p>
                              <p>{litige.soignant?.telephone || 'Téléphone non renseigné'}</p>
                            </div>
                            <div className="mt-3 flex flex-wrap gap-2">
                              {litige.soignant?.email && (
                                <a href={`mailto:${litige.soignant.email}`} className="inline-flex items-center gap-1 text-sm font-medium text-primary underline underline-offset-4">
                                  <Mail className="h-3.5 w-3.5" /> Email direct
                                </a>
                              )}
                              {litige.soignant?.telephone && (
                                <a href={`tel:${litige.soignant.telephone}`} className="inline-flex items-center gap-1 text-sm font-medium text-primary underline underline-offset-4">
                                  <Phone className="h-3.5 w-3.5" /> Appeler
                                </a>
                              )}
                              <button
                                onClick={() => contacterDepuisLitige(litige.soignant_id, navigate)}
                                className="inline-flex items-center gap-1 text-sm font-medium text-primary underline underline-offset-4"
                              >
                                <MessageCircle className="h-3.5 w-3.5" /> Contacter
                              </button>
                            </div>
                          </div>

                          <div className="rounded-md bg-muted/40 p-3">
                            <div className="flex items-center gap-2">
                              <Building2 className="h-4 w-4 text-muted-foreground" />
                              <p className="text-sm font-medium text-foreground">Établissement</p>
                            </div>
                            <div className="mt-2 space-y-1 text-sm text-muted-foreground">
                              <p className="text-foreground">{litige.etablissement?.nom || 'Établissement introuvable'}</p>
                              <p>{litige.etablissement?.type || 'Type non renseigné'}</p>
                              <p>{litige.etablissement?.email_contact || 'Email non renseigné'}</p>
                              <p>{litige.etablissement?.telephone_contact || 'Téléphone non renseigné'}</p>
                            </div>
                            <div className="mt-3 flex flex-wrap gap-2">
                              {litige.etablissement?.email_contact && (
                                <a href={`mailto:${litige.etablissement.email_contact}`} className="inline-flex items-center gap-1 text-sm font-medium text-primary underline underline-offset-4">
                                  <Mail className="h-3.5 w-3.5" /> Email direct
                                </a>
                              )}
                              {litige.etablissement?.telephone_contact && (
                                <a href={`tel:${litige.etablissement.telephone_contact}`} className="inline-flex items-center gap-1 text-sm font-medium text-primary underline underline-offset-4">
                                  <Phone className="h-3.5 w-3.5" /> Appeler
                                </a>
                              )}
                              <button
                                onClick={() => contacterDepuisLitige(litige.etablissement_id, navigate, true)}
                                className="inline-flex items-center gap-1 text-sm font-medium text-primary underline underline-offset-4"
                              >
                                <MessageCircle className="h-3.5 w-3.5" /> Contacter
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>

                    <AdminMissionChatPanel
                      missions={[
                        {
                          id: litige.mission_id,
                          intitule: litige.mission?.intitule || 'Mission liée au litige',
                          statut: litige.mission?.statut || 'LITIGE',
                          soignants: litige.soignant ? { prenom: litige.soignant.prenom, nom: litige.soignant.nom } : null,
                          etablissements: litige.etablissement ? { nom: litige.etablissement.nom } : null,
                        },
                      ]}
                      emptyLabel="Messagerie indisponible pour ce conflit."
                    />

                    {resolutionFormId === litige.id ? (
                      <div className="space-y-4 border-t border-border pt-4">
                        <div>
                          <Label className="mb-1.5 block">Résolution *</Label>
                          <Textarea value={resolutionText} onChange={e => setResolutionText(e.target.value)} placeholder="Expliquez la décision prise..." rows={3} />
                        </div>
                        <div>
                          <Label className="mb-1.5 block">En faveur de *</Label>
                          <Select value={enFaveurDe} onValueChange={setEnFaveurDe}>
                            <SelectTrigger><SelectValue placeholder="Choisir..." /></SelectTrigger>
                            <SelectContent>
                              <SelectItem value="SOIGNANT">Soignant</SelectItem>
                              <SelectItem value="ETABLISSEMENT">Établissement</SelectItem>
                              <SelectItem value="NEUTRE">Neutre</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="grid grid-cols-2 gap-3">
                          <div>
                            <Label className="mb-1.5 block">Ajuster les heures</Label>
                            <Input type="number" step="0.25" min="0" value={ajusterHeures} onChange={e => setAjusterHeures(e.target.value)} placeholder="Heures réelles" />
                          </div>
                          <div>
                            <Label className="mb-1.5 block">Ajuster le taux (€/h)</Label>
                            <Input type="number" step="0.01" min="0" value={ajusterTaux} onChange={e => setAjusterTaux(e.target.value)} placeholder="Nouveau taux" />
                          </div>
                        </div>
                        <div className="flex gap-2">
                          <Button size="sm" onClick={resoudreLitige} disabled={actionLitigeId === litige.id || !resolutionText.trim() || !enFaveurDe}>
                            {actionLitigeId === litige.id ? 'Résolution…' : 'Valider la résolution'}
                          </Button>
                          <Button size="sm" variant="ghost" onClick={() => setResolutionFormId(null)}>Annuler</Button>
                        </div>
                      </div>
                    ) : (
                      <div className="flex flex-wrap gap-2">
                        <Button size="sm" onClick={() => openResolutionForm(litige.id)} disabled={actionLitigeId === litige.id}>
                          Résoudre
                        </Button>
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </TabsContent>

          <TabsContent value="evaluations">
            <div className="overflow-x-auto rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Note</TableHead>
                    <TableHead>Commentaire</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {evaluations.map((e) => (
                    <TableRow key={e.id}>
                      <TableCell><Badge variant="outline">{e.note}/5</Badge></TableCell>
                      <TableCell className="max-w-[300px] truncate">{e.commentaire || '—'}</TableCell>
                      <TableCell>{e.type_evaluateur}</TableCell>
                      <TableCell className="text-xs text-muted-foreground">{formatDate(e.cree_le)}</TableCell>
                      <TableCell className="space-x-1 text-right">
                        <Button size="sm" variant="outline" onClick={() => publierEvaluation(e.id)}><Check className="mr-1 h-3.5 w-3.5" />Publier</Button>
                        <Button size="sm" variant="destructive" onClick={() => supprimerEvaluation(e.id)}><X className="mr-1 h-3.5 w-3.5" />Supprimer</Button>
                      </TableCell>
                    </TableRow>
                  ))}
                  {evaluations.length === 0 && <TableRow><TableCell colSpan={5} className="py-8 text-center text-muted-foreground">Aucune évaluation en attente</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>
          </TabsContent>

          <TabsContent value="documents">
            <div className="overflow-x-auto rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Fichier</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {documents.map((d) => (
                    <TableRow key={d.id}>
                      <TableCell className="max-w-[200px] truncate font-medium">{d.nom_fichier}</TableCell>
                      <TableCell><Badge variant="outline" className="text-[10px]">{d.type_document}</Badge></TableCell>
                      <TableCell className="text-xs text-muted-foreground">{d.televerse_le ? formatDate(d.televerse_le) : '—'}</TableCell>
                      <TableCell className="space-x-1 text-right">
                        <Button size="sm" variant="outline" onClick={() => validerDocument(d.id)}><Check className="mr-1 h-3.5 w-3.5" />Valider</Button>
                        <Button size="sm" variant="destructive" onClick={() => rejeterDocument(d.id)}><X className="mr-1 h-3.5 w-3.5" />Rejeter</Button>
                      </TableCell>
                    </TableRow>
                  ))}
                  {documents.length === 0 && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">Aucun document en attente</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>
          </TabsContent>

          <TabsContent value="incoherences">
            <div className="overflow-x-auto rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Soignant</TableHead>
                    <TableHead>Nom Profil</TableHead>
                    <TableHead>Nom RPPS</TableHead>
                    <TableHead>Nom CNI</TableHead>
                    <TableHead>Profil ↔ RPPS</TableHead>
                    <TableHead>Profil ↔ CNI</TableHead>
                    <TableHead>RPPS ↔ CNI</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {incoherences.map((inc: any) => {
                    const matchProfilRpps = inc.nom_profil && inc.nom_rpps
                      ? inc.nom_profil.toUpperCase() === inc.nom_rpps.toUpperCase()
                      : null;
                    const matchProfilCni = inc.nom_profil && inc.nom_cni
                      ? inc.nom_profil.toUpperCase() === inc.nom_cni.toUpperCase()
                      : null;
                    const matchRppsCni = inc.nom_rpps && inc.nom_cni
                      ? inc.nom_rpps.toUpperCase() === inc.nom_cni.toUpperCase()
                      : null;
                    return (
                      <TableRow key={inc.soignant_id}>
                        <TableCell className="font-medium">
                          {inc.prenom_profil} {inc.nom_profil}
                        </TableCell>
                        <TableCell>{inc.nom_profil || '—'}</TableCell>
                        <TableCell>{inc.nom_rpps || '—'}</TableCell>
                        <TableCell>{inc.nom_cni || '—'}</TableCell>
                        <TableCell className="text-center">
                          {matchProfilRpps === null ? '—' : matchProfilRpps ? <Check className="h-4 w-4 text-success mx-auto" /> : <X className="h-4 w-4 text-destructive mx-auto" />}
                        </TableCell>
                        <TableCell className="text-center">
                          {matchProfilCni === null ? '—' : matchProfilCni ? <Check className="h-4 w-4 text-success mx-auto" /> : <X className="h-4 w-4 text-destructive mx-auto" />}
                        </TableCell>
                        <TableCell className="text-center">
                          {matchRppsCni === null ? '—' : matchRppsCni ? <Check className="h-4 w-4 text-success mx-auto" /> : <X className="h-4 w-4 text-destructive mx-auto" />}
                        </TableCell>
                        <TableCell>
                          <Button size="sm" variant="outline" onClick={() => navigate(`/admin/utilisateurs/${inc.soignant_id}`)}>
                            <Eye className="mr-1 h-3.5 w-3.5" />Voir
                          </Button>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                  {incoherences.length === 0 && <TableRow><TableCell colSpan={8} className="py-8 text-center text-muted-foreground">Aucune incohérence identitaire détectée 🎉</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </LayoutAdmin>
  );
}
