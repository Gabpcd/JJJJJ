import { usePageTitle } from '@/hooks/usePageTitle';
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { JaugeScoreFiabilite } from '@/components/JaugeScoreFiabilite';
import { DecompositionScore } from '@/components/DecompositionScore';
import { ConseilsScore } from '@/components/ConseilsScore';
import { BadgeNiveau } from '@/components/BadgeNiveau';
import { ModalReclamationScore } from '@/components/ModalReclamationScore';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { handleErrorSilent } from '@/lib/handleError';
import { AlertTriangle, ArrowLeft } from 'lucide-react';

export default function FiabiliteSoignant() {
  usePageTitle('Score de Fiabilité');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [soignant, setSoignant] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [showReclamation, setShowReclamation] = useState(false);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('score_fiabilite, total_missions_terminees, total_missions_annulees, total_absences, total_retards_pointage')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => {
        setSoignant(data); setLoading(false);
        supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'soignant', p_id_ressource: user.id,
          p_cle_s3: null, p_details: { page: 'fiabilite' },
          p_ip: null, p_navigateur: navigator.userAgent,
        }).then(undefined, (err) => handleErrorSilent(err, 'FiabiliteSoignant.audit'));
      });
  }, [user]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const totalMissions = soignant.total_missions_terminees ?? 0;
  const score = soignant.score_fiabilite ?? 50;
  const scoreActif = totalMissions >= 3;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
          <ArrowLeft className="h-4 w-4" /> Retour
        </button>
        <h1 className="text-xl font-bold text-foreground">⭐ Score de fiabilité</h1>
        {scoreActif ? (
          <div className="mt-2"><BadgeNiveau score={score} /></div>
        ) : (
          <div className="mt-2 inline-flex items-center gap-1 rounded-full bg-muted text-muted-foreground px-3 py-1 text-xs font-medium">
            Pas encore d'évaluation · disponible après 3 missions terminées
          </div>
        )}
      </div>

      {scoreActif ? (
        <div className="mb-6">
          <JaugeScoreFiabilite score={score} />
        </div>
      ) : (
        <div className="card-base mb-6 text-center py-8">
          <p className="text-sm font-medium text-foreground">
            Votre score sera disponible après {Math.max(0, 3 - totalMissions)} mission{Math.max(0, 3 - totalMissions) > 1 ? 's' : ''} terminée{Math.max(0, 3 - totalMissions) > 1 ? 's' : ''} de plus.
          </p>
          <p className="text-xs text-muted-foreground mt-2">
            En attendant, votre profil reste visible aux établissements avec la mention « Pas encore d'évaluation ».
          </p>
        </div>
      )}

      <div className="space-y-4">
        <DecompositionScore soignant={soignant} />
        <ConseilsScore soignant={soignant} />

        {/* Contest button */}
        <div className="card-base">
          <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-warning" /> Vous pensez qu'une pénalité est injuste ?
          </h3>
          <p className="text-xs text-muted-foreground mb-3">
            Si votre score a baissé suite à un arrêt maladie, un accident ou une erreur, vous pouvez contester.
          </p>
          <button
            onClick={() => setShowReclamation(true)}
            className="btn-secondary text-sm py-2 px-4"
          >
            ⚖️ Contester une pénalité
          </button>
        </div>
      </div>

      {showReclamation && (
        <ModalReclamationScore
          onClose={() => setShowReclamation(false)}
          onSuccess={() => {
            setShowReclamation(false);
            afficherNotification({ type: 'succes', message: 'Réclamation envoyée. Un administrateur l\'examinera sous 72h.' });
          }}
        />
      )}
    </LayoutApp>
  );
}
