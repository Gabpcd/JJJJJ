import React, { useState, useEffect } from 'react';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { handleErrorSilent } from '@/lib/handleError';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CONTRATS, getLabelProfession, getTypesContratSoignant } from '@/lib/constantes';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { useRole } from '@/hooks/useRole';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { capturerErreurSentry } from '@/lib/sentry';
import { MapPin, Loader2, Download, Trash2, MapPinOff, Copy, Gift, CheckCircle } from 'lucide-react';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { SectionBio } from '@/components/SectionBio';
import { EncartInvitation } from '@/components/EncartInvitation';
import { BadgesGamification, BadgeStats } from '@/components/BadgesGamification';
import { AvatarUpload } from '@/components/AvatarUpload';
import { Switch } from '@/components/ui/switch';
import { PoolUrgenceToggle } from '@/components/PoolUrgenceToggle';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function ProfilSoignant() {
  usePageTitle('Profil');
  const { user, deconnexion } = useAuth();
  const { afficherNotification } = useNotification();
  const { role } = useRole();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [email, setEmail] = useState('');
  const [profession, setProfession] = useState('');
  const [rppsVerifie, setRppsVerifie] = useState(false);
  const [form, setForm] = useState({
    prenom: '', nom: '', telephone: '', dateNaissance: '',
    typeContrat: '', rpps: '', adeli: '',
    lat: '', lng: '', rayon: 30,
    bio: '', anneesExperience: 0,
    avatarUrl: '',
    tauxHoraireMinimum: null as number | null,
  });
  const [specialites, setSpecialites] = useState<string[]>([]);
  const [typesContrat, setTypesContrat] = useState<string[]>(['CDDU']);
  const [consentementGPS, setConsentementGPS] = useState(true);
  const [gpsToggling, setGpsToggling] = useState(false);

  // RGPD states
  const [exportLoading, setExportLoading] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [deleteLoading, setDeleteLoading] = useState(false);

  // Parrainage
  const [codeParrainage, setCodeParrainage] = useState('');
  const [codeRecu, setCodeRecu] = useState('');
  const [parrainageLoading, setParrainageLoading] = useState(false);
  const [parrainageSucces, setParrainageSucces] = useState(false);
  const [filleuls, setFilleuls] = useState<any[]>([]);
  const [codeCopied, setCodeCopied] = useState(false);
   const [poolUrgenceActif, setPoolUrgenceActif] = useState(false);
   const [poolUrgenceRayon, setPoolUrgenceRayon] = useState(15);
   const [typeExercice, setTypeExercice] = useState('SALARIE');
   const [attestationCumul, setAttestationCumul] = useState(false);
  const [heuresCumulees, setHeuresCumulees] = useState(0);
  const [statutLiberal, setStatutLiberal] = useState('');
  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('prenom, nom, email, telephone, date_naissance, profession, type_contrat, types_contrat_acceptes, numero_rpps, numero_adeli, rpps_verifie, adresse_lat, adresse_lng, rayon_deplacement_km, consentement_gps, code_parrainage, avatar_url, disponible_urgence, urgence_rayon_km, bio, annees_experience, specialites, heures_cumulees, statut_liberal, type_exercice, attestation_cumul_activite, taux_horaire_minimum').eq('id', user.id).single().then(({ data, error }: any) => {
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
        });
        setEmail(data.email);
        setProfession(data.profession);
        setRppsVerifie(!!data.rpps_verifie);
        setHeuresCumulees(data.heures_cumulees || 0);
        setStatutLiberal(data.statut_liberal || '');
        setTypeExercice(data.type_exercice || 'SALARIE');
        setAttestationCumul(data.attestation_cumul_activite || false);
        setCodeParrainage(data.code_parrainage || '');
        setForm({
          prenom: data.prenom || '',
          nom: data.nom || '',
          telephone: data.telephone || '',
          dateNaissance: data.date_naissance || '',
          typeContrat: data.type_contrat || '',
          rpps: data.numero_rpps || '',
          adeli: data.numero_adeli || '',
          lat: data.adresse_lat?.toString() || '',
          lng: data.adresse_lng?.toString() || '',
          rayon: data.rayon_deplacement_km ?? 30,
          bio: data.bio || '',
          anneesExperience: data.annees_experience || 0,
          avatarUrl: data.avatar_url || '',
          tauxHoraireMinimum: data.taux_horaire_minimum ?? null,
        });
        setSpecialites(Array.isArray(data.specialites) ? data.specialites : (data.specialites ? JSON.parse(data.specialites) : []));
        setTypesContrat(getTypesContratSoignant(data as any));
        setConsentementGPS(data.consentement_gps !== false);
        setPoolUrgenceActif(data.disponible_urgence || false);
        setPoolUrgenceRayon(data.urgence_rayon_km || 15);
      }
      setLoading(false);
    });

    // Load filleuls
    supabase.rpc('fn_mes_filleuls' as any).then(({ data }: any) => {
      if (Array.isArray(data)) setFilleuls(data);
    });
  }, [user]);

  const [geoLoading, setGeoLoading] = useState(false);
  const maj = (champ: string, valeur: any) => setForm(prev => ({ ...prev, [champ]: valeur }));

  const toggleContrat = (valeur: string) => {
    setTypesContrat(prev => {
      if (prev.includes(valeur)) {
        if (prev.length <= 1) return prev;
        return prev.filter(v => v !== valeur);
      }
      return [...prev, valeur];
    });
  };

  const demanderGeolocalisation = () => {
    if (!navigator.geolocation) {
      afficherNotification({ type: 'erreur', message: 'La géolocalisation n\'est pas supportée par votre navigateur.' });
      return;
    }
    setGeoLoading(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        maj('lat', position.coords.latitude.toString());
        maj('lng', position.coords.longitude.toString());
        setGeoLoading(false);
        afficherNotification({ type: 'succes', message: 'Position récupérée avec succès !' });
      },
      () => {
        setGeoLoading(false);
        afficherNotification({ type: 'erreur', message: 'Localisation refusée. Vous pouvez saisir votre adresse manuellement.' });
      }
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (!form.anneesExperience && form.anneesExperience !== 0) {
      afficherNotification({ type: 'erreur', message: 'Le nombre d\'années d\'expérience est obligatoire.' });
      return;
    }
    // Validate attestation for MIXTE/LIBERAL
    if ((typeExercice === 'MIXTE' || typeExercice === 'LIBERAL') && !attestationCumul) {
      afficherNotification({ type: 'erreur', message: 'Vous devez attester la conformité de votre cumul d\'activités (article L1222-5).' });
      return;
    }
    setSaving(true);
    const { data: rpcResult, error } = await supabase.rpc('fn_modifier_mon_profil' as any, {
      p_telephone: form.telephone || null,
      p_adresse_rue: null, p_adresse_ville: null, p_adresse_code_postal: null,
      p_rayon_deplacement_km: form.rayon,
      p_prenom: form.prenom || null, p_nom: form.nom || null,
      p_date_naissance: form.dateNaissance || null,
      p_types_contrat: typesContrat,
      p_numero_rpps: form.rpps || null, p_numero_adeli: form.adeli || null,
      p_adresse_lat: form.lat ? parseFloat(form.lat) : null,
      p_adresse_lng: form.lng ? parseFloat(form.lng) : null,
      p_bio: form.bio || null,
      p_annees_experience: form.anneesExperience,
      p_specialites: specialites,
    });

    // Also update type_exercice via RPC
    const { error: exError } = await supabase.rpc('fn_modifier_mon_profil_extra' as any, {
      p_type_exercice: typeExercice,
      p_attestation_cumul_activite: attestationCumul,
      p_taux_horaire_minimum: form.tauxHoraireMinimum,
    });

    if (error || exError) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error || exError) });
    } else if (rpcResult?.error) {
      afficherNotification({ type: 'erreur', message: rpcResult.error });
    } else {
      afficherNotification({ type: 'succes', message: 'Profil mis à jour avec succès !' });
    }
    setSaving(false);
  };

  // B2: Export RGPD
  const handleExportRGPD = async () => {
    setExportLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_rgpd_exporter_rate_limited' as any);
      if (error) throw error;
      // L3: Audit RGPD export
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: role || 'SOIGNANT',
        p_action: 'RGPD_EXPORT_DONNEES',
        p_type_ressource: 'soignant', p_id_ressource: user!.id,
        p_cle_s3: null, p_details: { format: 'json' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
      afficherNotification({ type: 'succes', message: 'Données exportées avec succès.' });
    } catch (err: any) {
      capturerErreurSentry(err, 'ProfilSoignant', 'export_rgpd');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setExportLoading(false);
  };

  // B3: Suppression compte
  const handleSupprimerCompte = async () => {
    setDeleteLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_supprimer_compte_rate_limited' as any);
      if (error) throw error;
      if (data?.error) {
        afficherNotification({ type: 'erreur', message: data.error });
        setDeleteLoading(false);
        return;
      }
      afficherNotification({ type: 'succes', message: 'Compte supprimé. Redirection...' });
      await supabase.auth.signOut();
      navigate('/');
    } catch (err: any) {
      capturerErreurSentry(err, 'ProfilSoignant', 'supprimer_compte');
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    }
    setDeleteLoading(false);
    setShowDeleteModal(false);
  };

  const [noteMoyenne, setNoteMoyenne] = useState<{ moyenne: number; total: number } | null>(null);
  const [evaluations, setEvaluations] = useState<any[]>([]);
  const [badgeStats, setBadgeStats] = useState<BadgeStats | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_note_moyenne' as any, { p_user_id: user.id })
      .then(({ data }: any) => {
        if (data && typeof data === 'object') setNoteMoyenne(data);
        else if (Array.isArray(data) && data[0]) setNoteMoyenne(data[0]);
      });
    supabase.rpc('fn_mes_evaluations_recues' as any)
      .then(({ data }: any) => {
        if (Array.isArray(data)) setEvaluations(data);
      });
    // Load badge stats
    supabase.rpc('fn_badge_stats' as any).then(({ data }: any) => {
      if (data) setBadgeStats(data as BadgeStats);
    });
  }, [user]);

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="flex items-center gap-4 mb-6">
        <AvatarUpload
          src={(form as any).avatarUrl}
          prenom={form.prenom}
          nom={form.nom}
          size={96}
          mode="soignant"
          onUploaded={(url) => setForm(prev => ({ ...prev, avatarUrl: url } as any))}
        />
        <div>
          <h1 className="text-xl font-bold text-foreground">{form.prenom} {form.nom}</h1>
          <div className="flex items-center gap-2 mt-1">
            <span className="text-sm text-muted-foreground">{getLabelProfession(profession)}</span>
            <BadgeRPPS rppsVerifie={rppsVerifie} rpps={form.rpps} profession={profession} />
          </div>
        </div>
      </div>

      {noteMoyenne && noteMoyenne.total > 0 && (
        <div className="card-base mb-6">
          <h2 className="text-base font-semibold text-foreground mb-2">Évaluations reçues</h2>
          <p className="text-lg font-bold text-foreground">⭐ {noteMoyenne.moyenne.toFixed(1)}/5 — {noteMoyenne.total} évaluation{noteMoyenne.total > 1 ? 's' : ''}</p>
          {evaluations.length > 0 && (
            <div className="mt-3 space-y-2">
              {evaluations.slice(0, 5).map((ev: any, i: number) => (
                <div key={i} className="text-sm text-muted-foreground border-t border-border pt-2">
                  <span className="text-foreground font-medium">{'⭐'.repeat(ev.note)}</span>
                  {ev.commentaire && <p className="text-xs mt-0.5">{ev.commentaire}</p>}
                  {ev.cree_le && <p className="text-[10px] text-muted-foreground/60">{format(new Date(ev.cree_le), 'd MMM yyyy', { locale: fr })}</p>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Badges Gamification */}
      {badgeStats && (
        <div className="max-w-2xl mb-6">
          <BadgesGamification stats={badgeStats} />
        </div>
      )}

      <form onSubmit={handleSave} className="space-y-6 max-w-2xl">
        {/* Bio / Présentation */}
        <SectionBio
          bio={form.bio}
          onBioChange={(val) => maj('bio', val)}
          anneesExperience={form.anneesExperience}
          onAnneesChange={(val) => maj('anneesExperience', val)}
          specialites={specialites}
          onSpecialitesChange={setSpecialites}
        />

        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Identité</h2>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Prénom <span className="text-xs text-muted-foreground">(vérifié — non modifiable)</span></label>
                <input value={form.prenom} readOnly className="input-base bg-muted cursor-not-allowed" />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Nom <span className="text-xs text-muted-foreground">(vérifié — non modifiable)</span></label>
                <input value={form.nom} readOnly className="input-base bg-muted cursor-not-allowed" />
              </div>
            </div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label><input value={form.telephone} onChange={e => maj('telephone', e.target.value)} className="input-base" /></div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance <span className="text-xs text-muted-foreground">(vérifié — non modifiable)</span></label>
              <input type="date" value={form.dateNaissance} readOnly className="input-base bg-muted cursor-not-allowed" />
            </div>
            <div><label className="text-sm font-medium text-foreground mb-1.5 block">Email</label><input value={email} disabled className="input-base bg-muted cursor-not-allowed" /></div>
          </div>
        </div>
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Professionnel</h2>
          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Profession</label>
              <input value={getLabelProfession(profession)} disabled className="input-base bg-muted cursor-not-allowed" />
              {statutLiberal !== 'ACTIF' && heuresCumulees < 3200 && (
                <p className="text-xs text-muted-foreground mt-1">
                  🔒 Passage en libéral disponible à 3 200h — actuellement <span className="font-semibold text-primary">{heuresCumulees}h</span>/3 200h
                </p>
              )}
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Types de contrat acceptés</label>
              <p className="text-xs text-muted-foreground mb-2">Cochez tous les types de contrat que vous acceptez</p>
              <div className="space-y-2">
                {CONTRATS.map(c => (
                  <label key={c.valeur} className="flex items-center gap-3 cursor-pointer group">
                    <input type="checkbox" checked={typesContrat.includes(c.valeur)} onChange={() => toggleContrat(c.valeur)} className="h-4 w-4 rounded border-border text-primary focus:ring-primary accent-primary" />
                    <span className="text-sm text-foreground group-hover:text-primary transition-colors">{c.label}</span>
                  </label>
                ))}
              </div>
              {typesContrat.length === 0 && <p className="text-xs text-destructive mt-1">Sélectionnez au moins un type de contrat</p>}
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">RPPS</label>
                <input value={form.rpps} onChange={e => maj('rpps', e.target.value.replace(/\D/g, '').slice(0, 11))} disabled={rppsVerifie} className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`} />
                {rppsVerifie && <p className="text-[10px] text-success mt-1">✓ Vérifié via l'Annuaire Santé</p>}
              </div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">ADELI</label><input value={form.adeli} onChange={e => maj('adeli', e.target.value)} className="input-base" /></div>
            </div>
          </div>
        </div>

        {/* Type d'exercice */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Type d'exercice</h2>
          <RadioGroup value={typeExercice} onValueChange={(v) => {
            setTypeExercice(v);
            if (v === 'SALARIE') setAttestationCumul(false);
          }} className="space-y-3">
            <label className="flex items-start gap-3 cursor-pointer rounded-lg border border-input px-4 py-3 hover:bg-accent/50 transition-colors has-[:checked]:border-primary has-[:checked]:bg-primary/5">
              <RadioGroupItem value="SALARIE" id="ex-salarie" className="mt-0.5" />
              <div>
                <Label htmlFor="ex-salarie" className="font-medium cursor-pointer">Salarié(e)</Label>
                <p className="text-xs text-muted-foreground mt-0.5">Je suis salarié(e) dans un établissement</p>
              </div>
            </label>
            <label className={`flex items-start gap-3 rounded-lg border border-input px-4 py-3 transition-colors ${statutLiberal === 'ACTIF' ? 'cursor-pointer hover:bg-accent/50 has-[:checked]:border-primary has-[:checked]:bg-primary/5' : 'opacity-50 cursor-not-allowed'}`}>
              <RadioGroupItem value="LIBERAL" id="ex-liberal" className="mt-0.5" disabled={statutLiberal !== 'ACTIF'} />
              <div>
                <Label htmlFor="ex-liberal" className={`font-medium ${statutLiberal !== 'ACTIF' ? 'cursor-not-allowed' : 'cursor-pointer'}`}>Libéral</Label>
                <p className="text-xs text-muted-foreground mt-0.5">J'exerce en libéral</p>
                {statutLiberal !== 'ACTIF' && (
                  <p className="text-xs text-destructive mt-1">
                    ⚠️ Vous devez d'abord faire valider vos 3200h via la page Parcours.{' '}
                    <button type="button" onClick={() => navigate('/soignant/parcours-3200h')} className="text-primary underline">Accéder au Parcours →</button>
                  </p>
                )}
              </div>
            </label>
            <label className={`flex items-start gap-3 rounded-lg border border-input px-4 py-3 transition-colors ${statutLiberal === 'ACTIF' ? 'cursor-pointer hover:bg-accent/50 has-[:checked]:border-primary has-[:checked]:bg-primary/5' : 'opacity-50 cursor-not-allowed'}`}>
              <RadioGroupItem value="MIXTE" id="ex-mixte" className="mt-0.5" disabled={statutLiberal !== 'ACTIF'} />
              <div>
                <Label htmlFor="ex-mixte" className={`font-medium ${statutLiberal !== 'ACTIF' ? 'cursor-not-allowed' : 'cursor-pointer'}`}>Mixte</Label>
                <p className="text-xs text-muted-foreground mt-0.5">Je cumule salarié et libéral</p>
                {statutLiberal !== 'ACTIF' && (
                  <p className="text-xs text-destructive mt-1">
                    ⚠️ Validation 3200h requise.{' '}
                    <button type="button" onClick={() => navigate('/soignant/parcours-3200h')} className="text-primary underline">Parcours →</button>
                  </p>
                )}
              </div>
            </label>
          </RadioGroup>

          {(typeExercice === 'MIXTE' || typeExercice === 'LIBERAL') && (
            <div className="mt-4 p-3 bg-warning/5 border border-warning/20 rounded-xl">
              <label className="flex items-start gap-3 cursor-pointer">
                <Checkbox
                  checked={attestationCumul}
                  onCheckedChange={(v) => setAttestationCumul(!!v)}
                  className="mt-0.5"
                />
                <span className="text-sm text-foreground">
                  ✅ J'atteste avoir vérifié que mon contrat de travail actuel autorise le cumul d'activités conformément à l'article L1222-5 du Code du travail.
                </span>
              </label>
            </div>
          )}
        </div>

        {/* Taux horaire minimum */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">💰 Taux horaire minimum accepté</h2>
          <p className="text-xs text-muted-foreground mb-3">Les missions en dessous de ce taux seront grisées dans vos résultats.</p>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-foreground font-medium">
                {form.tauxHoraireMinimum ? `${form.tauxHoraireMinimum} €/h` : 'Non défini'}
              </span>
              {form.tauxHoraireMinimum && (
                <button type="button" onClick={() => maj('tauxHoraireMinimum', null)} className="text-xs text-destructive hover:underline">Supprimer</button>
              )}
            </div>
            <input
              type="range"
              min={10}
              max={100}
              step={1}
              value={form.tauxHoraireMinimum ?? 10}
              onChange={e => maj('tauxHoraireMinimum', Number(e.target.value))}
              className="w-full accent-primary"
            />
            <div className="flex justify-between text-[10px] text-muted-foreground"><span>10 €/h</span><span>100 €/h</span></div>
          </div>
        </div>

        {/* Géolocalisation */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">📍 Géolocalisation</h2>
          <div className="space-y-3">
            <button type="button" onClick={demanderGeolocalisation} disabled={geoLoading} className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50">
              {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
              {geoLoading ? 'Récupération en cours…' : '📍 Utiliser ma position actuelle'}
            </button>
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Latitude</label><input type="number" step="any" value={form.lat} onChange={e => maj('lat', e.target.value)} className="input-base" /></div>
              <div><label className="text-sm font-medium text-foreground mb-1.5 block">Longitude</label><input type="number" step="any" value={form.lng} onChange={e => maj('lng', e.target.value)} className="input-base" /></div>
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Rayon de déplacement : <span className="text-primary font-bold">{form.rayon} km</span></label>
              <input type="range" min={5} max={100} value={form.rayon} onChange={e => maj('rayon', Number(e.target.value))} className="w-full accent-primary" />
              <div className="flex justify-between text-[10px] text-muted-foreground"><span>5 km</span><span>100 km</span></div>
            </div>
            {/* Ville de recherche fallback */}
            <div className="pt-2 border-t border-border">
              <label className="text-sm font-medium text-foreground mb-1.5 block">🏙️ Ville de recherche</label>
              <p className="text-xs text-muted-foreground mb-2">Indiquez la ville où vous cherchez des missions. Utile si vous êtes en déplacement ou en vacances.</p>
              <input value={(form as any).villeRecherche || ''} onChange={e => maj('villeRecherche', e.target.value)} placeholder="Ex : Lyon, Paris..." className="input-base" />
            </div>
          </div>
        </div>

        {/* Consentement GPS */}
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Consentement GPS</h2>
          <div className="flex items-center justify-between">
            <div className="flex-1">
              <p className="text-sm text-foreground font-medium">Autoriser la géolocalisation lors des pointages</p>
              <p className="text-xs text-muted-foreground mt-1">
                {consentementGPS
                  ? 'Votre position sera capturée uniquement au moment de l\'arrivée et du départ.'
                  : '⚠️ Sans GPS, vos pointages nécessiteront une vérification manuelle par l\'établissement.'}
              </p>
            </div>
            <Switch
              checked={consentementGPS}
              disabled={gpsToggling}
              onCheckedChange={async (checked) => {
                setGpsToggling(true);
                const { data, error } = await supabase.rpc('fn_consentir_gps' as any, { p_accepte: checked });
                if (error) {
                  afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
                } else if (data && (data as any).error) {
                  afficherNotification({ type: 'erreur', message: (data as any).error });
                } else {
                  setConsentementGPS(checked);
                  // L4: Audit GPS consent change
                  await supabase.rpc('fn_ecrire_audit_safe', {
                    p_acteur_id: user!.id, p_type_acteur: role || 'SOIGNANT',
                    p_action: checked ? 'GPS_CONSENTEMENT_ACTIVE' : 'GPS_CONSENTEMENT_RETIRE',
                    p_type_ressource: 'soignant', p_id_ressource: user!.id,
                    p_cle_s3: null, p_details: { consentement_gps: checked },
                    p_ip: null, p_navigateur: navigator.userAgent,
                  });
                  afficherNotification({
                    type: checked ? 'succes' : 'avertissement',
                    message: checked ? 'Consentement GPS activé.' : 'Consentement GPS retiré. Vérification manuelle requise.',
                  });
                }
                setGpsToggling(false);
              }}
            />
          </div>
        </div>
        <button type="submit" disabled={saving} className="btn-primary w-full md:w-auto disabled:opacity-50">
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </form>

      {/* Pool Urgence */}
      <div className="max-w-2xl mt-6">
        <PoolUrgenceToggle
          actif={poolUrgenceActif}
          rayonKm={poolUrgenceRayon}
          onUpdate={(a, r) => { setPoolUrgenceActif(a); setPoolUrgenceRayon(r); }}
          onError={(msg) => afficherNotification({ type: 'erreur', message: msg })}
          onSuccess={(msg) => afficherNotification({ type: 'succes', message: msg })}
        />
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
                value={codeRecu}
                onChange={e => setCodeRecu(e.target.value.toUpperCase())}
                placeholder="Ex: SOIN-ABCD"
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
                  } else if (data?.error) {
                    afficherNotification({ type: 'erreur', message: data.error });
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

      {/* RGPD Section */}
      <div className="max-w-2xl mt-12 space-y-4">
        <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">Données personnelles (RGPD)</h2>

        <button
          onClick={handleExportRGPD}
          disabled={exportLoading}
          className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition disabled:opacity-50"
        >
          <Download className="h-4 w-4" />
          {exportLoading ? 'Export en cours…' : '📥 Télécharger mes données (RGPD)'}
        </button>

        <button
          onClick={() => setShowDeleteModal(true)}
          className="flex items-center gap-2 text-sm text-destructive hover:text-destructive/80 transition"
        >
          <Trash2 className="h-4 w-4" /> Supprimer mon compte
        </button>
      </div>

      {/* B3: Modal suppression */}
      {showDeleteModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center">
          <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={() => setShowDeleteModal(false)} />
          <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full">
            <h3 className="text-lg font-bold text-destructive mb-2">🗑️ Supprimer mon compte</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Cette action est irréversible. Vos données seront anonymisées conformément au RGPD. Tapez <strong>SUPPRIMER</strong> pour confirmer.
            </p>
            <input
              value={deleteConfirmText}
              onChange={e => setDeleteConfirmText(e.target.value)}
              placeholder="Tapez SUPPRIMER"
              className="input-base mb-4"
            />
            <div className="flex gap-3 justify-end">
              <button onClick={() => { setShowDeleteModal(false); setDeleteConfirmText(''); }} className="btn-secondary text-sm px-4 py-2">Annuler</button>
              <button
                onClick={handleSupprimerCompte}
                disabled={deleteConfirmText !== 'SUPPRIMER' || deleteLoading}
                className="btn-danger text-sm px-4 py-2 disabled:opacity-50"
              >
                {deleteLoading ? 'Suppression…' : 'Supprimer définitivement'}
              </button>
            </div>
          </div>
        </div>
      )}
    </LayoutApp>
  );
}
