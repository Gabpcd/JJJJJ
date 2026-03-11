import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { ClipboardPlus, Search, X } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteMission } from '@/components/CarteMission';
import { CarteSerie, extraireSerieId } from '@/components/CarteSerie';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { ChargementPage } from '@/components/ChargementPage';
import { FABCreerMission } from '@/components/FABCreerMission';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

const STATUTS_FILTRES = [
  { valeur: '', label: 'Toutes' },
  { valeur: 'OUVERTE', label: 'Ouvertes' },
  { valeur: 'ASSIGNEE', label: 'Assignées' },
  { valeur: 'EN_COURS', label: 'En cours' },
  { valeur: 'TERMINEE', label: 'Terminées' },
  { valeur: 'ANNULEE_PAR_ETABLISSEMENT', label: 'Annulées' },
  { valeur: 'LITIGE', label: 'Litiges' },
];

type GroupeMission = { type: 'single'; mission: any } | { type: 'serie'; serieId: string; missions: any[] };

export default function ListeMissions() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [missions, setMissions] = useState<any[]>([]);
  const [filtreStatut, setFiltreStatut] = useState('');
  const [recherche, setRecherche] = useState('');
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [modalDupliquer, setModalDupliquer] = useState<any>(null);
  const [modalAnnuler, setModalAnnuler] = useState<any>(null);
  const [modalAnnulerSerie, setModalAnnulerSerie] = useState<any[] | null>(null);

  const charger = async () => {
    if (!user) return;
    setLoading(true);

    let query = supabase
      .from('missions')
      .select('id, intitule, description, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer, statut, est_urgente, niveau_urgence, soignant_assigne_id, soignants(prenom, nom, score_fiabilite), cree_le')
      .eq('etablissement_id', user.id)
      .order('debut_le', { ascending: false });

    if (filtreStatut) query = query.eq('statut', filtreStatut as any);
    if (recherche) query = query.ilike('intitule', `%${recherche}%`);

    const { data } = await query;
    setMissions(data || []);

    const statuts = ['', 'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'LITIGE'];
    const results = await Promise.all(
      statuts.map(s => {
        let q = supabase.from('missions').select('*', { count: 'exact', head: true }).eq('etablissement_id', user.id);
        if (s) q = q.eq('statut', s as any);
        return q;
      })
    );
    const c: Record<string, number> = {};
    statuts.forEach((s, i) => { c[s] = results[i].count ?? 0; });
    setCounts(c);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, filtreStatut, recherche]);

  // Group missions by serie
  const groupes = useMemo((): GroupeMission[] => {
    const seriesMap = new Map<string, any[]>();
    const singles: any[] = [];

    for (const m of missions) {
      const sid = extraireSerieId(m.description);
      if (sid) {
        if (!seriesMap.has(sid)) seriesMap.set(sid, []);
        seriesMap.get(sid)!.push(m);
      } else {
        singles.push(m);
      }
    }

    const result: GroupeMission[] = [];
    // Series first
    for (const [serieId, ms] of seriesMap) {
      result.push({ type: 'serie', serieId, missions: ms });
    }
    // Singles
    for (const m of singles) {
      result.push({ type: 'single', mission: m });
    }
    return result;
  }, [missions]);

  const handleAnnuler = async (mission: any) => {
    const { error } = await supabase
      .from('missions')
      .update({ statut: 'ANNULEE_PAR_ETABLISSEMENT', modifie_le: new Date().toISOString() } as any)
      .eq('id', mission.id);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'MISSION_ANNULATION',
        p_type_ressource: 'mission', p_id_ressource: mission.id, p_cle_s3: null,
        p_details: { intitule: mission.intitule }, p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: 'Mission annulée.' });
      charger();
    }
  };

  const handleAnnulerSerie = async (missionsSerieOuvertes: any[]) => {
    let reussies = 0;
    for (const m of missionsSerieOuvertes) {
      const { error } = await supabase
        .from('missions')
        .update({ statut: 'ANNULEE_PAR_ETABLISSEMENT', modifie_le: new Date().toISOString() } as any)
        .eq('id', m.id)
        .eq('statut', 'OUVERTE');
      if (!error) reussies++;
    }
    // Audit HDS — un log par mission annulée
    for (const m of missionsSerieOuvertes) {
      await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'MISSION_ANNULATION',
        p_type_ressource: 'mission', p_id_ressource: m.id, p_cle_s3: null,
        p_details: { type: 'annulation_serie', intitule: m.intitule }, p_ip: null, p_navigateur: navigator.userAgent,
      });
    }
    afficherNotification({ type: 'succes', message: `${reussies} mission(s) annulée(s).` });
    charger();
  };

  if (loading) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ETABLISSEMENT">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-foreground">Mes missions</h1>
        <button onClick={() => navigate('/etablissement/missions/creer')} className="btn-primary text-sm hidden md:inline-flex">
          + Publier une mission
        </button>
      </div>

      {/* Filtres */}
      <div className="mb-4 overflow-x-auto">
        <div className="flex gap-2 pb-2">
          {STATUTS_FILTRES.map(s => (
            <button key={s.valeur} onClick={() => setFiltreStatut(s.valeur)}
              className={`badge-base whitespace-nowrap transition-colors ${filtreStatut === s.valeur ? 'bg-primary text-primary-foreground font-semibold' : 'bg-muted text-muted-foreground hover:bg-muted/80'}`}>
              {s.label} ({counts[s.valeur] ?? 0})
            </button>
          ))}
        </div>
      </div>

      {/* Recherche */}
      <div className="relative mb-4">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <input value={recherche} onChange={(e) => setRecherche(e.target.value)}
          placeholder="🔍 Rechercher par intitulé, service ou soignant..." className="input-base pl-9 pr-9" />
        {recherche && (
          <button onClick={() => setRecherche('')} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
            <X className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Liste */}
      {groupes.length > 0 ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {groupes.map((g, i) => {
            if (g.type === 'serie') {
              return (
                <CarteSerie
                  key={g.serieId}
                  missions={g.missions}
                  role="etablissement"
                  onAnnulerSerie={() => setModalAnnulerSerie(g.missions.filter((m: any) => m.statut === 'OUVERTE'))}
                />
              );
            }
            return (
              <CarteMission
                key={g.mission.id}
                mission={g.mission}
                onDupliquer={(m) => setModalDupliquer(m)}
                onAnnuler={(m) => setModalAnnuler(m)}
                onRepublier={(m) => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)}
              />
            );
          })}
        </div>
      ) : (
        <EtatVide icone={ClipboardPlus} titre="Publiez votre première mission"
          sousTitre="Les soignants qualifiés seront notifiés immédiatement"
          boutonLabel="Publier une mission" boutonRoute="/etablissement/missions/creer" />
      )}

      <FABCreerMission />

      <ModalConfirmation ouvert={!!modalDupliquer} onFermer={() => setModalDupliquer(null)}
        onConfirmer={() => navigate(`/etablissement/missions/creer?dupliquer=${modalDupliquer.id}`)}
        titre="Dupliquer cette mission ?" message={`Une copie de « ${modalDupliquer?.intitule} » sera créée.`}
        labelConfirmer="Dupliquer" />

      <ModalConfirmation ouvert={!!modalAnnuler} onFermer={() => setModalAnnuler(null)}
        onConfirmer={() => handleAnnuler(modalAnnuler)}
        titre="Annuler cette mission ?" message={`La mission « ${modalAnnuler?.intitule} » sera définitivement annulée.`}
        labelConfirmer="Annuler la mission" variante="danger" />

      <ModalConfirmation ouvert={!!modalAnnulerSerie} onFermer={() => setModalAnnulerSerie(null)}
        onConfirmer={() => { if (modalAnnulerSerie) handleAnnulerSerie(modalAnnulerSerie); setModalAnnulerSerie(null); }}
        titre="Annuler toute la série ?" message={`${modalAnnulerSerie?.length || 0} mission(s) ouverte(s) seront annulées. Cette action est irréversible.`}
        labelConfirmer="Annuler la série" variante="danger" />
    </LayoutApp>
  );
}
