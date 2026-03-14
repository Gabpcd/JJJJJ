import React, { useState, useEffect, useMemo } from 'react';
import { Search, Eye, Ban, RefreshCw } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { supabase } from '@/integrations/supabase/client';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from '@/hooks/use-toast';
import { usePageTitle } from '@/hooks/usePageTitle';

export default function AdminUtilisateurs() {
  usePageTitle('Utilisateurs');
  const [soignants, setSoignants] = useState<any[]>([]);
  const [etabs, setEtabs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [recherche, setRecherche] = useState('');

  const charger = async () => {
    setLoading(true);
    const [resSoignants, resEtabs] = await Promise.all([
      supabase.from('soignants').select('id, prenom, nom, profession, numero_rpps, rpps_verifie, score_fiabilite, total_missions_terminees, supprime_le').order('cree_le', { ascending: false }).limit(500),
      supabase.from('etablissements').select('id, nom, type, siret, supprime_le').order('cree_le', { ascending: false }).limit(500),
    ]);
    if (resSoignants.data) setSoignants(resSoignants.data);
    if (resEtabs.data) setEtabs(resEtabs.data);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const filteredSoignants = useMemo(() => {
    const q = recherche.toLowerCase();
    if (!q) return soignants;
    return soignants.filter(s => `${s.prenom} ${s.nom} ${s.profession}`.toLowerCase().includes(q));
  }, [soignants, recherche]);

  const filteredEtabs = useMemo(() => {
    const q = recherche.toLowerCase();
    if (!q) return etabs;
    return etabs.filter(e => `${e.nom} ${e.siret} ${e.type}`.toLowerCase().includes(q));
  }, [etabs, recherche]);

  const suspendre = async (table: string, id: string) => {
    const { error } = await supabase.from(table as any).update({ supprime_le: new Date().toISOString() } as any).eq('id', id);
    if (error) { toast({ title: 'Erreur', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Utilisateur suspendu' });
    charger();
  };

  const reactiver = async (table: string, id: string) => {
    const { error } = await supabase.from(table as any).update({ supprime_le: null } as any).eq('id', id);
    if (error) { toast({ title: 'Erreur', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Utilisateur réactivé' });
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Gestion utilisateurs</h1>

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
                      <TableCell className="text-right space-x-1">
                        {s.supprime_le ? (
                          <Button size="sm" variant="outline" onClick={() => reactiver('soignants', s.id)}><RefreshCw className="h-3.5 w-3.5 mr-1" />Réactiver</Button>
                        ) : (
                          <Button size="sm" variant="destructive" onClick={() => suspendre('soignants', s.id)}><Ban className="h-3.5 w-3.5 mr-1" />Suspendre</Button>
                        )}
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
                      <TableCell>{e.supprime_le ? <Badge variant="destructive" className="text-[10px]">Suspendu</Badge> : <Badge className="bg-success text-success-foreground text-[10px]">Actif</Badge>}</TableCell>
                      <TableCell className="text-right space-x-1">
                        {e.supprime_le ? (
                          <Button size="sm" variant="outline" onClick={() => reactiver('etablissements', e.id)}><RefreshCw className="h-3.5 w-3.5 mr-1" />Réactiver</Button>
                        ) : (
                          <Button size="sm" variant="destructive" onClick={() => suspendre('etablissements', e.id)}><Ban className="h-3.5 w-3.5 mr-1" />Suspendre</Button>
                        )}
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
  );
}
