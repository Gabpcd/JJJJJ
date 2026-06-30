import React, { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { handleErrorSilent } from '@/lib/handleError';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Copy, Gift, CheckCircle, LogOut } from 'lucide-react';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { EncartInvitation } from '@/components/EncartInvitation';
import { BadgesGamification, BadgeStats } from '@/components/BadgesGamification';
import { AvatarUpload } from '@/components/AvatarUpload';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getLabelProfession, getTypesContratSoignant } from '@/lib/constantes';
import { calculerCompletionProfil } from '@/lib/profil-soignant';
import type { Database } from '@/integrations/supabase/types';
import { SectionProfilPrincipal } from '@/components/profil-soignant/SectionProfilPrincipal';
import { SectionPaiements } from '@/components/profil-soignant/SectionPaiements';
import { SectionPreferences } from '@/components/profil-soignant/SectionPreferences';
import { SectionConfidentialite } from '@/components/profil-soignant/SectionConfidentialite';
import { SectionDpaeIdentite } from '@/components/profil-soignant/SectionDpaeIdentite';

type SoignantRow = Database['public']['Tables']['soignants']['Row'];

export default function ProfilSoignant() {
  usePageTitle('Profil');
  const { user, deconnexion } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [deconnexionEnCours, setDeconnexionEnCours] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  // Soignant raw row (for completion helper)
  const [soignantRow, setSoignantRow] = useState<SoignantRow | null>(null);

  // Page-level state
  const [email, setEmail] = useState('');
  const [profession, setProfession] = useState('');
  const [specialiteMedicale, setSpecialiteMedicale] = useState('');
  const [specialiteVerifiee, setSpecialiteVerifiee] = useState(false);
  const [specialiteSource, setSpecialiteSource] = useState<string>('MANUEL');
  const [rppsVerifie, setRppsVerifie] = useState(false);
  const [rppsVerifieLe, setRppsVerifieLe] = useState<string | null>(null);
  const [mandatFacturationSigne, setMandatFacturationSigne] = useState(false);
  const [mandatFacturationSigneLe, setMandatFacturationSigneLe] = useState<string | null>(null);

  // Form fields
  const [prenom, setPrenom] = useState('');
  const [nom, setNom] = useState('');
  const [telephone, setTelephone] = useState('');
  const [dateNaissance, setDateNaissance] = useState('');
  const [rpps, setRpps] = useState('');
  const [lat, setLat] = useState('');
  const [lng, setLng] = useState('');
  const [rayon, setRayon] = useState(30);
  const [bio, setBio] = useState('');
  const [anneesExperience, setAnneesExperience] = useState(0);
  const [avatarUrl, setAvatarUrl] = useState('');
  const [tauxHoraireMinimum, setTauxHoraireMinimum] = useState<number | null>(null);
  const [villeRecherche, setVilleRecherche] = useState('');
  const [specialites, setSpecialites] = useState<string[]>([]);
  const [typesContrat, setTypesContrat] = useState<string[]>(['CDD']);
  const [consentementGPS, setConsentementGPS] = useState(true);
  const [gpsToggling, setGpsToggling] = useState(false);
  const [consentementSMS, setConsentementSMS] = useState(false);
  const [smsToggling, setSmsToggling] = useState(false);
  const [poolUrgenceActif, setPoolUrgenceActif] = useState(false);
  const [poolUrgenceRayon, setPoolUrgenceRayon] = useState(15);
  const [typeExercice, setTypeExercice] = useState('SALARIE');
  const [attestationCumul, setAttestationCumul] = useState(false);
  const [heuresCumulees, setHeuresCumulees] = useState(0);
  const [statutLiberal, setStatutLiberal] = useState('');
  const [codeParrainage, setCodeParrainage] = useState('');
  const [codeRecu, setCodeRecu] = useState(() => {
    // J5.D.1 — auto-fill depuis ?ref=CODE (URL inscription) ou sessionStorage
    try {
      const urlParam = new URLSearchParams(window.location.search).get('ref');
      if (urlParam) {
        sessionStorage.setItem('jolene.parrainage_code', urlParam.toUpperCase());
        return urlParam.toUpperCase();
      }
      const stored = sessionStorage.getItem('jolene.parrainage_code');
      return stored ?? '';
    } catch {
      return '';
    }
  });
  const [parrainageLoading, setParrainageLoading] = useState(false);
  const [parrainageSucces, setParrainageSucces] = useState(false);
  const [filleuls, setFilleuls] = useState<any[]>([]);
  const [codeCopied, setCodeCopied] = useState(false);

  // Évaluations / badges
  const [noteMoyenne, setNoteMoyenne] = useState<{ moyenne: number; total: number } | null>(null);
  const [evaluations, setEvaluations] = useState<any[]>([]);
  const [badgeStats, setBadgeStats] = useState<BadgeStats | null>(null);

  const refresh = useCallback(() => setRefreshKey((k) => k + 1), []);

  useEffect(() => {
    if (!user) return;
    setLoading(true);
    supabase.rpc('fn_mon_profil_soignant_complet' as any).then(({ data, error }: any) => {
      if (error) {
        afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
        setLoading(false);
        return;
      }
      if (data) {
        supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'soignant', p_id_ressource: user.id,
          p_cle_s3: null, p_details: { page: 'profil' },
          p_ip: null, p_navigateur: navigator.userAgent,
        }).then(undefined, (err) => handleErrorSilent(err, 'ProfilSoignant.audit'));

        setEmail(data.email || '');
        setProfession(data.profession || '');
        setSpecialiteMedicale(data.specialite_medicale || '');
        setSpecialiteVerifiee(!!data.specialite_verifiee);
        setSpecialiteSource(data.specialite_source || 'MANUEL');
        setRppsVerifie(!!data.rpps_verifie);
        setRppsVerifieLe(data.rpps_verifie_le || null);
        setMandatFacturationSigne(!!data.mandat_facturation_signe);
        setMandatFacturationSigneLe(data.mandat_facturation_signe_le || null);
        setHeuresCumulees(data.heures_cumulees || 0);
        setStatutLiberal(data.statut_liberal || '');
        setTypeExercice(data.type_exercice || 'SALARIE');
        setAttestationCumul(data.attestation_cumul_activite || false);
        setCodeParrainage(data.code_parrainage || '');

        setPrenom(data.prenom || '');
        setNom(data.nom || '');
        setTelephone(data.telephone || '');
        setDateNaissance(data.date_naissance || '');
        setRpps(data.numero_rpps || '');
        setLat(data.adresse_lat?.toString() || '');
        setLng(data.adresse_lng?.toString() || '');
        setRayon(data.rayon_deplacement_km ?? 30);
        setBio(data.bio || '');
        setAnneesExperience(data.annees_experience || 0);
        setAvatarUrl(data.avatar_url || '');
        setTauxHoraireMinimum(data.taux_horaire_minimum ?? null);
        setVilleRecherche(data.ville_recherche || '');
        setSpecialites(Array.isArray(data.specialites) ? data.specialites : (data.specialites ? JSON.parse(data.specialites) : []));
        setTypesContrat(getTypesContratSoignant(data));
        setConsentementGPS(data.consentement_gps !== false);
        setConsentementSMS(data.sms_actif === true);
        setPoolUrgenceActif(data.disponible_urgence || false);
        setPoolUrgenceRayon(data.urgence_rayon_km || 15);

        setSoignantRow(data as SoignantRow);
      }
      setLoading(false);
    });

    supabase.rpc('fn_mes_filleuls' as any).then(({ data }: any) => {
      if (Array.isArray(data)) setFilleuls(data);
    }).then(undefined, (err) => handleErrorSilent(err, 'ProfilSoignant.filleuls'));

    supabase.rpc('fn_note_moyenne' as any, { p_user_id: user.id })
      .then(({ data }: any) => {
        if (Array.isArray(data) && data.length > 0) setNoteMoyenne(data[0]);
        else if (data && typeof data === 'object' && !Array.isArray(data) && 'total' in data) setNoteMoyenne(data);
      }).then(undefined, (err) => handleErrorSilent(err, 'ProfilSoignant.noteMoyenne'));
    supabase.rpc('fn_mes_evaluations_recues' as any)
      .then(({ data }: any) => {
        if (Array.isArray(data)) setEvaluations(data);
      }).then(undefined, (err) => handleErrorSilent(err, 'ProfilSoignant.evaluations'));
    supabase.rpc('fn_badge_stats' as any).then(({ data }: any) => {
      if (data) {
        setBadgeStats({
          missionsTerminees: data.total_missions ?? data.missionsTerminees ?? 0,
          scoreFiabilite: data.score_fiabilite ?? data.scoreFiabilite ?? 0,
          heuresCumulees: data.heures_cumulees ?? data.heuresCumulees ?? 0,
          annulations: data.annulations ?? 0,
          missionsNuit: data.missions_nuit ?? data.missionsNuit ?? 0,
          missionsWeekend: data.missions_weekend ?? data.missionsWeekend ?? 0,
          maxMissionsMemeEtab: data.max_missions_meme_etab ?? data.maxMissionsMemeEtab ?? 0,
          retards: data.retards ?? 0,
          totalMissions: data.total_missions ?? data.missionsTerminees ?? 0,
        });
      }
    }).then(undefined, (err) => handleErrorSilent(err, 'ProfilSoignant.badgeStats'));
  }, [user, refreshKey, afficherNotification]);

  const toggleContrat = (valeur: string) => {
    setTypesContrat((prev) => {
      if (prev.includes(valeur)) {
        if (prev.length <= 1) return prev;
        return prev.filter((v) => v !== valeur);
      }
      return [...prev, valeur];
    });
  };

  const handleSave = async () => {
    if (!user) return;
    if (!anneesExperience && anneesExperience !== 0) {
      afficherNotification({ type: 'erreur', message: 'Le nombre d\'années d\'expérience est obligatoire.' });
      return;
    }
    if ((typeExercice === 'MIXTE' || typeExercice === 'LIBERAL') && !attestationCumul) {
      afficherNotification({ type: 'erreur', message: 'Vous devez attester la conformité de votre cumul d\'activités (article L1222-5).' });
      return;
    }
    setSaving(true);
    const { data: rpcResult, error } = await supabase.rpc('fn_modifier_mon_profil' as any, {
      p_telephone: telephone || null,
      p_adresse_rue: null, p_adresse_ville: null, p_adresse_code_postal: null,
      p_rayon_deplacement_km: rayon,
      p_prenom: prenom || null, p_nom: nom || null,
      p_date_naissance: dateNaissance || null,
      p_types_contrat: typesContrat,
      p_numero_rpps: rpps || null,
      p_adresse_lat: lat ? parseFloat(lat) : null,
      p_adresse_lng: lng ? parseFloat(lng) : null,
      p_bio: bio || null,
      p_annees_experience: anneesExperience,
      p_specialites: specialites,
      p_ville_recherche: villeRecherche || null,
    });

    const { error: exError } = await supabase.rpc('fn_modifier_mon_profil' as any, {
      p_type_exercice: typeExercice,
      p_attestation_cumul_activite: attestationCumul,
      p_taux_horaire_minimum: tauxHoraireMinimum,
    });

    let specialiteError: any = null;
    if ((profession === 'MEDECIN' || profession === 'IDE') && !specialiteVerifiee) {
      const { error: specErr } = await supabase.from('soignants')
        .update({ specialite_medicale: specialiteMedicale || null, specialite_code: specialiteMedicale || null, specialite_source: 'MANUEL' } as any)
        .eq('id', user.id);
      specialiteError = specErr;
    }

    if (error || exError || specialiteError) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error || exError || specialiteError) });
    } else if ((rpcResult as any)?.error) {
      afficherNotification({ type: 'erreur', message: (rpcResult as any).error });
    } else {
      afficherNotification({ type: 'succes', message: 'Profil mis à jour avec succès !' });
      refresh();
    }
    setSaving(false);
  };

  const resumeCompletion = calculerCompletionProfil(soignantRow);

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const profilComplet = resumeCompletion.peut_candidater;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="flex items-center gap-4 mb-6">
        <AvatarUpload
          src={avatarUrl}
          prenom={prenom}
          nom={nom}
          size={96}
          mode="soignant"
          onUploaded={(url) => setAvatarUrl(url)}
        />
        <div>
          <h1 className="text-xl font-bold text-foreground">{prenom} {nom}</h1>
          <div className="flex items-center gap-2 mt-1">
            <span className="text-sm text-muted-foreground">{getLabelProfession(profession)}</span>
            <BadgeRPPS rppsVerifie={rppsVerifie} rpps={rpps} profession={profession} />
          </div>
        </div>
      </div>

      {!profilComplet && (
        <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4 mb-6 flex items-start gap-3">
          <span className="text-xl shrink-0">🎯</span>
          <div>
            <p className="font-semibold text-foreground">Complète ton profil pour postuler</p>
            <p className="text-sm text-muted-foreground">Renseigne les champs ci-dessous — 2 minutes suffisent. (Tes documents, eux, débloquent l'acceptation par les établissements.)</p>
          </div>
        </div>
      )}

      {profilComplet && noteMoyenne && noteMoyenne.total > 0 && (
        <div className="card-base mb-6">
          <h2 className="text-base font-semibold text-foreground mb-2">Évaluations reçues</h2>
          <p className="text-lg font-bold text-foreground">⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}</p>
          {evaluations.length > 0 && (
            <div className="mt-3 space-y-2">
              {evaluations.slice(0, 5).map((ev: any, i: number) => (
                <div key={i} className="text-sm text-muted-foreground border-t border-border pt-2">
                  <span className="text-foreground font-medium">⭐ {ev.note}/5</span>
                  {ev.mission_intitule && <span className="ml-1">— {ev.mission_intitule}</span>}
                  {ev.cree_le && <span className="ml-1">— {format(new Date(ev.cree_le), 'd MMM yyyy', { locale: fr })}</span>}
                  {ev.type_evaluateur && <span className="ml-1">— par {ev.type_evaluateur === 'ETABLISSEMENT' ? 'l\'établissement' : 'le soignant'}</span>}
                  {ev.commentaire && <p className="text-xs mt-0.5 italic">{ev.commentaire}</p>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {profilComplet && badgeStats && (
        <div className="max-w-2xl mb-6">
          <BadgesGamification stats={badgeStats} />
        </div>
      )}

      <div className="max-w-2xl">
        <Tabs defaultValue="principal" className="w-full">
          <div className="overflow-x-auto -mx-1 px-1 mb-4">
            <TabsList className="w-max">
              <TabsTrigger value="principal">Profil principal</TabsTrigger>
              <TabsTrigger value="paiements">Paiements</TabsTrigger>
              <TabsTrigger value="preferences">Préférences</TabsTrigger>
              <TabsTrigger value="confidentialite">Confidentialité</TabsTrigger>
            </TabsList>
          </div>

          <TabsContent value="principal">
            <SectionProfilPrincipal
              userId={user!.id}
              email={email}
              rppsVerifie={rppsVerifie}
              rppsVerifieLe={rppsVerifieLe}
              rpps={rpps}
              setRpps={setRpps}
              prenom={prenom}
              setPrenom={setPrenom}
              nom={nom}
              setNom={setNom}
              dateNaissance={dateNaissance}
              setDateNaissance={setDateNaissance}
              telephone={telephone}
              setTelephone={setTelephone}
              profession={profession}
              specialiteMedicale={specialiteMedicale}
              setSpecialiteMedicale={setSpecialiteMedicale}
              specialiteVerifiee={specialiteVerifiee}
              specialiteSource={specialiteSource}
              lat={lat}
              setLat={setLat}
              lng={lng}
              setLng={setLng}
              rayon={rayon}
              villeRecherche={villeRecherche}
              setVilleRecherche={setVilleRecherche}
              typeExercice={typeExercice}
              setTypeExercice={setTypeExercice}
              attestationCumul={attestationCumul}
              setAttestationCumul={setAttestationCumul}
              statutLiberal={statutLiberal}
              heuresCumulees={heuresCumulees}
              tousDocumentsValides={!!soignantRow?.tous_documents_valides}
              resumeCompletion={resumeCompletion}
              onRefresh={refresh}
              onSave={handleSave}
              saving={saving}
            />
            <div className="mt-4">
              <SectionDpaeIdentite soignantId={user!.id} typeExercice={typeExercice} />
            </div>
          </TabsContent>

          <TabsContent value="paiements">
            <SectionPaiements
              userId={user!.id}
              typeExercice={typeExercice}
              mandatFacturationSigne={mandatFacturationSigne}
              mandatFacturationSigneLe={mandatFacturationSigneLe}
            />
          </TabsContent>

          <TabsContent value="preferences">
            <SectionPreferences
              userId={user!.id}
              bio={bio}
              onBioChange={setBio}
              anneesExperience={anneesExperience}
              onAnneesChange={setAnneesExperience}
              specialites={specialites}
              onSpecialitesChange={setSpecialites}
              typesContrat={typesContrat}
              onToggleContrat={toggleContrat}
              rayon={rayon}
              onRayonChange={setRayon}
              tauxHoraireMinimum={tauxHoraireMinimum}
              onTauxChange={setTauxHoraireMinimum}
              poolUrgenceActif={poolUrgenceActif}
              poolUrgenceRayon={poolUrgenceRayon}
              onPoolUrgenceUpdate={(a, r) => { setPoolUrgenceActif(a); setPoolUrgenceRayon(r); }}
              consentementGPS={consentementGPS}
              onConsentementGPSChange={setConsentementGPS}
              gpsToggling={gpsToggling}
              setGpsToggling={setGpsToggling}
              consentementSMS={consentementSMS}
              onConsentementSMSChange={setConsentementSMS}
              smsToggling={smsToggling}
              setSmsToggling={setSmsToggling}
            />
            <BlocStatutEtudiant userId={user!.id} />
            <div className="mt-4 flex justify-end">
              <button
                type="button"
                onClick={handleSave}
                disabled={saving}
                className="btn-primary disabled:opacity-50"
              >
                {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
              </button>
            </div>
          </TabsContent>

          <TabsContent value="confidentialite">
            <SectionConfidentialite userId={user!.id} />
          </TabsContent>
        </Tabs>
      </div>

      {/* Inviter des collègues */}
      {codeParrainage && (
        <div className="max-w-2xl mt-8">
          <EncartInvitation codeParrainage={codeParrainage} />
        </div>
      )}

      {/* Parrainage */}
      <div className="max-w-2xl mt-8">
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
            <Gift className="h-5 w-5 text-primary" /> Parrainage
          </h2>

          {codeParrainage && (
            <div className="mb-4">
              <p className="text-sm text-muted-foreground mb-2">Votre code parrainage :</p>
              <div className="flex items-center gap-2">
                <code className="bg-muted px-4 py-2 rounded-xl font-mono text-lg font-bold text-foreground">{codeParrainage}</code>
                <button
                  onClick={() => {
                    navigator.clipboard.writeText(codeParrainage);
                    setCodeCopied(true);
                    setTimeout(() => setCodeCopied(false), 2000);
                  }}
                  className="btn-secondary text-xs py-2 px-3 flex items-center gap-1"
                >
                  {codeCopied ? <><CheckCircle className="h-3.5 w-3.5" /> Copié !</> : <><Copy className="h-3.5 w-3.5" /> Copier</>}
                </button>
              </div>
              <p className="text-xs text-muted-foreground mt-2">Parrainez 3 collègues pour obtenir le badge Ambassadeur et un accès prioritaire aux missions urgentes.</p>
            </div>
          )}

          <div className="border-t border-border pt-4">
            <p className="text-sm text-muted-foreground mb-2">Vous avez un code parrainage ?</p>
            <div className="flex gap-2">
              <input
                aria-label="Code de parrainage"
                value={codeRecu}
                onChange={(e) => setCodeRecu(e.target.value.toUpperCase())}
                placeholder="Ex: JO-5B4945"
                className="input-base flex-1"
                disabled={parrainageSucces}
              />
              <button
                onClick={async () => {
                  if (!codeRecu.trim()) return;
                  setParrainageLoading(true);
                  const { data, error } = await supabase.rpc('fn_appliquer_parrainage' as any, { p_code: codeRecu.trim() });
                  if (error) {
                    afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
                  } else if ((data as any)?.error) {
                    afficherNotification({ type: 'erreur', message: (data as any).error });
                  } else {
                    setParrainageSucces(true);
                    afficherNotification({ type: 'succes', message: 'Parrainage enregistré ! 🎉' });
                  }
                  setParrainageLoading(false);
                }}
                disabled={parrainageLoading || parrainageSucces || !codeRecu.trim()}
                className="btn-primary text-sm disabled:opacity-50"
              >
                {parrainageLoading ? '…' : parrainageSucces ? '✓ Appliqué' : 'Appliquer'}
              </button>
            </div>
            {parrainageSucces && (
              <p className="text-sm text-success font-semibold mt-2">🎉 Parrainage enregistré avec succès !</p>
            )}
          </div>

          {filleuls.length > 0 && (
            <div className="border-t border-border pt-4 mt-4">
              <p className="text-sm font-medium text-foreground mb-2">Vos filleuls ({filleuls.length})</p>
              <div className="space-y-1">
                {filleuls.map((f: any, i: number) => (
                  <div key={i} className="text-sm text-muted-foreground flex items-center gap-2">
                    <CheckCircle className="h-3.5 w-3.5 text-success" />
                    {f.prenom} {f.nom} — inscrit le {f.cree_le ? format(new Date(f.cree_le), 'd MMM yyyy', { locale: fr }) : '—'}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Déconnexion mobile */}
      <div className="md:hidden mt-6 pt-6 border-t border-border max-w-2xl">
        <button
          disabled={deconnexionEnCours}
          onClick={async () => { setDeconnexionEnCours(true); try { await deconnexion(); navigate('/'); } catch { setDeconnexionEnCours(false); } }}
          className="btn-secondary w-full flex items-center justify-center gap-2 text-destructive border-destructive/30 hover:bg-destructive/5 disabled:opacity-50"
        >
          <LogOut className="h-4 w-4" /> {deconnexionEnCours ? 'Déconnexion…' : 'Se déconnecter'}
        </button>
      </div>
    </LayoutApp>
  );
}


/* ── Statut étudiant en santé (exercice « faisant fonction », arrêté du 03/02/2022).
   Autodéclaré + niveau VÉRIFIÉ par l'IA via l'attestation de scolarité
   (type ATTESTATION_SCOLARITE) → profession autorisée calculée par la table
   d'équivalence. Affiché aux établissements (badge 🎓 sur les candidatures). ── */
function BlocStatutEtudiant({ userId }: { userId: string }) {
  const navigate = useNavigate();
  const [estEtudiant, setEstEtudiant] = useState(false);
  const [details, setDetails] = useState('');
  const [scol, setScol] = useState<{ verifiee: boolean; annee: number | null; profession: string | null } | null>(null);
  const [charge, setCharge] = useState(false);

  useEffect(() => {
    (supabase.from('soignants') as any)
      .select('est_etudiant, etudiant_details, scolarite_verifiee, scolarite_annee_validee, scolarite_profession_autorisee')
      .eq('id', userId).maybeSingle()
      .then(({ data }: { data: any }) => {
        if (data) {
          setEstEtudiant(!!data.est_etudiant);
          setDetails(data.etudiant_details || '');
          setScol({
            verifiee: !!data.scolarite_verifiee,
            annee: data.scolarite_annee_validee ?? null,
            profession: data.scolarite_profession_autorisee ?? null,
          });
        }
        setCharge(true);
      });
  }, [userId]);

  const sauver = async (actif: boolean, det: string) => {
    const { error } = await supabase.from('soignants')
      .update({ est_etudiant: actif, etudiant_details: det.trim() || null } as any)
      .eq('id', userId);
    if (error) toast.error(error.message);
  };

  if (!charge) return null;
  return (
    <div className="card-base mt-4 space-y-2">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-semibold text-foreground">🎓 Je suis étudiant(e) en santé</p>
          <p className="text-xs text-muted-foreground">
            Visible par les établissements. Un étudiant peut exercer « faisant fonction » selon
            son niveau (ex : étudiant infirmier ayant validé l'année 1 → aide-soignant, arrêté du 03/02/2022).
          </p>
        </div>
        <button type="button"
          onClick={() => { const v = !estEtudiant; setEstEtudiant(v); sauver(v, details); }}
          className={`relative w-12 h-6 rounded-full transition-colors shrink-0 ${estEtudiant ? 'bg-primary' : 'bg-muted'}`}>
          <span className={`absolute top-0.5 w-5 h-5 rounded-full bg-card shadow transition-transform ${estEtudiant ? 'translate-x-6' : 'translate-x-0.5'}`} />
        </button>
      </div>

      {estEtudiant && scol?.verifiee && scol.profession && (
        <div className="rounded-lg border border-emerald-200 bg-emerald-50 dark:bg-emerald-950/20 dark:border-emerald-800 p-2.5">
          <p className="text-xs font-semibold text-emerald-800 dark:text-emerald-300">
            ✅ Niveau vérifié{scol.annee ? ` (année ${scol.annee} validée)` : ''} — vous pouvez exercer comme {getLabelProfession(scol.profession)}
          </p>
          <p className="text-[11px] text-emerald-700/80 dark:text-emerald-400/80 mt-0.5">
            Vérifié par l'IA à partir de votre attestation de scolarité.
          </p>
        </div>
      )}

      {estEtudiant && !scol?.verifiee && (
        <>
          <input
            aria-label="Détails de scolarité"
            value={details}
            onChange={(e) => setDetails(e.target.value.slice(0, 80))}
            onBlur={() => sauver(true, details)}
            placeholder="Ex : IFSI 2e année — UE AS validées"
            className="input-base text-sm"
          />
          <button type="button"
            onClick={() => navigate('/soignant/mes-documents?tab=justificatifs')}
            className="text-xs font-medium text-primary underline">
            Téléverser mon attestation de scolarité pour vérification IA →
          </button>
        </>
      )}
    </div>
  );
}
