import React, { useState, useEffect } from 'react';
import { useSearchParams, Link, useNavigate } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
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
  const map: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
    OUVERTE: 'warning',
    ASSIGNEE: 'info',
    EN_COURS: 'info',
    TERMINEE: 'success',
    ANNULEE: 'error',
  };
  return <BadgeY2K variant={map[statut] ?? 'info'} size="sm">{statut}</BadgeY2K>;
}

export default function AdminMissions() {
  usePageTitle('Missions');
  const navigate = useNavigate();
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

        {(() => {
          const colonnes: ColonneTableau<any>[] = [
            { cle: 'mission', titre: 'Mission' },
            { cle: 'etab', titre: 'Établissement' },
            { cle: 'soignant', titre: 'Soignant' },
            { cle: 'statut', titre: 'Statut' },
            { cle: 'debut', titre: 'Début' },
            { cle: 'duree', titre: 'Durée' },
            { cle: 'taux', titre: 'Taux horaire' },
          ];

          return (
            <TableOuCartes
              colonnes={colonnes}
              donnees={missions}
              getId={(m: any) => m.id}
              onClickLigne={(m: any) => navigate(`/admin/missions/${m.id}`)}
              etatVide={<EmptyState titre="Aucune mission" description={`Aucune mission avec le statut "${filtre}".`} />}
              renduCellule={(m: any, col) => {
                const soignantNom = m.soignants ? `${m.soignants.prenom ?? ''} ${m.soignants.nom ?? ''}`.trim() : null;
                const etabNom = (m.etablissements as any)?.nom ?? null;
                switch (col.cle) {
                  case 'mission':
                    return (
                      <Link
                        to={`/admin/missions/${m.id}`}
                        onClick={(e) => e.stopPropagation()}
                        className="font-medium text-primary hover:underline inline-flex items-center gap-1 group"
                      >
                        {m.intitule}
                        <ExternalLink className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity" />
                      </Link>
                    );
                  case 'etab':
                    return m.etablissement_id ? (
                      <Link to={`/admin/utilisateurs/${m.etablissement_id}`} onClick={(e) => e.stopPropagation()} className="text-primary hover:underline text-sm">
                        {etabNom ?? 'Établissement'}
                      </Link>
                    ) : '—';
                  case 'soignant':
                    return m.soignant_assigne_id ? (
                      <Link to={`/admin/utilisateurs/${m.soignant_assigne_id}`} onClick={(e) => e.stopPropagation()} className="text-primary hover:underline text-sm">
                        {soignantNom || 'Soignant'}
                      </Link>
                    ) : <span className="text-muted-foreground">Non assigné</span>;
                  case 'statut':
                    return statutBadge(m.statut);
                  case 'debut':
                    return (
                      <span className="text-muted-foreground whitespace-nowrap">
                        {formatDate(m.debut_le)}
                        <span className="text-[10px] ml-1">{formatHeure(m.debut_le)}</span>
                      </span>
                    );
                  case 'duree':
                    return <span className="text-muted-foreground">{m.duree_heures ? `${m.duree_heures}h` : '—'}</span>;
                  case 'taux':
                    return <span className="text-muted-foreground">{formatEur(m.taux_horaire_base)}</span>;
                  default:
                    return null;
                }
              }}
              renduCarte={(m: any) => {
                const soignantNom = m.soignants ? `${m.soignants.prenom ?? ''} ${m.soignants.nom ?? ''}`.trim() : null;
                const etabNom = (m.etablissements as any)?.nom ?? null;
                return (
                  <div className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <p className="font-semibold text-foreground inline-flex items-center gap-1 min-w-0">
                        <span className="truncate">{m.intitule}</span>
                        <ExternalLink className="h-3.5 w-3.5 text-primary shrink-0" />
                      </p>
                      {statutBadge(m.statut)}
                    </div>
                    <div className="text-xs text-muted-foreground space-y-0.5">
                      <p>🏥 {etabNom ?? '—'}</p>
                      <p>👤 {soignantNom || 'Non assigné'}</p>
                      <p className="whitespace-nowrap">
                        📅 {formatDate(m.debut_le)} {formatHeure(m.debut_le)} · {m.duree_heures ? `${m.duree_heures}h` : '—'} · {formatEur(m.taux_horaire_base)}
                      </p>
                    </div>
                  </div>
                );
              }}
            />
          );
        })()}
      </div>
    </LayoutAdmin>
  );
}
