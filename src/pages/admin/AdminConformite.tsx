import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { ShieldAlert, Clock, FileWarning, FileQuestion, Repeat, UserX, FileX, ChevronDown, Loader2 } from 'lucide-react';

interface Indicateur {
  cle: string;
  rpcCle: string;
  label: string;
  icone: React.ElementType;
  colonnes: string[];
  renderRow: (item: any) => React.ReactNode;
}

const formatDate = (d: string) => d ? new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';

const INDICATEURS: Indicateur[] = [
  {
    cle: 'violations_repos_11h',
    rpcCle: 'repos_11h_violations',
    label: 'Violations repos 11h',
    icone: Clock,
    colonnes: ['Soignant', 'Mission', 'Établissement', 'Résultat', 'Date'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.soignant_nom}</TableCell>
        <TableCell>{item.mission_intitule}</TableCell>
        <TableCell>{item.etablissement_nom}</TableCell>
        <TableCell><Badge variant="destructive" className="text-[10px]">{item.resultat}</Badge></TableCell>
        <TableCell className="text-muted-foreground">{formatDate(item.controle_le)}</TableCell>
      </>
    ),
  },
  {
    cle: 'alertes_48h',
    rpcCle: 'plafond_48h_alertes',
    label: 'Alertes 48h',
    icone: ShieldAlert,
    colonnes: ['Soignant', 'Profession', 'Heures cette semaine'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.soignant_nom}</TableCell>
        <TableCell><Badge variant="outline" className="text-[10px]">{item.profession}</Badge></TableCell>
        <TableCell className="font-semibold text-destructive">{item.heures_semaine}h</TableCell>
      </>
    ),
  },
  {
    cle: 'docs_expires',
    rpcCle: 'documents_expires',
    label: 'Documents expirés',
    icone: FileWarning,
    colonnes: ['Soignant', 'Profession', 'Document', 'Expiré le'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.soignant_nom}</TableCell>
        <TableCell><Badge variant="outline" className="text-[10px]">{item.profession}</Badge></TableCell>
        <TableCell>{item.type_document}</TableCell>
        <TableCell className="text-destructive">{formatDate(item.valide_jusqua)}</TableCell>
      </>
    ),
  },
  {
    cle: 'docs_en_attente',
    rpcCle: 'documents_en_attente',
    label: 'Documents en attente',
    icone: FileQuestion,
    colonnes: ['Soignant', 'Profession', 'Document', 'Téléversé le'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.soignant_nom}</TableCell>
        <TableCell><Badge variant="outline" className="text-[10px]">{item.profession}</Badge></TableCell>
        <TableCell>{item.type_document}</TableCell>
        <TableCell className="text-muted-foreground">{formatDate(item.televerse_le)}</TableCell>
      </>
    ),
  },
  {
    cle: 'cddu_repetitifs',
    rpcCle: 'cddu_repetitifs',
    label: 'CDDU répétitifs',
    icone: Repeat,
    colonnes: ['Soignant', 'Établissement', 'Nb missions', 'Première', 'Dernière'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.soignant_nom}</TableCell>
        <TableCell>{item.etablissement_nom}</TableCell>
        <TableCell className="font-semibold">{item.nb_missions}</TableCell>
        <TableCell className="text-muted-foreground">{formatDate(item.premiere_mission)}</TableCell>
        <TableCell className="text-muted-foreground">{formatDate(item.derniere_mission)}</TableCell>
      </>
    ),
  },
  {
    cle: 'soignants_sans_docs',
    rpcCle: 'soignants_sans_docs',
    label: 'Soignants sans documents',
    icone: UserX,
    colonnes: ['Soignant', 'Profession', 'Email', 'Inscrit le'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.soignant_nom}</TableCell>
        <TableCell><Badge variant="outline" className="text-[10px]">{item.profession}</Badge></TableCell>
        <TableCell className="text-muted-foreground">{item.email}</TableCell>
        <TableCell className="text-muted-foreground">{formatDate(item.cree_le)}</TableCell>
      </>
    ),
  },
  {
    cle: 'missions_sans_contrat',
    rpcCle: 'missions_sans_contrat',
    label: 'Missions sans contrat',
    icone: FileX,
    colonnes: ['Mission', 'Établissement', 'Soignant', 'Statut', 'Début'],
    renderRow: (item: any) => (
      <>
        <TableCell className="font-medium">{item.intitule}</TableCell>
        <TableCell>{item.etablissement_nom}</TableCell>
        <TableCell>{item.soignant_nom ?? '—'}</TableCell>
        <TableCell><Badge variant="secondary" className="text-[10px]">{item.statut}</Badge></TableCell>
        <TableCell className="text-muted-foreground">{formatDate(item.debut_le)}</TableCell>
      </>
    ),
  },
];

function getCouleur(val: number): string {
  if (val === 0) return 'text-success';
  if (val <= 5) return 'text-warning';
  return 'text-destructive';
}

function getBgCouleur(val: number): string {
  if (val === 0) return 'bg-success/10 border-success/20';
  if (val <= 5) return 'bg-warning/10 border-warning/20';
  return 'bg-destructive/10 border-destructive/20';
}

export default function AdminConformite() {
  usePageTitle('Conformité');
  const [data, setData] = useState<Record<string, number> | null>(null);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<any[] | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);

  useEffect(() => {
    supabase.rpc('fn_admin_conformite' as any).then(({ data: d }: any) => {
      if (d && typeof d === 'object' && !Array.isArray(d)) setData(d);
      else if (Array.isArray(d) && d[0]) setData(d[0]);
      setLoading(false);
    });
  }, []);

  async function toggleDetail(cle: string) {
    if (selected === cle) {
      setSelected(null);
      setDetail(null);
      return;
    }
    setSelected(cle);
    setDetail(null);
    setLoadingDetail(true);
    const { data: d } = await supabase.rpc('fn_admin_conformite_detail' as any, { p_type: cle });
    setDetail(Array.isArray(d) ? d : []);
    setLoadingDetail(false);
  }

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  // Map RPC keys to frontend keys
  const mappedData: Record<string, number> = {};
  if (data) {
    INDICATEURS.forEach(ind => {
      mappedData[ind.cle] = data[ind.cle] ?? data[ind.rpcCle] ?? 0;
    });
  }

  const selectedInd = INDICATEURS.find(i => i.cle === selected);

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Conformité" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Conformité</h1>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {INDICATEURS.map((ind) => {
            const val = mappedData[ind.cle] ?? 0;
            const isSelected = selected === ind.cle;
            return (
              <Card
                key={ind.cle}
                className={`border cursor-pointer transition-all hover:shadow-md ${getBgCouleur(val)} ${isSelected ? 'ring-2 ring-primary' : ''}`}
                onClick={() => toggleDetail(ind.cle)}
              >
                <CardContent className="pt-5 pb-5 flex items-center gap-4">
                  <div className={`rounded-xl p-2.5 ${getBgCouleur(val)}`}>
                    <ind.icone className={`h-5 w-5 ${getCouleur(val)}`} />
                  </div>
                  <div className="flex-1">
                    <p className={`text-2xl font-bold ${getCouleur(val)}`}>{val}</p>
                    <p className="text-xs text-muted-foreground">{ind.label}</p>
                  </div>
                  <ChevronDown className={`h-4 w-4 text-muted-foreground transition-transform ${isSelected ? 'rotate-180' : ''}`} />
                </CardContent>
              </Card>
            );
          })}
        </div>

        {/* Detail panel */}
        {selected && selectedInd && (
          <Card className="animate-in fade-in-0 slide-in-from-top-2 duration-200">
            <CardContent className="pt-5">
              <div className="flex items-center gap-2 mb-4">
                <selectedInd.icone className="h-5 w-5 text-foreground" />
                <h2 className="text-base font-semibold text-foreground">{selectedInd.label}</h2>
                <Badge variant="outline" className="ml-auto">{mappedData[selected] ?? 0} élément(s)</Badge>
              </div>

              {loadingDetail ? (
                <div className="flex justify-center py-8">
                  <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                </div>
              ) : detail && detail.length > 0 ? (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        {selectedInd.colonnes.map(col => (
                          <TableHead key={col} className="text-xs">{col}</TableHead>
                        ))}
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {detail.map((item: any, i: number) => (
                        <TableRow key={item.id ?? i} className="text-sm">
                          {selectedInd.renderRow(item)}
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              ) : (
                <p className="text-sm text-muted-foreground text-center py-6">Aucun élément à afficher</p>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </LayoutAdmin>
  );
}
