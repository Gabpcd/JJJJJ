import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CarteValidation } from '@/components/CarteValidation';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { RpcSuccessOrError, RpcValiderPresencesLot } from '@/lib/supabase-rpc-types';
import { ClipboardCheck, CheckCircle, Clock, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { useSearchParams } from 'react-router-dom';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

export default function PresencesEtablissement() {
  usePageTitle('Présences');
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [presences, setPresences] = useState<any[]>([]);
  const [litiges, setLitiges] = useState<Record<string, any>>({});
  const [loading, setLoading] = useState(true);
  const [modalLot, setModalLot] = useState(false);
  const tabParam = searchParams.get('tab');
  const [activeTab, setActiveTab] = useState(['a_valider', 'en_cours', 'validees', 'alertes'].includes(tabParam || '') ? tabParam! : 'validees');

  const charger = useCallback(async () => {
    if (!user || !etablissementId) return;
    const [{ data: presData }, { data: soignantsData }, { data: litigesData }] = await Promise.all([
      supabase
        .from('presences')
        .select(`
          id, mission_id, soignant_id,
          pointage_arrivee_le, pointage_depart_le,
          arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
          depart_lat, depart_lng, depart_precision_gps_m,
          distance_etablissement_m, perimetre_gps_valide,
          alerte_teleportation, alertes_fraude,
          arrivee_mock_detected, depart_mock_detected, coherence_incidents,
          valide_par_etablissement, valide_le, motif_litige,
          missions!inner(intitule, service, debut_le, fin_le, duree_heures, etablissement_id)
        `)
        .eq('missions.etablissement_id', etablissementId)
        .not('pointage_arrivee_le', 'is', null)
        .order('pointage_arrivee_le', { ascending: false }),
      supabase.rpc('fn_mes_soignants_etablissement'),
      supabase
        .from('litiges')
        .select('id, mission_id, motif, statut, initie_par, cree_le, resolution, accord_soignant, accord_etablissement')
        .eq('etablissement_id', etablissementId),
    ]);

    // Build litiges map by mission_id
    const litigesMap: Record<string, any> = {};
    if (Array.isArray(litigesData)) {
      for (const l of litigesData) {
        litigesMap[l.mission_id] = l;
      }
    }
    setLitiges(litigesMap);

    const sgMap: Record<string, any> = {};
    if (Array.isArray(soignantsData)) {
      for (const s of soignantsData) sgMap[s.id] = s;
    }

    if (Object.keys(sgMap).length === 0 && Array.isArray(presData)) {
      const soignantIds = [...new Set(presData.map((p: any) => p.soignant_id).filter(Boolean))];
      if (soignantIds.length > 0) {
        const { data: soignantsDirect } = await supabase
          .from('soignants')
          .select('id, prenom, nom, profession, telephone')
          .in('id', soignantIds);
        if (Array.isArray(soignantsDirect)) {
          for (const s of soignantsDirect) sgMap[s.id] = s;
        }
      }
    }

    setPresences((presData || []).map((p: any) => ({
      ...p,
      soignants: sgMap[p.soignant_id] || null,
    })));
    setLoading(false);
  }, [user, etablissementId]);

  // Combined data loading + tab sync to avoid race conditions between URL param and state
  useEffect(() => {
    charger();
    if (tabParam && ['a_valider', 'en_cours', 'validees', 'alertes'].includes(tabParam) && tabParam !== activeTab) {
      setActiveTab(tabParam);
    }
  }, [charger, tabParam]); // eslint-disable-line react-hooks/exhaustive-deps

  const aValider = presences.filter(p => !p.valide_par_etablissement && p.pointage_depart_le);
  const validees = presences.filter(p => p.valide_par_etablissement);
  const enCours = presences.filter(p => !p.pointage_depart_le);
  const alertes = presences.filter(p => p.alerte_teleportation || !p.perimetre_gps_valide);

  const presencesSansAlerte = aValider.filter(p =>
    p.perimetre_gps_valide === true && !p.alerte_teleportation
  );

  const validerUne = async (presenceId: string) => {
    // Optimistic: immediately move presence to "validées"
    const prevPresences = presences;
    setPresences(prev =>
      prev.map(p => p.id === presenceId ? { ...p, valide_par_etablissement: true, valide_le: new Date().toISOString() } : p)
    );

    const { data, error } = await supabase.rpc('fn_valider_presence', { p_presence_id: presenceId });
    const result = data as unknown as RpcSuccessOrError | null;

    if (error || (result && !result.success)) {
      setPresences(prevPresences); // Revert on error
      afficherNotification({ type: 'erreur', message: result?.error || extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_VALIDATION', p_type_ressource: 'presence',
        p_id_ressource: presenceId, p_cle_s3: null,
        p_details: { type: 'validation_individuelle' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: '✅ Présence validée !' });
      charger(); // Refresh from server to ensure consistency
    }
  };

  const contester = async (presenceId: string, motif: string) => {
    const { data, error } = await supabase.rpc('fn_contester_presence', {
      p_presence_id: presenceId,
      p_motif: motif,
    });
    const result = data as unknown as RpcSuccessOrError | null;

    if (error || (result && !result.success)) {
      afficherNotification({ type: 'erreur', message: result?.error || extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_CONTESTATION', p_type_ressource: 'presence',
        p_id_ressource: presenceId, p_cle_s3: null,
        p_details: { motif },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'avertissement', message: 'Contestation enregistrée.' });
      charger();
    }
  };

  const validerEnLot = async () => {
    if (presencesSansAlerte.length === 0) {
      afficherNotification({ type: 'info', message: 'Aucune présence éligible à la validation automatique.' });
      return;
    }

    const ids = presencesSansAlerte.map(p => p.id);

    const { data, error } = await supabase.rpc('fn_valider_presences_lot', { p_ids: ids });
    const result = data as unknown as RpcValiderPresencesLot | null;

    if (error || (result && !result.success)) {
      afficherNotification({ type: 'erreur', message: result?.error || extraireMessageErreur(error) });
    } else {
      const nbValidees = result?.nb_validees ?? ids.length;
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_VALIDATION_LOT', p_type_ressource: 'presence',
        p_id_ressource: user!.id, p_cle_s3: null,
        p_details: { type: 'validation_en_lot', nb_validees: nbValidees, ids_presences: ids },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: `✅ ${nbValidees} présences validées !` });
      charger();
    }
  };

  const ouvrirLitige = async (presenceId: string, missionId: string, soignantId: string, motif: string) => {
    if (!etablissementId || !motif.trim()) return;
    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: missionId,
      p_motif: motif.trim(),
    });
    if (error) {
      toast.error('Erreur lors de la création du litige.');
      return;
    }
    if (data?.error) { toast.error(data.error); return; }
    toast.success('Litige ouvert avec succès.');
    charger();
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  // Helpers pour rendu TableOuCartes
  const colonnesPresences: ColonneTableau<any>[] = [
    { cle: 'soignant', titre: 'Soignant' },
    { cle: 'mission', titre: 'Mission' },
    { cle: 'date', titre: 'Date' },
    { cle: 'heures', titre: 'Heures', align: 'right' },
    { cle: 'alertes', titre: 'Alertes' },
    { cle: 'actions', titre: '', align: 'right', largeur: 'w-32' },
  ];

  const calculHeures = (p: any): string => {
    if (!p.pointage_arrivee_le || !p.pointage_depart_le) return '—';
    const h = (new Date(p.pointage_depart_le).getTime() - new Date(p.pointage_arrivee_le).getTime()) / 3600000;
    return `${h.toFixed(1)}h`;
  };

  const renduCellulePresence = (p: any, col: ColonneTableau<any>) => {
    const sg = p.soignants;
    const nomComplet = sg ? `${sg.prenom} ${sg.nom}` : 'Soignant';
    switch (col.cle) {
      case 'soignant':
        return (
          <div>
            <p className="font-medium text-foreground">{nomComplet}</p>
            {sg?.profession && <p className="text-xs text-muted-foreground">{sg.profession}</p>}
          </div>
        );
      case 'mission':
        return <span className="text-sm text-muted-foreground line-clamp-1">{p.missions?.intitule || '—'}</span>;
      case 'date':
        return (
          <span className="text-xs whitespace-nowrap">
            {p.pointage_arrivee_le && new Date(p.pointage_arrivee_le).toLocaleDateString('fr-FR')}
          </span>
        );
      case 'heures':
        return <span className="text-sm tabular-nums">{calculHeures(p)}</span>;
      case 'alertes':
        return (
          <div className="flex flex-wrap gap-1">
            {p.alerte_teleportation && <BadgeY2K variant="error" size="sm">🚨 Téléport.</BadgeY2K>}
            {p.perimetre_gps_valide === false && <BadgeY2K variant="warning" size="sm">📍 Hors zone</BadgeY2K>}
            {(p.arrivee_mock_detected || p.depart_mock_detected) && <BadgeY2K variant="error" size="sm">🤖 GPS truqué</BadgeY2K>}
            {p.valide_par_etablissement && <BadgeY2K variant="success" size="sm">✅ Validée</BadgeY2K>}
            {!p.valide_par_etablissement && p.pointage_depart_le && !p.alerte_teleportation && p.perimetre_gps_valide && <BadgeY2K variant="info" size="sm" className="bg-muted text-muted-foreground border-muted">À valider</BadgeY2K>}
            {!p.pointage_depart_le && <BadgeY2K variant="info" size="sm">⏳ En cours</BadgeY2K>}
          </div>
        );
      case 'actions':
        if (!p.valide_par_etablissement && p.pointage_depart_le) {
          return (
            <BoutonY2K size="sm" variant="primary" className="h-8 text-xs" onClick={(e) => { e.stopPropagation(); validerUne(p.id); }} iconeGauche={<CheckCircle className="h-3.5 w-3.5" />}>
              Valider
            </BoutonY2K>
          );
        }
        return <span className="text-xs text-muted-foreground">—</span>;
      default:
        return null;
    }
  };

  const renduCartePresence = (p: any) => (
    <CarteValidation
      presence={p}
      litigeExistant={litiges[p.mission_id]}
      onValider={validerUne}
      onContester={contester}
      onOuvrirLitige={ouvrirLitige}
      onUpdate={charger}
    />
  );

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <ClipboardCheck className="h-5 w-5 text-primary" aria-hidden="true" /> Présences à valider
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Vérifiez et validez les pointages de vos soignants</p>
      </div>

      <Tabs
        value={activeTab}
        onValueChange={(value) => {
          setActiveTab(value);
          if (value === 'a_valider') setSearchParams({}, { replace: true });
          else setSearchParams({ tab: value }, { replace: true });
        }}
      >
        <TabsList className="w-full grid grid-cols-2 sm:grid-cols-4 mb-4">
          <TabsTrigger value="a_valider" className="text-xs min-h-[44px]" aria-label={`À valider: ${aValider.length} présences`}>
            À valider ({aValider.length})
          </TabsTrigger>
          <TabsTrigger value="en_cours" className="text-xs min-h-[44px]" aria-label={`En cours: ${enCours.length} présences`}>
            En cours ({enCours.length})
          </TabsTrigger>
          <TabsTrigger value="validees" className="text-xs min-h-[44px]" aria-label={`Validées: ${validees.length} présences`}>
            Validées ({validees.length})
          </TabsTrigger>
          <TabsTrigger value="alertes" className="text-xs min-h-[44px]" aria-label={`Alertes: ${alertes.length} présences`}>
            Alertes ({alertes.length})
          </TabsTrigger>
        </TabsList>

        <TabsContent value="a_valider">
          {aValider.length > 0 && (
            <div className="bg-card border border-border rounded-2xl p-4 mb-4">
              <p className="text-sm font-semibold text-foreground mb-2">{aValider.length} présences à valider</p>
              <button
                onClick={() => setModalLot(true)}
                disabled={presencesSansAlerte.length === 0}
                className="btn-primary text-sm flex items-center gap-2 disabled:opacity-50"
              >
                <CheckCircle className="h-4 w-4" /> Tout valider (sans alerte) · {presencesSansAlerte.length} présences
              </button>
              <p className="text-[11px] text-muted-foreground mt-2">
                Ce bouton valide uniquement les présences sans aucune alerte (géofence OK, pas de téléportation).
              </p>
            </div>
          )}
          <TableOuCartes
            colonnes={colonnesPresences}
            donnees={aValider}
            getId={(p: any) => p.id}
            etatVide={<EmptyState icone={<CheckCircle />} mascotte="happy" titre="Aucune présence à valider" description="Les pointages de vos soignants apparaîtront ici." variant="success" />}
            renduCellule={renduCellulePresence}
            renduCarte={renduCartePresence}
          />
        </TabsContent>

        <TabsContent value="en_cours">
          <TableOuCartes
            colonnes={colonnesPresences}
            donnees={enCours}
            getId={(p: any) => p.id}
            etatVide={<EmptyState icone={<Clock />} mascotte="empty" titre="Aucune mission en cours" description="Les soignants actuellement en mission apparaîtront ici." cta={{ label: 'Publier une mission', onClick: () => navigate('/etablissement/missions/creer') }} />}
            renduCellule={renduCellulePresence}
            renduCarte={renduCartePresence}
          />
        </TabsContent>

        <TabsContent value="validees">
          <TableOuCartes
            colonnes={colonnesPresences}
            donnees={validees}
            getId={(p: any) => p.id}
            etatVide={<EmptyState icone={<CheckCircle />} mascotte="empty" titre="Aucune présence validée" description="Les présences validées seront archivées ici." />}
            renduCellule={renduCellulePresence}
            renduCarte={renduCartePresence}
          />
        </TabsContent>

        <TabsContent value="alertes">
          <TableOuCartes
            colonnes={colonnesPresences}
            donnees={alertes}
            getId={(p: any) => p.id}
            etatVide={<EmptyState icone={<AlertTriangle />} mascotte="happy" titre="Aucune alerte" description="Les présences avec des alertes de fraude apparaîtront ici." variant="success" />}
            renduCellule={renduCellulePresence}
            renduCarte={renduCartePresence}
          />
        </TabsContent>
      </Tabs>

      <ModalConfirmation
        ouvert={modalLot}
        onFermer={() => setModalLot(false)}
        onConfirmer={validerEnLot}
        titre={`Valider ${presencesSansAlerte.length} présences ?`}
        message="Seules les présences sans alerte de fraude seront validées."
        labelConfirmer={`Valider ${presencesSansAlerte.length} présences`}
      />
    </LayoutApp>
  );
}
