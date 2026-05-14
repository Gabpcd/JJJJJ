import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { BadgeStatut } from '@/components/BadgeStatut';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { FileText } from 'lucide-react';
import { IllustrationStylo } from '@/components/ui/EmptyState';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { UserRole } from '@/lib/types';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

const FILTRES_STATUT = ['Tous', 'EN_ATTENTE_SIGNATURES', 'SIGNE_COMPLET', 'ANNULE'] as const;

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

  const filtered = filtre === 'Tous' ? contrats : contrats.filter(c => c.statut === filtre);

  if (loading) return <ChargementPage />;

  return (
    <>
      <h1 className="text-xl font-bold text-foreground mb-4">{role === 'SOIGNANT' ? 'Mes contrats' : 'Contrats'}</h1>

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

      {filtered.length === 0 ? (() => {
        const isEtab = role === 'ADMIN_ETABLISSEMENT';
        let titre = 'Aucun contrat';
        let sousTitre: string;
        if (filtre === 'EN_ATTENTE_SIGNATURES') {
          titre = 'Aucun contrat en attente';
          sousTitre = isEtab
            ? 'Aucun contrat en attente de signature. Les contrats apparaîtront ici quand un soignant acceptera une mission.'
            : 'Aucun contrat en attente de signature pour le moment.';
        } else if (filtre === 'SIGNE_COMPLET') {
          sousTitre = isEtab
            ? 'Aucun contrat finalisé pour le moment. Les contrats signés par vos soignants s\'afficheront ici.'
            : 'Aucun contrat signé pour le moment.';
        } else if (filtre === 'ANNULE') {
          sousTitre = isEtab
            ? 'Aucun contrat annulé.'
            : 'Aucun contrat annulé.';
        } else {
          sousTitre = isEtab
            ? 'Les contrats apparaîtront ici après qu\'un soignant ait accepté une de vos missions.'
            : 'Vos contrats apparaîtront ici après avoir accepté une mission.';
        }
        return (
          <EmptyState
            illustration={<IllustrationStylo />}
            titre={titre}
            description={sousTitre}
          />
        );
      })() : (
        <div className="space-y-3">
          {filtered.map((c: any) => (
            <div key={c.id} onClick={() => navigate(`/contrat/${c.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <FileText className="h-4 w-4 text-primary" />
                  <span className="text-sm font-semibold text-foreground">{c.numero_contrat || '—'}</span>
                </div>
                <span className={`badge-base text-[10px] ${c.statut === 'SIGNE_COMPLET' ? 'bg-success/10 text-success' : c.statut === 'ANNULE' ? 'bg-destructive/10 text-destructive' : 'bg-warning/10 text-warning'}`}>
                  {c.statut === 'SIGNE_COMPLET' ? '✅ Signé' : c.statut === 'ANNULE' ? '❌ Annulé' : '⏳ En attente'}
                </span>
              </div>
              <p className="text-xs text-muted-foreground">Type : {c.type_contrat}</p>
              <p className="text-xs text-muted-foreground">Mission : {(c.missions as any)?.intitule || '—'}</p>
              <p className="text-xs text-muted-foreground">Créé le {format(new Date(c.cree_le), 'dd/MM/yyyy', { locale: fr })}</p>
              {!c.signature_soignant && role === 'SOIGNANT' && c.statut !== 'ANNULE' && (
                <p className="text-xs text-primary font-medium mt-1">✍️ Signer →</p>
              )}
              {!c.signature_etablissement && role === 'ADMIN_ETABLISSEMENT' && c.statut !== 'ANNULE' && (
                <p className="text-xs text-primary font-medium mt-1">✍️ Signer →</p>
              )}
            </div>
          ))}
        </div>
      )}
    </>
  );
}
