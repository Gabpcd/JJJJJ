import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeStatut } from '@/components/BadgeStatut';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { FileText, ChevronRight } from 'lucide-react';
import { IllustrationStylo } from '@/components/ui/EmptyState';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { UserRole } from '@/lib/types';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

const FILTRES_STATUT = ['Tous', 'EN_ATTENTE_SIGNATURES', 'SIGNE_COMPLET', 'ANNULE'] as const;

export function contratCorrespondAuFiltre(statut: string, filtre: string): boolean {
  if (filtre === 'Tous') return true;
  if (filtre === 'EN_ATTENTE_SIGNATURES') {
    return statut !== 'SIGNE_COMPLET' && statut !== 'ANNULE' && statut !== 'EXPIRE' && statut !== 'REFUSE';
  }
  return statut === filtre;
}

export default function ListeContrats({ role }: { role: UserRole }) {
  usePageTitle('Contrats');
  return (
    <LayoutApp role={role}>
      <ListeContratsContent role={role} />
    </LayoutApp>
  );
}

export function ListeContratsContent({ role }: { role: UserRole }) {
  const { user, etablissementId } = useEtablissementScope();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [contrats, setContrats] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const statutParam = searchParams.get('statut');
  const [filtre, setFiltre] = useState(FILTRES_STATUT.includes((statutParam as any)) ? statutParam! : 'Tous');

  useEffect(() => {
    if (!user || (role === 'ADMIN_ETABLISSEMENT' && !etablissementId)) return;
    const load = async () => {
      const col = role === 'SOIGNANT' ? 'soignant_id' : 'etablissement_id';
      const valeur = role === 'SOIGNANT' ? user.id : etablissementId;
      const { data } = await supabase
        .from('contrats_mission')
        .select('id, mission_id, numero_contrat, type_contrat, statut, soignant_id, etablissement_id, signature_soignant, signature_etablissement, cree_le, missions(intitule, debut_le, fin_le)')
        .eq(col, valeur)
        .order('cree_le', { ascending: false });
      setContrats(data || []);
      setLoading(false);
    };
    load();
  }, [user, role, etablissementId]);

  useEffect(() => {
    if (statutParam && FILTRES_STATUT.includes(statutParam as any)) {
      setFiltre(statutParam);
      return;
    }
    setFiltre('Tous');
  }, [statutParam]);

  const filtered = contrats.filter(c => contratCorrespondAuFiltre(c.statut, filtre));

  if (loading) return <ChargementPage />;

  return (
    <>
      {role === 'SOIGNANT' ? (
        <h2 className="text-xl font-bold text-foreground mb-4">Mes contrats</h2>
      ) : (
        <h1 className="text-xl font-bold text-foreground mb-4">Contrats</h1>
      )}

      <div className="flex gap-2 mb-4 flex-wrap">
        {FILTRES_STATUT.map(f => (
          <button
            key={f}
            onClick={() => {
              setFiltre(f);
              if (f === 'Tous') setSearchParams({}, { replace: true });
              else setSearchParams({ statut: f }, { replace: true });
            }}
            className={`badge-base transition-colors ${filtre === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-accent'}`}
          >
            {f === 'Tous' ? 'Tous' : f === 'EN_ATTENTE_SIGNATURES' ? 'En attente' : f === 'SIGNE_COMPLET' ? 'Signés' : 'Annulés'}
          </button>
        ))}
      </div>

      {(() => {
        const isEtab = role === 'ADMIN_ETABLISSEMENT';
        let titreVide = 'Aucun contrat';
        let descVide: string;
        if (filtre === 'EN_ATTENTE_SIGNATURES') {
          titreVide = 'Aucun contrat en attente';
          descVide = isEtab
            ? 'Aucun contrat en attente de signature. Les contrats apparaîtront ici quand un soignant acceptera une mission.'
            : 'Aucun contrat en attente de signature pour le moment.';
        } else if (filtre === 'SIGNE_COMPLET') {
          descVide = isEtab
            ? 'Aucun contrat finalisé pour le moment. Les contrats signés par vos soignants s\'afficheront ici.'
            : 'Aucun contrat signé pour le moment.';
        } else if (filtre === 'ANNULE') {
          descVide = 'Aucun contrat annulé.';
        } else {
          descVide = isEtab
            ? 'Les contrats apparaîtront ici après qu\'un soignant ait accepté une de vos missions.'
            : 'Vos contrats apparaîtront ici après avoir accepté une mission.';
        }

        const colonnes: ColonneTableau<any>[] = [
          { cle: 'numero', titre: 'N° contrat' },
          { cle: 'mission', titre: 'Mission' },
          { cle: 'type', titre: 'Type' },
          { cle: 'date', titre: 'Créé le' },
          { cle: 'statut', titre: 'Statut' },
          { cle: 'actions', titre: '', align: 'right', largeur: 'w-28' },
        ];

        const aSigner = (c: any) =>
          c.statut !== 'ANNULE' &&
          ((role === 'SOIGNANT' && !c.signature_soignant) ||
            (role === 'ADMIN_ETABLISSEMENT' && !c.signature_etablissement));

        const badgeStatut = (statut: string) => (
          <span className={`badge-base text-[10px] ${statut === 'SIGNE_COMPLET' ? 'bg-success/10 text-success' : statut === 'ANNULE' ? 'bg-destructive/10 text-destructive' : 'bg-warning/10 text-warning'}`}>
            {statut === 'SIGNE_COMPLET' ? '✅ Signé' : statut === 'ANNULE' ? '❌ Annulé' : '⏳ En attente'}
          </span>
        );

        return (
          <TableOuCartes
            colonnes={colonnes}
            donnees={filtered}
            getId={(c: any) => c.id}
            onClickLigne={(c: any) => navigate(`/contrat/${c.id}`)}
            etatVide={<EmptyState illustration={<IllustrationStylo />} titre={titreVide} description={descVide} />}
            renduCellule={(c: any, col) => {
              switch (col.cle) {
                case 'numero':
                  return (
                    <span className="inline-flex items-center gap-1.5 font-medium text-foreground">
                      <FileText className="h-3.5 w-3.5 text-primary" />
                      {c.numero_contrat || '—'}
                    </span>
                  );
                case 'mission':
                  return <span className="text-sm text-muted-foreground line-clamp-1">{(c.missions as any)?.intitule || '—'}</span>;
                case 'type':
                  return <span className="text-xs">{c.type_contrat}</span>;
                case 'date':
                  return <span className="text-xs text-muted-foreground whitespace-nowrap">{format(new Date(c.cree_le), 'dd/MM/yyyy', { locale: fr })}</span>;
                case 'statut':
                  return badgeStatut(c.statut);
                case 'actions':
                  return aSigner(c) ? (
                    <BoutonY2K size="sm" variant="primary" className="h-8 text-xs" onClick={(e) => { e.stopPropagation(); navigate(`/contrat/${c.id}`); }}>
                      ✍️ Signer
                    </BoutonY2K>
                  ) : (
                    <BoutonY2K size="sm" variant="secondary" className="h-8 text-xs" onClick={(e) => { e.stopPropagation(); navigate(`/contrat/${c.id}`); }}>
                      Voir
                    </BoutonY2K>
                  );
                default:
                  return null;
              }
            }}
            renduCarte={(c: any) => (
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <FileText className="h-4 w-4 text-primary shrink-0" />
                    <span className="text-sm font-semibold text-foreground truncate">{c.numero_contrat || '—'}</span>
                  </div>
                  {badgeStatut(c.statut)}
                </div>
                <p className="text-xs text-muted-foreground line-clamp-1">📋 {(c.missions as any)?.intitule || '—'}</p>
                <p className="text-xs text-muted-foreground">{c.type_contrat} · Créé le {format(new Date(c.cree_le), 'dd/MM/yyyy', { locale: fr })}</p>
                <BoutonY2K
                  size="sm"
                  variant={aSigner(c) ? 'primary' : 'secondary'}
                  className="w-full min-h-[44px]"
                  onClick={(e) => { e.stopPropagation(); navigate(`/contrat/${c.id}`); }}
                  iconeDroite={!aSigner(c) ? <ChevronRight className="h-4 w-4" /> : undefined}
                >
                  {aSigner(c) ? '✍️ Signer le contrat' : 'Voir le contrat'}
                </BoutonY2K>
              </div>
            )}
          />
        );
      })()}
    </>
  );
}
