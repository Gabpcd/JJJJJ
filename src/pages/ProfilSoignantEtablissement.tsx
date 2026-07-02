import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Briefcase, Phone, RotateCcw, ShieldAlert, ShieldCheck, Star } from 'lucide-react';
import { ModalRebook } from '@/components/dashboard/TopSoignants';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EtoilesNote } from '@/components/EtoilesNote';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { SignalerUtilisateur } from '@/components/SignalerUtilisateur';
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
  // 7e-2 (F2) : re-booking 2 taps depuis le profil (modal pré-remplie).
  const [rebookOpen, setRebookOpen] = useState(false);

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
                  <div className="flex items-start justify-between gap-3">
                    <h1 className="text-2xl font-bold text-foreground">{soignant.prenom} {soignant.nom}</h1>
                    <div className="flex items-center gap-2 shrink-0">
                      {/* 7e-2 (F2) : reproposer une mission = le chemin de moindre
                          résistance vs le SMS. Visible dès qu'une mission TERMINEE
                          commune existe (elle sert de modèle pré-rempli). */}
                      {missions.some(m => m.statut === 'TERMINEE') && (
                        <BoutonY2K size="sm" onClick={() => setRebookOpen(true)} iconeGauche={<RotateCcw className="h-4 w-4" />}>
                          Reproposer une mission
                        </BoutonY2K>
                      )}
                      <SignalerUtilisateur cibleId={soignant.id} cibleType="SOIGNANT" variant="bouton" />
                    </div>
                  </div>
                  {rebookOpen && (
                    <ModalRebook
                      soignant={{
                        id: soignant.id,
                        prenom: soignant.prenom,
                        nom: soignant.nom,
                        score_fiabilite: soignant.score_fiabilite ?? 0,
                        count: missions.length,
                        derniere_mission_id: missions.find(m => m.statut === 'TERMINEE')?.id ?? null,
                      }}
                      onClose={() => setRebookOpen(false)}
                    />
                  )}
                  <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                    <span className="inline-flex items-center gap-1"><Briefcase className="h-4 w-4 text-primary" /> {getLabelProfession(soignant.profession)}</span>
                    {soignant.type_exercice && (
                      <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${soignant.type_exercice === 'LIBERAL' ? 'bg-info/10 text-info' : soignant.type_exercice === 'MIXTE' ? 'bg-rose/10 text-rose' : 'bg-muted text-muted-foreground'}`}>
                        {soignant.type_exercice === 'MIXTE' ? 'Salarié + Libéral' : soignant.type_exercice === 'LIBERAL' ? 'Libéral' : 'Salarié'}
                      </span>
                    )}
                    {soignant.rpps_verifie && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-success/10 text-success px-2 py-0.5 text-xs font-semibold">
                        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
                        Vérifié
                      </span>
                    )}
                    <span className="inline-flex items-center gap-1"><Star className="h-4 w-4 text-primary" /> {soignant.score_fiabilite != null && soignant.total_missions_terminees >= 3 ? `${soignant.score_fiabilite}/100` : 'Pas encore d\'évaluation'}</span>
                    {soignant.note_moyenne != null && soignant.nb_evaluations > 0 && (
                      <span className="inline-flex items-center gap-1">⭐ {Number(soignant.note_moyenne).toFixed(1)}/5 ({soignant.nb_evaluations} avis)</span>
                    )}
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
                  <p className="text-muted-foreground">Type d'exercice</p>
                  <p className="font-medium text-foreground">{soignant.type_exercice === 'MIXTE' ? 'Salarié + Libéral' : soignant.type_exercice === 'LIBERAL' ? 'Libéral' : 'Salarié'}</p>
                </div>
                <div>
                  <p className="text-muted-foreground">RPPS</p>
                  <p className="font-medium text-foreground">{soignant.numero_rpps || '—'}</p>
                </div>
                <div>
                  <p className="text-muted-foreground">Vérification RPPS</p>
                  <div className="flex items-center gap-1.5">
                    {soignant.rpps_verifie ? (
                      <span className="inline-flex items-center gap-1 rounded-full bg-success/10 text-success px-2.5 py-1 text-xs font-semibold">
                        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
                        Vérifié
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 rounded-full bg-warning/10 text-warning px-2.5 py-1 text-xs font-semibold">
                        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" /></svg>
                        Non vérifié
                      </span>
                    )}
                  </div>
                </div>
                <div>
                  <p className="text-muted-foreground">Missions terminées</p>
                  <p className="font-medium text-foreground">{soignant.total_missions_terminees ?? 0}</p>
                </div>
                {soignant.annees_experience > 0 && (
                  <div>
                    <p className="text-muted-foreground">Années d'expérience</p>
                    <p className="font-medium text-foreground">{soignant.annees_experience} ans</p>
                  </div>
                )}
                {soignant.disponible_urgence && (
                  <div>
                    <p className="text-muted-foreground">Pool urgence</p>
                    <p className="font-medium text-success">🚨 Disponible</p>
                  </div>
                )}
              </div>
              {soignant.bio && (
                <div className="mt-4">
                  <p className="text-muted-foreground text-sm mb-1">Bio</p>
                  <p className="text-sm text-foreground">{soignant.bio}</p>
                </div>
              )}
              {soignant.specialites && (Array.isArray(soignant.specialites) ? soignant.specialites : []).length > 0 && (
                <div className="mt-3">
                  <p className="text-muted-foreground text-sm mb-1">Spécialités</p>
                  <div className="flex flex-wrap gap-1.5">
                    {(Array.isArray(soignant.specialites) ? soignant.specialites : []).map((s: string) => (
                      <span key={s} className="inline-flex items-center rounded-full bg-primary/10 text-primary px-2 py-0.5 text-xs font-medium">{s}</span>
                    ))}
                  </div>
                </div>
              )}
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
                  <span className="font-bold text-foreground">{soignant.score_fiabilite != null && soignant.total_missions_terminees >= 3 ? `${soignant.score_fiabilite}/100` : 'Pas encore d\'évaluation'}</span>
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
