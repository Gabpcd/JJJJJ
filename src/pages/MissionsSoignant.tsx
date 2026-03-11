import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { SearchX, Briefcase, History } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { CarteMissionSoignant } from '@/components/CarteMissionSoignant';
import { FiltresMissions, type FiltresMissionsState } from '@/components/FiltresMissions';
import { BadgeStatut } from '@/components/BadgeStatut';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { calculerDistanceKm } from '@/lib/geo';
import { getLabelProfession } from '@/lib/constantes';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

type Onglet = 'disponibles' | 'mes_missions' | 'historique';

interface SoignantData {
  profession: string;
  adresse_lat: number | null;
  adresse_lng: number | null;
  rayon_deplacement_km: number;
  tous_documents_valides: boolean;
}

export default function MissionsSoignant() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [onglet, setOnglet] = useState<Onglet>('disponibles');
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtres, setFiltres] = useState<FiltresMissionsState | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('soignants')
      .select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides')
      .eq('id', user.id)
      .single()
      .then(({ data }) => { if (data) setSoignant(data as any); });
  }, [user]);

  useEffect(() => {
    if (!user || !soignant) return;
    setLoading(true);

    const fetchMissions = async () => {
      let query = supabase
        .from('missions')
        .select(`
          id, intitule, description, service, profession_requise,
          debut_le, fin_le, duree_heures,
          taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
          total_brut, net_a_payer,
          est_urgente, niveau_urgence, statut,
          soignant_assigne_id, cree_le,
          etablissements(id, nom, adresse_ville, adresse_departement, adresse_lat, adresse_lng, type)
        `);

      if (onglet === 'disponibles') {
        query = query
          .eq('statut', 'OUVERTE')
          .eq('profession_requise', soignant.profession)
          .order('est_urgente', { ascending: false })
          .order('debut_le', { ascending: true });

        if (filtres?.dateDebut) query = query.gte('debut_le', filtres.dateDebut);
        if (filtres?.dateFin) query = query.lte('debut_le', filtres.dateFin);
        if (filtres?.tauxMin && filtres.tauxMin > 0) query = query.gte('taux_horaire_base', filtres.tauxMin);
      } else if (onglet === 'mes_missions') {
        query = query
          .eq('soignant_assigne_id', user.id)
          .in('statut', ['ASSIGNEE', 'EN_COURS'])
          .order('debut_le', { ascending: true });
      } else {
        query = query
          .eq('soignant_assigne_id', user.id)
          .in('statut', ['TERMINEE', 'ANNULEE_PAR_SOIGNANT', 'ANNULEE_PAR_ETABLISSEMENT', 'ABSENCE'])
          .order('debut_le', { ascending: false });
      }

      const { data } = await query;
      setMissions(data || []);
      setLoading(false);
    };

    fetchMissions();
  }, [user, soignant, onglet, filtres]);

  const missionsAvecDistance = useMemo(() => {
    if (!soignant) return [];
    let result = missions.map(m => ({
      ...m,
      distance_km: calculerDistanceKm(
        soignant.adresse_lat, soignant.adresse_lng,
        m.etablissements?.adresse_lat ?? null, m.etablissements?.adresse_lng ?? null
      ),
    }));

    // Filtrage par rayon (onglet disponibles uniquement)
    if (onglet === 'disponibles' && filtres) {
      result = result.filter(m => m.distance_km === null || m.distance_km <= filtres.rayonKm);
    }

    // Tri
    if (filtres?.tri === 'proximite') {
      result.sort((a, b) => (a.distance_km ?? 999) - (b.distance_km ?? 999));
    } else if (filtres?.tri === 'taux') {
      result.sort((a, b) => b.taux_horaire_base - a.taux_horaire_base);
    } else if (filtres?.tri === 'duree') {
      result.sort((a, b) => (a.duree_heures ?? 0) - (b.duree_heures ?? 0));
    }

    return result;
  }, [missions, soignant, filtres, onglet]);

  if (!soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const onglets: { id: Onglet; label: string; count?: number }[] = [
    { id: 'disponibles', label: 'Disponibles' },
    { id: 'mes_missions', label: 'Mes missions' },
    { id: 'historique', label: 'Historique' },
  ];

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-4">Missions</h1>

      {/* Onglets */}
      <div className="flex border-b border-border mb-4 overflow-x-auto">
        {onglets.map(o => (
          <button
            key={o.id}
            onClick={() => setOnglet(o.id)}
            className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 transition-colors
              ${onglet === o.id ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
          >
            {o.label}
          </button>
        ))}
      </div>

      {/* Filtres (onglet disponibles uniquement) */}
      {onglet === 'disponibles' && (
        <FiltresMissions
          rayonDefaut={soignant.rayon_deplacement_km}
          onFiltreChange={setFiltres}
        />
      )}

      {loading ? (
        <ChargementPage />
      ) : (
        <>
          {/* Onglet Disponibles */}
          {onglet === 'disponibles' && (
            missionsAvecDistance.length > 0 ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {missionsAvecDistance.map(m => (
                  <CarteMissionSoignant
                    key={m.id}
                    mission={m}
                    soignant={soignant}
                    onClick={() => navigate(`/soignant/missions/${m.id}`)}
                  />
                ))}
              </div>
            ) : (
              <EtatVide
                icone={SearchX}
                titre="Aucune mission disponible pour votre profil"
                sousTitre={`De nouvelles missions pour les ${getLabelProfession(soignant.profession)} sont publiées régulièrement dans votre zone. Revenez bientôt !`}
              />
            )
          )}

          {/* Onglet Mes missions */}
          {onglet === 'mes_missions' && (
            missionsAvecDistance.length > 0 ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {missionsAvecDistance.map(m => (
                  <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all">
                    <div className="flex items-center justify-between mb-2">
                      <BadgeStatut statut={m.statut} />
                      {m.est_urgente && <span className="badge-base bg-destructive text-destructive-foreground text-[10px]">🔥 URGENT</span>}
                    </div>
                    <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-1">🏥 {m.etablissements?.nom} · {m.etablissements?.adresse_ville}</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      📅 {format(new Date(m.debut_le), "EEE d MMM · HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                    </p>
                  </div>
                ))}
              </div>
            ) : (
              <EtatVide
                icone={Briefcase}
                titre="Vous n'avez pas encore de mission en cours"
                sousTitre="Consultez les missions disponibles et postulez !"
                boutonLabel="Voir les missions disponibles"
                boutonRoute="#"
                boutonDisabled={false}
              />
            )
          )}

          {/* Onglet Historique */}
          {onglet === 'historique' && (
            missionsAvecDistance.length > 0 ? (
              <div className="space-y-3">
                {missionsAvecDistance.map(m => (
                  <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all">
                    <div className="flex items-center justify-between mb-2">
                      <BadgeStatut statut={m.statut} />
                      <span className="text-xs text-muted-foreground">{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</span>
                    </div>
                    <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-1">🏥 {m.etablissements?.nom}</p>
                    {m.net_a_payer > 0 && <p className="text-sm font-bold text-primary mt-1">{new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(m.net_a_payer)}</p>}
                  </div>
                ))}
              </div>
            ) : (
              <EtatVide
                icone={History}
                titre="Aucune mission dans l'historique"
                sousTitre="Vos missions terminées et annulées apparaîtront ici."
              />
            )
          )}
        </>
      )}
    </LayoutApp>
  );
}
