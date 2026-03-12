import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { UserSearch, PlusCircle, Copy, XCircle, RotateCcw, Eye } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { BadgeStatut } from '@/components/BadgeStatut';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

function scoreColor(score: number): string {
  if (score >= 70) return 'text-success';
  if (score >= 40) return 'text-warning';
  return 'text-destructive';
}

function scoreLabel(score: number): string {
  if (score >= 70) return 'Fiable';
  if (score >= 40) return 'Moyen';
  return 'À surveiller';
}

export default function DetailMission() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [mission, setMission] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [modalAnnuler, setModalAnnuler] = useState(false);
  const [modalDupliquer, setModalDupliquer] = useState(false);

  useEffect(() => {
    if (!id) return;
    supabase
      .from('missions')
      .select(`
        *,
        etablissements(nom, adresse_ville, adresse_departement,
          taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
          taux_majoration_ferie_pourcent),
        soignants(prenom, nom, profession, telephone, email,
          score_fiabilite, total_missions_terminees, total_absences)
      `)
      .eq('id', id)
      .single()
      .then(({ data }) => {
        setMission(data);
        setLoading(false);
      });
  }, [id]);

  const handleAnnuler = async () => {
    const { error } = await supabase
      .from('missions')
      .update({ statut: 'ANNULEE_PAR_ETABLISSEMENT', modifie_le: new Date().toISOString() } as any)
      .eq('id', id!);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'MISSION_ANNULATION',
        p_type_ressource: 'mission', p_id_ressource: id!, p_cle_s3: null,
        p_details: { intitule: mission.intitule }, p_ip: null, p_navigateur: navigator.userAgent,
      });
      if (auditError) handleErrorSilent(auditError, 'Audit annulation mission');
      afficherNotification({ type: 'succes', message: 'Mission annulée.' });
      navigate('/etablissement/missions');
    }
  };

  if (loading || !mission) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  const m = mission;
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  const estAnnulee = m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT';

  return (
    <LayoutApp role="ETABLISSEMENT">
      <button onClick={() => navigate('/etablissement/missions')} className="text-sm text-primary hover:underline mb-4 inline-block">
        ← Retour aux missions
      </button>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Colonne gauche */}
        <div className="lg:col-span-2 space-y-4">
          {/* Informations */}
          <div className="card-base">
            <h1 className="text-2xl font-bold text-foreground mb-2">{m.intitule}</h1>
            <div className="flex items-center gap-2 flex-wrap mb-3">
              <BadgeStatut statut={m.statut} />
              {m.est_urgente && (
                <span className="badge-base bg-destructive/10 text-destructive text-[10px]">
                  {m.niveau_urgence === 3 ? '🚨 Critique' : m.niveau_urgence === 2 ? '🔥 Élevé' : '⚡ Urgent'}
                </span>
              )}
              {m.rist_plafond_applique && (
                <span className="badge-base bg-warning/10 text-warning text-[10px]">⚠️ Rist plafonné</span>
              )}
            </div>
            {m.description && <p className="text-sm text-muted-foreground mb-3">{m.description}</p>}
            <p className="text-sm text-muted-foreground">
              {getLabelProfession(m.profession_requise)}{m.service ? ` · ${m.service}` : ''}
            </p>
            <hr className="my-3 border-border" />
            <p className="text-sm text-foreground">📅 {format(debut, 'EEEE d MMMM yyyy', { locale: fr })}</p>
            <p className="text-sm text-foreground">🕐 {format(debut, 'HH:mm')} → {format(fin, 'HH:mm')} ({m.duree_heures?.toFixed(1)}h)</p>
          </div>

          {/* Soignant */}
          <div className="card-base">
            <h2 className="font-semibold text-foreground mb-3">Soignant assigné</h2>
            {m.soignants ? (
              <div className="space-y-2">
                <p className="font-semibold text-foreground">👤 {m.soignants.prenom} {m.soignants.nom}</p>
                <p className="text-sm text-muted-foreground">
                  {getLabelProfession(m.soignants.profession)} ·{' '}
                  <span className={`font-semibold ${scoreColor(m.soignants.score_fiabilite)}`}>
                    ⭐ {m.soignants.score_fiabilite}/100 ({scoreLabel(m.soignants.score_fiabilite)})
                  </span>
                </p>
                {m.soignants.telephone && <p className="text-sm text-muted-foreground">📱 {m.soignants.telephone}</p>}
                <p className="text-xs text-muted-foreground">
                  📊 {m.soignants.total_missions_terminees} missions terminées · {m.soignants.total_absences} absences
                </p>
              </div>
            ) : (
              <div className="text-center py-6">
                <UserSearch className="h-12 w-12 text-muted-foreground/30 mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">En attente d'un soignant</p>
                <p className="text-xs text-muted-foreground">Les soignants qualifiés voient cette mission et peuvent postuler.</p>
              </div>
            )}
          </div>

          {/* Vues (préparation) */}
          <div className="card-base flex items-center gap-2 text-sm text-muted-foreground">
            <Eye className="h-4 w-4" />
            <span>0 soignants ont vu cette mission</span>
          </div>

          {/* Historique */}
          <div className="card-base">
            <h2 className="font-semibold text-foreground mb-3">Historique</h2>
            <div className="space-y-3 text-sm">
              <div className="flex items-center gap-3">
                <PlusCircle className="h-4 w-4 text-primary flex-shrink-0" />
                <span className="text-muted-foreground">Créée le {format(new Date(m.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}</span>
              </div>
              {m.modifie_le && m.modifie_le !== m.cree_le && (
                <div className="flex items-center gap-3">
                  <PlusCircle className="h-4 w-4 text-info flex-shrink-0" />
                  <span className="text-muted-foreground">Modifiée le {format(new Date(m.modifie_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}</span>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Colonne droite */}
        <div>
          <DecompositionFinanciere mission={m} />
        </div>
      </div>

      {/* Actions sticky mobile */}
      <div className="fixed bottom-16 left-0 right-0 bg-card border-t border-border p-3 flex gap-3 md:static md:mt-6 md:border-0 md:p-0 md:justify-end z-30">
        {m.statut === 'OUVERTE' && (
          <button onClick={() => navigate(`/etablissement/missions/${m.id}/modifier`)} className="btn-secondary text-sm flex-1 md:flex-none">
            Modifier
          </button>
        )}
        <button onClick={() => setModalDupliquer(true)} className="text-sm font-medium text-muted-foreground hover:text-foreground flex items-center gap-1 px-3">
          <Copy className="h-4 w-4" /> Dupliquer
        </button>
        {(m.statut === 'OUVERTE' || m.statut === 'ASSIGNEE') && (
          <button onClick={() => setModalAnnuler(true)} className="btn-danger text-sm flex-1 md:flex-none">
            Annuler
          </button>
        )}
        {estAnnulee && (
          <button onClick={() => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)} className="btn-primary text-sm flex-1 md:flex-none flex items-center gap-1 justify-center">
            <RotateCcw className="h-4 w-4" /> Republier
          </button>
        )}
      </div>

      <ModalConfirmation
        ouvert={modalAnnuler}
        onFermer={() => setModalAnnuler(false)}
        onConfirmer={handleAnnuler}
        titre="Annuler cette mission ?"
        message={`La mission « ${m.intitule} » sera définitivement annulée.`}
        labelConfirmer="Annuler la mission"
        variante="danger"
      />

      <ModalConfirmation
        ouvert={modalDupliquer}
        onFermer={() => setModalDupliquer(false)}
        onConfirmer={() => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)}
        titre="Dupliquer cette mission ?"
        message={`Une copie de « ${m.intitule} » sera créée avec le statut OUVERTE.`}
        labelConfirmer="Dupliquer"
      />
    </LayoutApp>
  );
}
