import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Briefcase, Phone, ShieldAlert, ShieldCheck, Star } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

export default function ProfilSoignantEtablissement() {
  usePageTitle('Profil soignant');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { etablissementId } = useEtablissementScope();
  const [loading, setLoading] = useState(true);
  const [soignant, setSoignant] = useState<any>(null);
  const [noteMoyenne, setNoteMoyenne] = useState<{ moyenne: number; total: number } | null>(null);
  const [missions, setMissions] = useState<any[]>([]);

  useEffect(() => {
    if (!id || !etablissementId) return;

    const charger = async () => {
      setLoading(true);
      const [{ data: soignantData }, { data: noteData }, { data: missionsData }] = await Promise.all([
        supabase.rpc('fn_soignant_pour_etablissement' as any, { p_soignant_id: id }),
        supabase.rpc('fn_note_moyenne' as any, { p_user_id: id }),
        supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, statut, service')
          .eq('etablissement_id', etablissementId)
          .eq('soignant_assigne_id', id)
          .order('debut_le', { ascending: false })
          .limit(20),
      ]);

      if (soignantData && !(soignantData as any).error) {
        setSoignant(soignantData);
      } else {
        setSoignant(null);
      }

      if (noteData && typeof noteData === 'object' && !Array.isArray(noteData)) {
        setNoteMoyenne(noteData as { moyenne: number; total: number });
      } else if (Array.isArray(noteData) && noteData[0]) {
        setNoteMoyenne(noteData[0]);
      } else {
        setNoteMoyenne(null);
      }

      setMissions(missionsData || []);

      setLoading(false);
    };

    charger();
  }, [id, etablissementId]);

  const initiales = useMemo(() => {
    if (!soignant) return 'SD';
    return `${soignant.prenom?.[0] ?? ''}${soignant.nom?.[0] ?? ''}`.toUpperCase() || 'SD';
  }, [soignant]);

  if (loading) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <ChargementPage />
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      {!soignant ? (
        <div className="card-base text-center py-10">
          <p className="text-sm text-muted-foreground">Profil soignant indisponible.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-4">
            <div className="card-base">
              <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                {soignant.avatar_url ? (
                  <img
                    src={soignant.avatar_url}
                    alt={`Photo de ${soignant.prenom} ${soignant.nom}`}
                    className="h-20 w-20 rounded-2xl object-cover border border-border"
                  />
                ) : (
                  <div className="h-20 w-20 rounded-2xl border border-border bg-muted flex items-center justify-center text-xl font-bold text-foreground">
                    {initiales}
                  </div>
                )}

                <div className="space-y-2">
                  <h1 className="text-2xl font-bold text-foreground">{soignant.prenom} {soignant.nom}</h1>
                  <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                    <span className="inline-flex items-center gap-1"><Briefcase className="h-4 w-4 text-primary" /> {getLabelProfession(soignant.profession)}</span>
                    <span className="inline-flex items-center gap-1"><Star className="h-4 w-4 text-primary" /> {soignant.score_fiabilite ?? 0}/100</span>
                  </div>
                </div>
              </div>
            </div>

            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-3">Informations professionnelles</h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                <div>
                  <p className="text-muted-foreground">Profession</p>
                  <p className="font-medium text-foreground">{getLabelProfession(soignant.profession)}</p>
                </div>
                <div>
                  <p className="text-muted-foreground">RPPS</p>
                  <p className="font-medium text-foreground">{soignant.numero_rpps || '—'}</p>
                </div>
                <div>
                  <p className="text-muted-foreground">Vérification RPPS</p>
                  <p className="font-medium text-foreground">{soignant.rpps_verifie ? 'Vérifié' : 'Non vérifié'}</p>
                </div>
                <div>
                  <p className="text-muted-foreground">Missions terminées</p>
                  <p className="font-medium text-foreground">{soignant.total_missions_terminees ?? 0}</p>
                </div>
              </div>
            </div>

            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-3">Missions avec votre établissement</h2>
              {missions.length > 0 ? (
                <div className="space-y-2">
                  {missions.map((mission) => (
                    <button
                      key={mission.id}
                      type="button"
                      onClick={() => navigate(`/etablissement/missions/${mission.id}`)}
                      className="w-full rounded-xl border border-border p-3 text-left transition-colors hover:bg-muted/30"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-medium text-foreground">{mission.intitule}</p>
                          <p className="text-xs text-muted-foreground mt-1">
                            {mission.service || 'Service non renseigné'} · {new Date(mission.debut_le).toLocaleDateString('fr-FR')} 
                          </p>
                        </div>
                        <span className="text-xs font-medium text-primary">Voir la mission →</span>
                      </div>
                    </button>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">Aucune mission partagée avec votre établissement pour le moment.</p>
              )}
            </div>
          </div>

          <div className="space-y-4">
            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-3">Fiabilité</h2>
              <div className="space-y-3 text-sm">
                <div className="flex items-center justify-between gap-3">
                  <span className="text-muted-foreground">Score de fiabilité</span>
                  <span className="font-bold text-foreground">{soignant.score_fiabilite ?? 0}/100</span>
                </div>
                <div className="flex items-center justify-between gap-3">
                  <span className="text-muted-foreground">Évaluations</span>
                  <span className="font-medium text-foreground">
                    {noteMoyenne && noteMoyenne.total > 0 ? `${noteMoyenne.moyenne.toFixed(1)}/5 (${noteMoyenne.total})` : 'Pas encore d’évaluation'}
                  </span>
                </div>
              </div>
            </div>

            <div className="card-base">
              <h2 className="font-semibold text-foreground mb-3">Conformité</h2>
              <div className="space-y-3 text-sm">
                <div className="flex items-center justify-between gap-3">
                  <span className="text-muted-foreground">Documents</span>
                  <span className="inline-flex items-center gap-1 font-medium text-foreground">
                    {soignant.tous_documents_valides ? <ShieldCheck className="h-4 w-4 text-success" /> : <ShieldAlert className="h-4 w-4 text-warning" />}
                    {soignant.tous_documents_valides ? 'Complets' : 'À compléter'}
                  </span>
                </div>
                <div className="flex items-center justify-between gap-3">
                  <span className="text-muted-foreground">Téléphone</span>
                  <span className="font-medium text-foreground">{soignant.telephone || 'Visible le jour J uniquement'}</span>
                </div>
              </div>
            </div>

            {soignant.telephone && (
              <a href={`tel:${soignant.telephone}`} className="btn-secondary w-full inline-flex items-center justify-center gap-2 text-sm">
                <Phone className="h-4 w-4" /> Appeler le soignant
              </a>
            )}
          </div>
        </div>
      )}
    </LayoutApp>
  );
}
