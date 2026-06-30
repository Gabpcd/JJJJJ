import React, { useState, useEffect, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, XCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BadgeDistance } from '@/components/BadgeDistance';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import { ModalPerduDeVitesse } from '@/components/ModalPerduDeVitesse';
import { AnimationSuccesMission } from '@/components/AnimationSuccesMission';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { calculerDistanceKm } from '@/lib/geo';
import { getLabelProfession } from '@/lib/constantes';
import { extraireMessageErreur, estBlocageCodeTravail } from '@/lib/erreurs';
import { format, startOfWeek } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

function fmt(v: number | null): string {
  if (v == null || v === 0) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

interface Conflit {
  missionId: string;
  date: string;
  type: 'CHEVAUCHEMENT' | 'REPOS_11H' | 'PLAFOND_48H';
  detail: string;
  article?: string;
}

export default function DetailSerieSoignant() {
  const { serieId } = useParams<{ serieId: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [missions, setMissions] = useState<any[]>([]);
  const [soignant, setSoignant] = useState<any>(null);
  const [missionsExistantes, setMissionsExistantes] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [conflits, setConflits] = useState<Conflit[]>([]);
  const [detailsOuverts, setDetailsOuverts] = useState<Record<string, boolean>>({});

  // Modals
  const [modalConfirm, setModalConfirm] = useState(false);
  const [acceptationEnCours, setAcceptationEnCours] = useState(false);
  const [modalCodeTravail, setModalCodeTravail] = useState<any>(null);
  const [animationSucces, setAnimationSucces] = useState(false);
  const [resultatsAcceptation, setResultatsAcceptation] = useState<{ reussies: number; echouees: number } | null>(null);

  useEffect(() => {
    if (!user || !serieId) return;
    const load = async () => {
      const decoded = decodeURIComponent(serieId);
      const [{ data: allMissions }, { data: s }, { data: existantes }] = await Promise.all([
        supabase.from('missions').select(`
          id, intitule, description, service, profession_requise,
          debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer,
          est_urgente, niveau_urgence, statut, soignant_assigne_id, cree_le, etablissement_id
        `).ilike('description', `%[SERIE_ID:${decoded}]%`).order('debut_le', { ascending: true }),
        supabase.from('soignants').select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides').eq('id', user.id).maybeSingle(),
        supabase.from('missions').select('id, intitule, debut_le, fin_le, duree_heures, statut')
          .eq('soignant_assigne_id', user.id).in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE']).order('debut_le'),
      ]);

      const enriched = allMissions ? await enrichirEtablissements(allMissions as any) : [];
      const mWithDist = enriched.map((m: any) => ({
        ...m,
        distance_km: calculerDistanceKm(s?.adresse_lat, s?.adresse_lng, m.etablissements?.adresse_lat, m.etablissements?.adresse_lng),
      }));
      setMissions(mWithDist);
      setSoignant(s);
      setMissionsExistantes(existantes || []);

      // Auto-select all open
      const openIds = new Set(mWithDist.filter((m: any) => m.statut === 'OUVERTE').map((m: any) => m.id));
      setSelectedIds(openIds);

      setLoading(false);
    };
    load();
  }, [user, serieId]);

  // Compute conflicts
  useEffect(() => {
    if (!missions.length || !missionsExistantes) return;
    const ouvertes = missions.filter(m => selectedIds.has(m.id));
    const toutesLesMissions = [...missionsExistantes, ...ouvertes];
    const newConflits: Conflit[] = [];

    for (const mission of ouvertes) {
      const debut = new Date(mission.debut_le).getTime();
      const fin = new Date(mission.fin_le).getTime();

      for (const existante of toutesLesMissions) {
        if (existante.id === mission.id) continue;
        const debutE = new Date(existante.debut_le).getTime();
        const finE = new Date(existante.fin_le).getTime();

        if (debutE < fin && finE > debut) {
          newConflits.push({ missionId: mission.id, date: mission.debut_le, type: 'CHEVAUCHEMENT', detail: `Chevauchement le ${format(new Date(mission.debut_le), 'd MMM', { locale: fr })}` });
        }
        if (finE <= debut && (debut - finE) < 11 * 3600000 && (debut - finE) >= 0) {
          newConflits.push({ missionId: mission.id, date: mission.debut_le, type: 'REPOS_11H', detail: `Repos insuffisant le ${format(new Date(mission.debut_le), 'd MMM', { locale: fr })} (${((debut - finE) / 3600000).toFixed(1)}h < 11h)`, article: 'L3131-1' });
        }
        if (debutE >= fin && (debutE - fin) < 11 * 3600000 && (debutE - fin) >= 0) {
          newConflits.push({ missionId: mission.id, date: mission.debut_le, type: 'REPOS_11H', detail: `Repos insuffisant après le ${format(new Date(mission.debut_le), 'd MMM', { locale: fr })}`, article: 'L3131-1' });
        }
      }

      // 48h check
      const debutSemaine = startOfWeek(new Date(mission.debut_le), { weekStartsOn: 1 });
      const finSemaine = new Date(debutSemaine.getTime() + 7 * 24 * 3600000);
      const heuresSemaine = toutesLesMissions
        .filter(m => new Date(m.debut_le) >= debutSemaine && new Date(m.debut_le) < finSemaine)
        .reduce((t, m) => t + (m.duree_heures || 0), 0);
      if (heuresSemaine > 48) {
        const alreadyAdded = newConflits.find(c => c.missionId === mission.id && c.type === 'PLAFOND_48H');
        if (!alreadyAdded) {
          newConflits.push({ missionId: mission.id, date: mission.debut_le, type: 'PLAFOND_48H', detail: `Plafond 48h dépassé semaine du ${format(debutSemaine, 'd MMM', { locale: fr })} (${heuresSemaine.toFixed(0)}h)`, article: 'L3121-20' });
        }
      }
    }

    // Deduplicate
    const unique = newConflits.filter((c, i, arr) =>
      arr.findIndex(x => x.missionId === c.missionId && x.type === c.type) === i
    );
    setConflits(unique);
  }, [missions, missionsExistantes, selectedIds]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const ouvertes = missions.filter(m => m.statut === 'OUVERTE');
  const first = missions[0];
  const last = missions[missions.length - 1];
  const distance = first?.distance_km;
  const netTotal = missions.filter(m => selectedIds.has(m.id)).reduce((t: number, m: any) => t + (m.net_a_payer || 0), 0);
  const conflitMissionIds = new Set(conflits.map(c => c.missionId));
  const selectablesCompatibles = ouvertes.filter(m => !conflitMissionIds.has(m.id));
  const toutCompatible = conflits.length === 0;

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const selectAllCompatibles = () => {
    setSelectedIds(new Set(selectablesCompatibles.map(m => m.id)));
  };

  const accepterSerie = async () => {
    const toAccept = ouvertes.filter(m => selectedIds.has(m.id) && !conflitMissionIds.has(m.id));
    if (toAccept.length === 0) return;

    setAcceptationEnCours(true);
    let reussies = 0;
    let echouees = 0;

    for (const mission of toAccept) {
      const { data, error } = await supabase.rpc('fn_accepter_mission' as any, { p_mission_id: mission.id });

      if (error) {
        echouees++;
        if (estBlocageCodeTravail(error)) {
          setModalCodeTravail(error);
          break;
        }
      } else if (data?.choix_requis) {
        // Series don't support contract choice dialog — direct user to mission detail
        toast.error('Choix de contrat requis', {
          description: `La mission "${mission.intitule}" accepte salarié ou libéral : ouvre son détail pour choisir ton mode de contrat avant d'accepter.`,
          duration: 8000,
        });
        echouees++;
      } else if (data?.error) {
        echouees++;
      } else {
        reussies++;
      }
    }

    // Audit HDS — un log par mission acceptée
    for (const mission of toAccept) {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT', p_action: 'MISSION_ASSIGNATION',
        p_type_ressource: 'mission', p_id_ressource: mission.id, p_cle_s3: null,
        p_details: { type: 'acceptation_serie', serie_id: serieId, intitule: mission.intitule },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    }

    setAcceptationEnCours(false);
    setResultatsAcceptation({ reussies, echouees });

    if (reussies > 0 && echouees === 0) {
      setAnimationSucces(true);
      // Redirect to contracts list after animation
      setTimeout(() => navigate('/soignant/contrats'), 2000);
    } else if (reussies > 0) {
      toast.warning(`${reussies} mission(s) acceptée(s), ${echouees} en conflit.`);
      navigate('/soignant/contrats');
    } else {
      toast.error('Aucune mission n\'a pu être acceptée.');
    }
  };

  return (
    <LayoutApp role="SOIGNANT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      {/* Header */}
      <div className="card-base mb-4">
        <div className="flex items-center gap-2 mb-2">
          <span className="badge-base bg-primary/10 text-primary text-[10px]">🔁 Pack de missions</span>
        </div>
        <h1 className="text-lg font-bold text-foreground mb-1">{first?.intitule}</h1>
        {first?.etablissements && (
          <>
            <p className="text-xs text-muted-foreground">🏥 {first.etablissements.nom} · {first.etablissements.adresse_ville}</p>
            <BadgeDistance distanceKm={distance} />
          </>
        )}
        <p className="text-xs text-muted-foreground mt-2">
          📅 Du {format(new Date(first?.debut_le), 'd MMM', { locale: fr })} au {format(new Date(last?.debut_le), 'd MMM yyyy', { locale: fr })}
        </p>
        <p className="text-xs text-muted-foreground">
          📋 {ouvertes.length} créneau{ouvertes.length > 1 ? 'x' : ''} disponible{ouvertes.length > 1 ? 's' : ''} sur {missions.length}
        </p>
      </div>

      {/* Conformity bloc */}
      <div className={`rounded-2xl p-4 border mb-4 ${toutCompatible ? 'bg-success/5 border-success/20' : 'bg-destructive/5 border-destructive/20'}`}>
        <h3 className="text-sm font-bold text-foreground mb-3">🔍 Vérification de compatibilité — Pack complet</h3>
        {toutCompatible ? (
          <div className="space-y-1">
            <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="h-3.5 w-3.5" /> Repos 11h respecté entre chaque créneau</p>
            <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="h-3.5 w-3.5" /> Plafond 48h respecté chaque semaine</p>
            <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="h-3.5 w-3.5" /> Aucun chevauchement avec tes missions existantes</p>
            <p className="text-xs text-success font-medium mt-2">→ Tu peux accepter l'ensemble du pack.</p>
          </div>
        ) : (
          <div className="space-y-2">
            <p className="text-xs text-destructive font-semibold">❌ Conflit détecté sur {conflits.length} créneau{conflits.length > 1 ? 'x' : ''} :</p>
            {conflits.slice(0, 5).map((c, i) => (
              <div key={i} className="text-xs text-muted-foreground ml-4">
                <p>• {c.detail}</p>
                {c.article && (
                  <button onClick={() => setDetailsOuverts(p => ({ ...p, [c.article!]: !p[c.article!] }))}
                    className="text-primary hover:underline text-[10px]">
                    📖 Art. {c.article} [En savoir plus]
                  </button>
                )}
                {c.article && detailsOuverts[c.article] && ARTICLES_CODE_TRAVAIL[c.article] && (
                  <div className="bg-muted/50 rounded-lg p-2 mt-1 text-[10px] space-y-1">
                    <p className="font-semibold">{ARTICLES_CODE_TRAVAIL[c.article].titre}</p>
                    <p>{ARTICLES_CODE_TRAVAIL[c.article].explicationSimple}</p>
                  </div>
                )}
              </div>
            ))}
            {conflits.length > 5 && <p className="text-[10px] text-muted-foreground ml-4">... et {conflits.length - 5} autre(s)</p>}
            <p className="text-xs text-muted-foreground mt-2">💡 Tu peux accepter les créneaux compatibles individuellement.</p>
          </div>
        )}
      </div>

      {/* Créneaux list */}
      <div className="card-base mb-4">
        <h3 className="text-sm font-bold text-foreground mb-3">📋 Créneaux</h3>
        <div className="space-y-2 max-h-96 overflow-y-auto">
          {missions.map(m => {
            const isOpen = m.statut === 'OUVERTE';
            const hasConflict = conflitMissionIds.has(m.id);
            const isSelected = selectedIds.has(m.id);
            const duree = m.duree_heures || ((new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime()) / 3600000);

            return (
              <div key={m.id}
                className={`flex items-center gap-3 p-2.5 rounded-xl border transition-colors ${
                  !isOpen ? 'bg-muted/30 border-border opacity-60' :
                  hasConflict ? 'bg-destructive/5 border-destructive/20' :
                  isSelected ? 'bg-primary/5 border-primary/20' : 'border-border'
                }`}
              >
                {isOpen && !hasConflict && (
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onChange={() => toggleSelect(m.id)}
                    className="h-4 w-4 rounded border-border text-primary"
                  />
                )}
                {isOpen && hasConflict && <XCircle className="h-4 w-4 text-destructive shrink-0" />}
                {!isOpen && <span className="text-muted-foreground text-sm">⬜</span>}

                <div className="flex-1 min-w-0">
                  <p className="text-xs font-medium text-foreground">
                    {format(new Date(m.debut_le), 'EEE d MMM', { locale: fr })} — {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })} ({Math.round(duree)}h)
                  </p>
                  {!isOpen && (
                    <p className="text-[10px] text-muted-foreground">
                      {m.soignant_assigne_id ? 'Déjà pourvue' : m.statut}
                    </p>
                  )}
                  {hasConflict && <p className="text-[10px] text-destructive">⚠️ Conflit détecté</p>}
                </div>

                <div className="shrink-0">
                  {isOpen ? (
                    <span className="text-xs font-medium text-foreground">{fmt(m.net_a_payer)}</span>
                  ) : (
                    <BadgeStatut statut={m.statut} />
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Net total */}
      {netTotal > 0 && (
        <div className="card-base bg-gradient-to-r from-primary/5 to-info/5 mb-4">
          <p className="text-sm font-bold text-foreground">💰 Net estimé total : {fmt(netTotal)}</p>
          <p className="text-[10px] text-muted-foreground/60 italic mt-1">
            Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
          </p>
        </div>
      )}

      {/* Action buttons */}
      <div className="space-y-3">
        {toutCompatible && ouvertes.length > 0 ? (
          <button
            onClick={() => setModalConfirm(true)}
            disabled={acceptationEnCours || selectedIds.size === 0}
            className="btn-primary w-full text-base py-3.5 disabled:opacity-50"
          >
            {acceptationEnCours ? 'Acceptation en cours…' : `★ Tout accepter (${selectedIds.size} créneau${selectedIds.size > 1 ? 'x' : ''})`}
          </button>
        ) : ouvertes.length > 0 ? (
          <>
            <button disabled className="w-full py-3 rounded-xl bg-destructive/10 text-destructive text-sm font-medium cursor-not-allowed">
              ⛔ Tout accepter — Incompatible avec ton planning
            </button>
            {selectablesCompatibles.length > 0 && (
              <button
                onClick={() => { selectAllCompatibles(); setModalConfirm(true); }}
                disabled={acceptationEnCours}
                className="btn-secondary w-full text-sm"
              >
                Accepter les créneaux compatibles ({selectablesCompatibles.length}/{ouvertes.length})
              </button>
            )}
          </>
        ) : null}

        <button onClick={() => navigate(`/soignant/planning?serie=${serieId}`)} className="text-xs text-primary font-medium hover:underline block text-center">
          📅 Voir dans mon planning
        </button>
      </div>

      {/* Modals */}
      <ModalConfirmation
        ouvert={modalConfirm}
        onFermer={() => setModalConfirm(false)}
        onConfirmer={accepterSerie}
        titre={`Accepter ${selectedIds.size} mission${selectedIds.size > 1 ? 's' : ''} ?`}
        message={`Tu t'engages sur ${selectedIds.size} créneau${selectedIds.size > 1 ? 'x' : ''}.`}
        labelConfirmer="Oui, tout accepter"
        labelAnnuler="Annuler"
      />

      {modalCodeTravail && <ModalCodeTravail erreur={modalCodeTravail} onFermer={() => setModalCodeTravail(null)} />}

      {animationSucces && (
        <AnimationSuccesMission
          mission={{ ...first, _message: `${resultatsAcceptation?.reussies || selectedIds.size} missions acceptées !` }}
          onTermine={() => { setAnimationSucces(false); navigate('/soignant/missions'); }}
        />
      )}
    </LayoutApp>
  );
}
