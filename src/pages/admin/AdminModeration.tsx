import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';
import { Shield, FileCheck, MessageSquare, Check, X, Eye } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';

const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' });

export default function AdminModeration() {
  usePageTitle('Modération');
  const [litiges, setLitiges] = useState<any[]>([]);
  const [evaluations, setEvaluations] = useState<any[]>([]);
  const [documents, setDocuments] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const charger = async () => {
    setLoading(true);
    const [resLitiges, resEvals, resDocs] = await Promise.all([
      supabase.from('litiges').select('id, motif, reponse, statut, cree_le, soignant_id, etablissement_id, mission_id').in('statut', ['OUVERT', 'EN_DISCUSSION']).order('cree_le', { ascending: true }),
      supabase.from('evaluations').select('id, note, commentaire, type_evaluateur, mission_id, cree_le').eq('visible', false).order('cree_le', { ascending: true }).limit(50),
      supabase.from('documents_soignants').select('id, nom_fichier, type_document, soignant_id, televerse_le').eq('statut_verification', 'EN_ATTENTE').is('supprime_le', null).order('televerse_le', { ascending: true }).limit(50),
    ]);
    if (resLitiges.data) setLitiges(resLitiges.data);
    if (resEvals.data) setEvaluations(resEvals.data);
    if (resDocs.data) setDocuments(resDocs.data);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const resoudreLitige = async (id: string, statut: string) => {
    const resolution = statut === 'FERME' ? 'Fermé par admin' : `Résolu en faveur du ${statut === 'RESOLUE_SOIGNANT' ? 'soignant' : 'établissement'}`;
    const { data, error } = await supabase.rpc('fn_resoudre_litige' as any, { p_litige_id: id, p_statut: statut, p_resolution: resolution });
    if (error) { toast.error(error.message); return; }
    toast.success('Litige résolu');
    charger();
  };

  const publierEvaluation = async (id: string) => {
    const { error } = await supabase.from('evaluations').update({ visible: true } as any).eq('id', id);
    if (error) { toast({ title: 'Erreur', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Évaluation publiée' });
    charger();
  };

  const supprimerEvaluation = async (id: string) => {
    const { error } = await supabase.from('evaluations').delete().eq('id', id);
    if (error) { toast({ title: 'Erreur', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Évaluation supprimée' });
    charger();
  };

  const validerDocument = async (id: string) => {
    const { error } = await supabase.from('documents_soignants').update({ statut_verification: 'VALIDE', verifie_le: new Date().toISOString() } as any).eq('id', id);
    if (error) { toast({ title: 'Erreur', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Document validé' });
    charger();
  };

  const rejeterDocument = async (id: string) => {
    const { error } = await supabase.from('documents_soignants').update({ statut_verification: 'REJETE', verifie_le: new Date().toISOString(), motif_rejet: 'Rejeté par admin' } as any).eq('id', id);
    if (error) { toast({ title: 'Erreur', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Document rejeté' });
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
          </TabsList>

          <TabsContent value="litiges" className="space-y-4">
            {litiges.length === 0 && <p className="text-muted-foreground text-sm py-8 text-center">Aucun litige ouvert 🎉</p>}
            {litiges.map((l) => (
              <Card key={l.id}>
                <CardContent className="pt-4 space-y-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-foreground">{l.motif}</p>
                      {l.reponse && <p className="text-sm text-muted-foreground mt-1">Réponse : {l.reponse}</p>}
                    </div>
                    <Badge variant={l.statut === 'OUVERT' ? 'destructive' : 'secondary'}>{l.statut}</Badge>
                  </div>
                  <p className="text-xs text-muted-foreground">{formatDate(l.cree_le)}</p>
                  <div className="flex gap-2 flex-wrap">
                    <Button size="sm" onClick={() => resoudreLitige(l.id, 'RESOLUE_SOIGNANT')} className="bg-success hover:bg-success/90 text-success-foreground">Résoudre soignant</Button>
                    <Button size="sm" onClick={() => resoudreLitige(l.id, 'RESOLUE_ETABLISSEMENT')} variant="outline">Résoudre établissement</Button>
                    <Button size="sm" onClick={() => resoudreLitige(l.id, 'FERME')} variant="destructive">Fermer</Button>
                  </div>
                </CardContent>
              </Card>
            ))}
          </TabsContent>

          <TabsContent value="evaluations">
            <div className="rounded-lg border overflow-x-auto">
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
                      <TableCell className="text-muted-foreground text-xs">{formatDate(e.cree_le)}</TableCell>
                      <TableCell className="text-right space-x-1">
                        <Button size="sm" variant="outline" onClick={() => publierEvaluation(e.id)}><Check className="h-3.5 w-3.5 mr-1" />Publier</Button>
                        <Button size="sm" variant="destructive" onClick={() => supprimerEvaluation(e.id)}><X className="h-3.5 w-3.5 mr-1" />Supprimer</Button>
                      </TableCell>
                    </TableRow>
                  ))}
                  {evaluations.length === 0 && <TableRow><TableCell colSpan={5} className="text-center text-muted-foreground py-8">Aucune évaluation en attente</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>
          </TabsContent>

          <TabsContent value="documents">
            <div className="rounded-lg border overflow-x-auto">
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
                      <TableCell className="font-medium max-w-[200px] truncate">{d.nom_fichier}</TableCell>
                      <TableCell><Badge variant="outline" className="text-[10px]">{d.type_document}</Badge></TableCell>
                      <TableCell className="text-muted-foreground text-xs">{d.televerse_le ? formatDate(d.televerse_le) : '—'}</TableCell>
                      <TableCell className="text-right space-x-1">
                        <Button size="sm" variant="outline" onClick={() => validerDocument(d.id)}><Check className="h-3.5 w-3.5 mr-1" />Valider</Button>
                        <Button size="sm" variant="destructive" onClick={() => rejeterDocument(d.id)}><X className="h-3.5 w-3.5 mr-1" />Rejeter</Button>
                      </TableCell>
                    </TableRow>
                  ))}
                  {documents.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-muted-foreground py-8">Aucun document en attente</TableCell></TableRow>}
                </TableBody>
              </Table>
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </LayoutAdmin>
  );
}
