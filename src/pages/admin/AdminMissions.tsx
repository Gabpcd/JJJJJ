import React, { useState, useEffect } from 'react';
import { useSearchParams, Link } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { ExternalLink, Clock, CheckCircle, PlayCircle, Send, ClipboardList } from 'lucide-react';

type FiltreStatut = 'TOUTES' | 'OUVERTE' | 'ASSIGNEE' | 'EN_COURS' | 'TERMINEE';

const FILTRES: { cle: FiltreStatut; label: string; icone: React.ElementType; couleur: string }[] = [
  { cle: 'TOUTES', label: 'Toutes', icone: ClipboardList, couleur: 'bg-muted text-foreground' },
  { cle: 'OUVERTE', label: 'Ouvertes', icone: Clock, couleur: 'bg-warning/10 text-warning' },
  { cle: 'ASSIGNEE', label: 'Assignées', icone: Send, couleur: 'bg-info/10 text-info' },
  { cle: 'EN_COURS', label: 'En cours', icone: PlayCircle, couleur: 'bg-primary/10 text-primary' },
  { cle: 'TERMINEE', label: 'Terminées', icone: CheckCircle, couleur: 'bg-success/10 text-success' },
];

const formatDate = (d: string) => d ? new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
const formatHeure = (d: string) => d ? new Date(d).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '';
const formatEur = (v: number | null) => v != null ? `${Number(v).toFixed(2)} €` : '—';

function statutBadge(statut: string) {
  const map: Record<string, string> = {
    OUVERTE: 'bg-warning/10 text-warning border-warning/30',
    ASSIGNEE: 'bg-info/10 text-info border-info/30',
    EN_COURS: 'bg-primary/10 text-primary border-primary/30',
    TERMINEE: 'bg-success/10 text-success border-success/30',
    ANNULEE: 'bg-destructive/10 text-destructive border-destructive/30',
  };
  return <Badge variant="outline" className={`text-[10px] ${map[statut] ?? ''}`}>{statut}</Badge>;
}

export default function AdminMissions() {
  usePageTitle('Missions');
  const [searchParams, setSearchParams] = useSearchParams();
  // Support both ?filtre= (legacy) and ?statut= (from AdminGroupes)
  const filtreParam = (searchParams.get('filtre') || searchParams.get('statut') || 'TOUTES').toUpperCase() as FiltreStatut;
  const groupeParam = searchParams.get('groupe') || null;
  const [filtre, setFiltre] = useState<FiltreStatut>(FILTRES.some(f => f.cle === filtreParam) ? filtreParam : 'TOUTES');
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [groupeNom, setGroupeNom] = useState<string | null>(null);

  useEffect(() => {
    async function charger() {
      setLoading(true);

      // Si filtre par groupe, récupérer les etab IDs du groupe
      let etabIds: string[] | null = null;
      if (groupeParam) {
        const { data: grp } = await supabase
          .from('groupes_sante')
          .select('nom')
          .eq('id', groupeParam)
          .maybeSingle();
        if (grp) setGroupeNom((grp as any).nom);

        const { data: etabs } = await supabase
          .from('etablissements')
          .select('id')
          .eq('groupe_sante_id', groupeParam);
        etabIds = (etabs || []).map((e: any) => e.id);
      }

      let query = supabase
        .from('missions')
        .select('id, intitule, statut, debut_le, fin_le, duree_heures, profession_requise, taux_horaire_base, net_estime, soignant_assigne_id, etablissement_id, etablissements(nom), soignants(prenom, nom)')
        .order('debut_le', { ascending: false })
        .limit(200);

      if (filtre !== 'TOUTES') {
        query = query.eq('statut', filtre);
      }

      if (etabIds && etabIds.length > 0) {
        query = query.in('etablissement_id', etabIds);
      } else if (groupeParam && (!etabIds || etabIds.length === 0)) {
        // Groupe sans établissements → aucune mission
        setMissions([]);
        setLoading(false);
        return;
      }

      const { data } = await query;
      setMissions(data ?? []);
      setLoading(false);
    }
    charger();
  }, [filtre, groupeParam]);

  function changerFiltre(f: FiltreStatut) {
    setFiltre(f);
    const params: Record<string, string> = {};
    if (f !== 'TOUTES') params.filtre = f;
    if (groupeParam) params.groupe = groupeParam;
    setSearchParams(params);
  }

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Missions" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">
          Missions{groupeNom ? <span className="text-primary"> — {groupeNom}</span> : ''}
        </h1>

        {/* Filtres */}
        <div className="flex flex-wrap gap-2">
          {FILTRES.map((f) => (
            <button
              key={f.cle}
              onClick={() => changerFiltre(f.cle)}
              className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all border ${
                filtre === f.cle
                  ? `${f.couleur} border-current ring-1 ring-current/20`
                  : 'bg-muted/50 text-muted-foreground border-transparent hover:bg-muted'
              }`}
            >
              <f.icone className="h-3.5 w-3.5" />
              {f.label}
            </button>
          ))}
        </div>

        {missions.length === 0 ? (
          <EmptyState titre="Aucune mission" description={`Aucune mission avec le statut "${filtre}".`} />
        ) : (
          <Card>
            <CardContent className="pt-5">
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="text-xs">Mission</TableHead>
                      <TableHead className="text-xs">Établissement</TableHead>
                      <TableHead className="text-xs">Soignant</TableHead>
                      <TableHead className="text-xs">Statut</TableHead>
                      <TableHead className="text-xs">Début</TableHead>
                      <TableHead className="text-xs">Durée</TableHead>
                      <TableHead className="text-xs">Taux horaire</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {missions.map((m: any) => {
                      const soignantNom = m.soignants ? `${m.soignants.prenom ?? ''} ${m.soignants.nom ?? ''}`.trim() : null;
                      const etabNom = (m.etablissements as any)?.nom ?? null;
                      return (
                        <TableRow key={m.id} className="text-sm">
                          <TableCell className="font-medium">
                            <Link
                              to={`/admin/missions/${m.id}`}
                              className="text-primary hover:underline inline-flex items-center gap-1 group"
                            >
                              {m.intitule}
                              <ExternalLink className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity" />
                            </Link>
                          </TableCell>
                          <TableCell>
                            {m.etablissement_id ? (
                              <Link to={`/admin/utilisateurs/${m.etablissement_id}`} className="text-primary hover:underline text-sm">
                                {etabNom ?? 'Établissement'}
                              </Link>
                            ) : '—'}
                          </TableCell>
                          <TableCell>
                            {m.soignant_assigne_id ? (
                              <Link to={`/admin/utilisateurs/${m.soignant_assigne_id}`} className="text-primary hover:underline text-sm">
                                {soignantNom || 'Soignant'}
                              </Link>
                            ) : <span className="text-muted-foreground">Non assigné</span>}
                          </TableCell>
                          <TableCell>{statutBadge(m.statut)}</TableCell>
                          <TableCell className="text-muted-foreground whitespace-nowrap">
                            {formatDate(m.debut_le)}
                            <span className="text-[10px] ml-1">{formatHeure(m.debut_le)}</span>
                          </TableCell>
                          <TableCell className="text-muted-foreground">{m.duree_heures ? `${m.duree_heures}h` : '—'}</TableCell>
                          <TableCell className="text-muted-foreground">{formatEur(m.taux_horaire_base)}</TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </LayoutAdmin>
  );
}
