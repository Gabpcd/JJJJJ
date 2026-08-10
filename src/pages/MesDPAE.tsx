import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileCheck2, AlertCircle, ExternalLink, Clock } from 'lucide-react';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface DpaeContrat {
  contrat_id: string;
  mission_id: string;
  mission_intitule: string;
  etablissement_id: string;
  etablissement_nom: string;
  debut_le: string;
  fin_le: string;
  type_contrat: string;
  dpae_effectuee: boolean;
  dpae_numero: string | null;
  dpae_effectuee_le: string | null;
  rappel_dpae_affiche: boolean;
  rappel_dpae_affiche_le: string | null;
  statut_contrat: string;
}

type FiltreStatut = 'TOUS' | 'EN_ATTENTE' | 'VALIDEE';

/**
 * Contenu "Mes DPAE" soignant (Sprint 5.5 PR 10, embarqué Session B).
 *
 * Onglet DPAE de /soignant/mes-documents (l'ancienne page dédiée
 * /soignant/dpae redirige) : statut DPAE des contrats CDD/SALARIE signés.
 *  - VALIDEE_URSSAF : numéro URSSAF saisi par l'étab
 *  - EN_ATTENTE_ETAB : étab pas encore déclaré
 *
 * Appelle fn_mes_dpae (RPC Sprint 5.5 PR 10).
 */
export function MesDPAEContent() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [dpae, setDpae] = useState<DpaeContrat[]>([]);
  const [filtre, setFiltre] = useState<FiltreStatut>('TOUS');

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const { data, error } = await supabase.rpc('fn_mes_dpae' as any);
      if (cancelled) return;
      if (error || !(data as any)?.success) {
        setLoading(false);
        return;
      }
      const list = (data as any).dpae as DpaeContrat[];
      setDpae(Array.isArray(list) ? list : []);
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, []);

  const filtrees = useMemo(() => {
    if (filtre === 'TOUS') return dpae;
    if (filtre === 'VALIDEE') return dpae.filter((d) => d.dpae_effectuee);
    return dpae.filter((d) => !d.dpae_effectuee);
  }, [dpae, filtre]);

  const nbEnAttente = dpae.filter((d) => !d.dpae_effectuee).length;
  const nbValidees = dpae.filter((d) => d.dpae_effectuee).length;

  if (loading) return <ChargementPage />;

  return (
    <div>
      <p className="text-sm text-muted-foreground mb-4">
        Suivi des Déclarations Préalables à l'Embauche (DPAE) que tes établissements doivent transmettre à l'URSSAF pour tes missions salariées.
      </p>

      {/* KPIs */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
        <div className="rounded-2xl border-2 border-primary/30 bg-primary/5 p-4">
          <p className="text-xs font-semibold text-foreground">Total contrats salariés signés</p>
          <p className="text-2xl font-bold text-primary tabular-nums mt-1">{dpae.length}</p>
        </div>
        <div className="rounded-2xl border-2 border-success/30 bg-success/5 p-4">
          <p className="text-xs font-semibold text-foreground">Transmission confirmée</p>
          <p className="text-2xl font-bold text-success tabular-nums mt-1">{nbValidees}</p>
        </div>
        <div className="rounded-2xl border-2 border-warning/30 bg-warning/5 p-4">
          <p className="text-xs font-semibold text-foreground">À confirmer par l'étab</p>
          <p className="text-2xl font-bold text-warning tabular-nums mt-1">{nbEnAttente}</p>
        </div>
      </div>

      {/* Filtres */}
      <div className="flex gap-2 mb-4 overflow-x-auto">
        {([
          { v: 'TOUS', label: `Tous (${dpae.length})` },
          { v: 'VALIDEE', label: `Validées (${nbValidees})` },
          { v: 'EN_ATTENTE', label: `En attente (${nbEnAttente})` },
        ] as Array<{ v: FiltreStatut; label: string }>).map((f) => (
          <button
            key={f.v}
            onClick={() => setFiltre(f.v)}
            className={`whitespace-nowrap px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
              filtre === f.v ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* Liste */}
      {(() => {
        const colonnes: ColonneTableau<DpaeContrat>[] = [
          { cle: 'mission', titre: 'Mission' },
          { cle: 'etab', titre: 'Établissement' },
          { cle: 'periode', titre: 'Période' },
          { cle: 'type', titre: 'Type' },
          { cle: 'numero', titre: 'N° URSSAF' },
          { cle: 'statut', titre: 'Statut' },
          { cle: 'actions', titre: '', align: 'right', largeur: 'w-32' },
        ];

        return (
          <TableOuCartes
            colonnes={colonnes}
            donnees={filtrees}
            getId={(d) => d.contrat_id}
            etatVide={(
              <EmptyState
                icone={<FileCheck2 />}
                mascotte="empty"
                titre={dpae.length === 0 ? 'Aucun contrat salarié signé' : 'Aucune DPAE dans cette catégorie'}
                description={dpae.length === 0
                  ? "Les DPAE apparaîtront ici une fois un contrat salarié signé avec un établissement."
                  : 'Changez de filtre pour voir d\'autres DPAE.'}
              />
            )}
            renduCellule={(d, col) => {
              const validee = d.dpae_effectuee && d.dpae_numero;
              switch (col.cle) {
                case 'mission':
                  return <span className="font-medium text-foreground">{d.mission_intitule}</span>;
                case 'etab':
                  return <span className="text-sm text-muted-foreground">{d.etablissement_nom}</span>;
                case 'periode':
                  return (
                    <span className="text-xs text-muted-foreground whitespace-nowrap">
                      {format(new Date(d.debut_le), 'dd/MM/yy', { locale: fr })} → {format(new Date(d.fin_le), 'dd/MM/yy', { locale: fr })}
                    </span>
                  );
                case 'type':
                  return <span className="text-xs">{d.type_contrat}</span>;
                case 'numero':
                  return validee
                    ? <span className="font-mono text-xs select-all">{d.dpae_numero}</span>
                    : <span className="text-xs text-muted-foreground">—</span>;
                case 'statut':
                  return (
                    <span className={`text-[11px] px-2 py-1 rounded-full font-medium whitespace-nowrap ${
                      validee ? 'bg-success text-success-foreground' : 'bg-warning/30 text-warning'
                    }`}>
                      {validee ? '✅ Validée' : '⏳ En attente'}
                    </span>
                  );
                case 'actions':
                  return (
                    <BoutonY2K
                      size="sm"
                      variant="secondary"
                      className="h-8 text-xs"
                      onClick={(e) => { e.stopPropagation(); navigate(`/soignant/missions/${d.mission_id}`); }}
                    >
                      Détail
                    </BoutonY2K>
                  );
                default:
                  return null;
              }
            }}
            renduCarte={(d) => (
              <DpaeCardContent
                dpae={d}
                onVoirContrat={() => navigate(`/contrat/${d.contrat_id}`)}
                onVoirMission={() => navigate(`/soignant/missions/${d.mission_id}`)}
              />
            )}
          />
        );
      })()}

      <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground mt-6">
        <p className="font-semibold text-foreground mb-1">À propos des DPAE</p>
        <ul className="list-disc list-inside space-y-1">
          <li>La DPAE est obligatoire avant toute embauche salariée. L'établissement peut la transmettre à l'URSSAF au plus tôt 8 jours avant le début de mission et doit le faire avant la prise de poste.</li>
          <li>Tu dois avoir complété ton <strong>profil DPAE</strong> (sexe, lieu de naissance, nationalité, NIR) pour que l'établissement puisse préparer les données.</li>
          <li>Jolene prépare et suit les informations ; l'établissement reste responsable de la transmission effective à l'URSSAF.</li>
          <li>Une fois transmise, l'établissement saisit le numéro URSSAF de retour. Tu le retrouves ici.</li>
        </ul>
        <button
          onClick={() => navigate('/soignant/profil')}
          className="text-primary hover:underline text-xs mt-2 inline-flex items-center gap-1"
        >
          Compléter mon profil DPAE <ExternalLink className="h-3 w-3" />
        </button>
      </div>
    </div>
  );
}

function DpaeCardContent({ dpae, onVoirContrat, onVoirMission }: {
  dpae: DpaeContrat;
  onVoirContrat: () => void;
  onVoirMission: () => void;
}) {
  const validee = dpae.dpae_effectuee && dpae.dpae_numero;
  return (
    <div className="space-y-2">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-foreground truncate">{dpae.mission_intitule}</p>
          <p className="text-xs text-muted-foreground">{dpae.etablissement_nom}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Du {format(new Date(dpae.debut_le), 'dd MMM yyyy', { locale: fr })} au {format(new Date(dpae.fin_le), 'dd MMM yyyy', { locale: fr })} · {dpae.type_contrat}
          </p>
        </div>
        <span className={`text-[11px] px-2 py-1 rounded-full font-medium whitespace-nowrap shrink-0 ${
          validee
            ? 'bg-success text-success-foreground'
            : 'bg-warning/30 text-warning'
        }`}>
          {validee ? '✅ Validée URSSAF' : '⏳ En attente'}
        </span>
      </div>

      {validee ? (
        <div className="rounded-lg bg-background/50 border border-success/20 p-2 text-xs">
          <p className="text-muted-foreground">Numéro URSSAF retour :</p>
          <p className="font-mono font-semibold text-foreground select-all">{dpae.dpae_numero}</p>
          {dpae.dpae_effectuee_le && (
            <p className="text-[10px] text-muted-foreground mt-1 inline-flex items-center gap-1">
              <Clock className="h-3 w-3" />
              Saisi le {format(new Date(dpae.dpae_effectuee_le), 'dd MMM yyyy HH:mm', { locale: fr })}
            </p>
          )}
        </div>
      ) : (
        <div className="rounded-lg bg-background/50 border border-warning/20 p-2 text-xs flex items-start gap-2">
          <AlertCircle className="h-4 w-4 shrink-0 text-warning mt-0.5" />
          <p className="text-muted-foreground">
            L'établissement n'a pas encore transmis la DPAE à l'URSSAF ou n'a pas saisi le numéro de retour. Contacte l'établissement si le début de mission approche.
          </p>
        </div>
      )}

      <div className="flex gap-2 pt-1 flex-wrap">
        <BoutonY2K size="sm" variant="primary" className="text-xs min-h-[44px]" onClick={(e) => { e.stopPropagation(); onVoirMission(); }}>
          Détail mission
        </BoutonY2K>
        <BoutonY2K size="sm" variant="secondary" className="text-xs min-h-[44px]" onClick={(e) => { e.stopPropagation(); onVoirContrat(); }}>
          Voir le contrat
        </BoutonY2K>
      </div>
    </div>
  );
}
