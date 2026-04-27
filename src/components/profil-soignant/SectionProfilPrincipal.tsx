import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2, MapPin, ShieldCheck, AlertCircle, CheckCircle2 } from 'lucide-react';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { SelectSpecialiteMedicale } from '@/components/SelectSpecialiteMedicale';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { useTypesExerciceAutorises } from '@/hooks/useTypesExerciceAutorises';
import { estEligibleLiberal } from '@/lib/regles-installation-liberal';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { ResumeCompletion } from '@/lib/profil-soignant';
import { getMotifProfilIncomplet } from '@/lib/profil-soignant';

interface Props {
  userId: string;
  email: string;
  rppsVerifie: boolean;
  rppsVerifieLe: string | null;
  rpps: string;
  setRpps: (v: string) => void;
  prenom: string;
  setPrenom: (v: string) => void;
  nom: string;
  setNom: (v: string) => void;
  dateNaissance: string;
  setDateNaissance: (v: string) => void;
  telephone: string;
  setTelephone: (v: string) => void;
  profession: string;
  specialiteMedicale: string;
  setSpecialiteMedicale: (v: string) => void;
  specialiteVerifiee: boolean;
  specialiteSource: string;
  adeli: string;
  setAdeli: (v: string) => void;
  lat: string;
  setLat: (v: string) => void;
  lng: string;
  setLng: (v: string) => void;
  rayon: number;
  villeRecherche: string;
  setVilleRecherche: (v: string) => void;
  typeExercice: string;
  setTypeExercice: (v: string) => void;
  attestationCumul: boolean;
  setAttestationCumul: (v: boolean) => void;
  statutLiberal: string;
  heuresCumulees: number;
  resumeCompletion: ResumeCompletion;
  onRefresh: () => void;
  onSave: () => Promise<void>;
  saving: boolean;
}

function BandeauCompletionProfil({ resume }: { resume: ResumeCompletion }) {
  const motif = getMotifProfilIncomplet(resume);
  if (resume.est_complet) {
    return (
      <div className="card-base bg-success/5 border-success/30">
        <div className="flex items-center gap-3">
          <CheckCircle2 className="h-5 w-5 text-success shrink-0" />
          <div>
            <p className="text-sm font-semibold text-success">Profil complet à 100%</p>
            <p className="text-xs text-muted-foreground">Toutes les informations sont renseignées.</p>
          </div>
        </div>
      </div>
    );
  }
  const couleur = resume.peut_candidater ? 'warning' : 'destructive';
  return (
    <div className={`card-base bg-${couleur}/5 border-${couleur}/30`}>
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex items-start gap-3">
          <AlertCircle className={`h-5 w-5 text-${couleur} shrink-0 mt-0.5`} />
          <div>
            <p className={`text-sm font-semibold text-${couleur}`}>
              Profil complété à {resume.pourcentage}%
            </p>
            {motif && <p className="text-xs text-muted-foreground mt-0.5">{motif}</p>}
          </div>
        </div>
        <span className="text-xs text-muted-foreground">
          {resume.items_remplis}/{resume.total_items}
        </span>
      </div>
      <div className="h-2 bg-muted rounded-full overflow-hidden">
        <div
          className={`h-full bg-${couleur} transition-all`}
          style={{ width: `${resume.pourcentage}%` }}
        />
      </div>
    </div>
  );
}

function RppsVerifierInline(props: {
  userId: string;
  rpps: string;
  setRpps: (v: string) => void;
  prenom: string;
  setPrenom: (v: string) => void;
  nom: string;
  setNom: (v: string) => void;
  dateNaissance: string;
  setDateNaissance: (v: string) => void;
  onVerified: () => void;
}) {
  const { userId, rpps, setRpps, prenom, setPrenom, nom, setNom, dateNaissance, setDateNaissance, onVerified } = props;
  const { afficherNotification } = useNotification();
  const [verifying, setVerifying] = useState(false);
  const [resultat, setResultat] = useState<null | { trouve: boolean; correspond?: boolean; nom_api?: string; prenom_api?: string; profession_api?: string }>(null);

  const peutVerifier = rpps.length === 11 && !!prenom && !!nom;

  const verifier = async () => {
    if (!peutVerifier) return;
    setVerifying(true);
    setResultat(null);
    try {
      // 1) Persister prénom, nom, date naissance, RPPS sur le profil
      const { error: errSave } = await supabase.rpc('fn_modifier_mon_profil' as any, {
        p_prenom: prenom || null,
        p_nom: nom || null,
        p_date_naissance: dateNaissance || null,
        p_numero_rpps: rpps || null,
      });
      if (errSave) {
        afficherNotification({
          type: 'erreur',
          message: `Impossible d'enregistrer vos informations : ${extraireMessageErreur(errSave)}`,
        });
        setVerifying(false);
        return;
      }

      // 2) Vérifier via l'edge function (qui écrit rpps_verifie=true si correspond)
      const response = await fetch(`${SUPABASE_URL}/functions/v1/verify-rpps`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          rpps,
          numero_rpps: rpps,
          prenom,
          nom,
          soignant_id: userId,
        }),
      });
      const data = await response.json();
      setResultat({
        trouve: !!data.trouve,
        correspond: !!data.correspond,
        nom_api: data.nom_api,
        prenom_api: data.prenom_api,
        profession_api: data.profession_api,
      });

      if (data.trouve && data.correspond) {
        afficherNotification({ type: 'succes', message: 'RPPS vérifié avec succès !' });
        onVerified();
      } else if (data.trouve && !data.correspond) {
        afficherNotification({
          type: 'erreur',
          message: `Les informations ne correspondent pas. API : ${data.prenom_api || ''} ${data.nom_api || ''}`,
        });
      } else {
        afficherNotification({ type: 'erreur', message: 'RPPS introuvable dans l\'Annuaire Santé.' });
      }
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: 'Erreur serveur lors de la vérification.' });
    }
    setVerifying(false);
  };

  return (
    <div className="card-base">
      <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
        <ShieldCheck className="h-4 w-4 text-primary" /> Vérification RPPS
      </h2>
      <p className="text-xs text-muted-foreground mb-4">
        Saisissez votre numéro RPPS, prénom et nom tels qu'ils apparaissent dans l'Annuaire Santé.
      </p>
      <div className="space-y-3">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Prénom *</label>
            <input
              value={prenom}
              onChange={(e) => setPrenom(e.target.value)}
              className="input-base"
              placeholder="Tel qu'à l'état civil"
            />
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Nom *</label>
            <input
              value={nom}
              onChange={(e) => setNom(e.target.value)}
              className="input-base"
              placeholder="Tel qu'à l'état civil"
            />
          </div>
        </div>
        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Date de naissance</label>
          <input
            type="date"
            value={dateNaissance}
            onChange={(e) => setDateNaissance(e.target.value)}
            className="input-base"
          />
        </div>
        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Numéro RPPS *</label>
          <input
            value={rpps}
            onChange={(e) => setRpps(e.target.value.replace(/\D/g, '').slice(0, 11))}
            placeholder="11 chiffres"
            className="input-base"
            inputMode="numeric"
            autoComplete="off"
          />
          {rpps.length > 0 && rpps.length < 11 && (
            <p className="text-[10px] text-warning mt-1">
              {rpps.length}/11 chiffres
            </p>
          )}
          <p className="text-[10px] text-muted-foreground mt-1">
            Numéro à 11 chiffres délivré par l'ARS et inscrit sur votre carte CPS. La validation se fait via l'Annuaire Santé (ANS).
          </p>
        </div>

        <button
          type="button"
          onClick={verifier}
          disabled={!peutVerifier || verifying}
          className="btn-primary text-sm py-2 px-4 inline-flex items-center gap-2 disabled:opacity-50"
        >
          {verifying ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}
          {verifying ? 'Vérification…' : 'Vérifier mon RPPS'}
        </button>

        {resultat && resultat.trouve && resultat.correspond && (
          <div className="p-3 rounded-xl border border-success/30 bg-success/5">
            <p className="text-sm font-semibold text-success flex items-center gap-2">
              <ShieldCheck className="h-4 w-4" /> RPPS vérifié — {resultat.prenom_api} {resultat.nom_api}
            </p>
            {resultat.profession_api && (
              <p className="text-xs text-muted-foreground mt-1">Profession : {resultat.profession_api}</p>
            )}
          </div>
        )}
        {resultat && resultat.trouve && !resultat.correspond && (
          <div className="p-3 rounded-xl border border-destructive/30 bg-destructive/5">
            <p className="text-sm font-semibold text-destructive">Les données ne correspondent pas</p>
            <p className="text-xs text-muted-foreground mt-1">
              API : <strong>{resultat.prenom_api} {resultat.nom_api}</strong>. Vérifiez l'orthographe.
            </p>
          </div>
        )}
        {resultat && !resultat.trouve && (
          <div className="p-3 rounded-xl border border-destructive/30 bg-destructive/5">
            <p className="text-sm font-semibold text-destructive">RPPS introuvable</p>
            <p className="text-xs text-muted-foreground mt-1">
              Le numéro saisi n'est pas dans l'Annuaire Santé. Vérifiez les chiffres.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

export function SectionProfilPrincipal(props: Props) {
  const {
    userId, email,
    rppsVerifie, rppsVerifieLe, rpps, setRpps,
    prenom, setPrenom, nom, setNom, dateNaissance, setDateNaissance,
    telephone, setTelephone,
    profession, specialiteMedicale, setSpecialiteMedicale,
    specialiteVerifiee, specialiteSource,
    adeli, setAdeli,
    lat, setLat, lng, setLng, villeRecherche, setVilleRecherche,
    typeExercice, setTypeExercice, attestationCumul, setAttestationCumul,
    statutLiberal, heuresCumulees,
    resumeCompletion, onRefresh, onSave, saving,
  } = props;

  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const { typesAutorises, uniqueType } = useTypesExerciceAutorises(profession);
  const [geoLoading, setGeoLoading] = useState(false);

  useEffect(() => {
    if (uniqueType) setTypeExercice(uniqueType);
  }, [uniqueType, setTypeExercice]);

  const demanderGeolocalisation = () => {
    if (!navigator.geolocation) {
      afficherNotification({ type: 'erreur', message: 'La géolocalisation n\'est pas supportée par votre navigateur.' });
      return;
    }
    setGeoLoading(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLat(position.coords.latitude.toString());
        setLng(position.coords.longitude.toString());
        setGeoLoading(false);
        afficherNotification({ type: 'succes', message: 'Position récupérée avec succès !' });
      },
      () => {
        setGeoLoading(false);
        afficherNotification({ type: 'erreur', message: 'Localisation refusée. Vous pouvez saisir votre adresse manuellement.' });
      },
    );
  };

  return (
    <div className="space-y-4">
      <BandeauCompletionProfil resume={resumeCompletion} />

      {/* RPPS — en TÊTE */}
      {!rppsVerifie ? (
        <RppsVerifierInline
          userId={userId}
          rpps={rpps}
          setRpps={setRpps}
          prenom={prenom}
          setPrenom={setPrenom}
          nom={nom}
          setNom={setNom}
          dateNaissance={dateNaissance}
          setDateNaissance={setDateNaissance}
          onVerified={onRefresh}
        />
      ) : (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-2 flex items-center gap-2">
            <ShieldCheck className="h-4 w-4 text-success" /> Identité professionnelle
          </h2>
          <div className="p-3 rounded-xl border border-success/30 bg-success/5 mb-3">
            <p className="text-sm font-semibold text-success flex items-center gap-2">
              <ShieldCheck className="h-4 w-4" /> RPPS vérifié
              {rppsVerifieLe && (
                <span className="text-xs font-normal text-muted-foreground">
                  · le {new Date(rppsVerifieLe).toLocaleDateString('fr-FR')}
                </span>
              )}
            </p>
            <p className="text-xs text-muted-foreground mt-1">Source : Annuaire Santé (ANS).</p>
          </div>
          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Profession <span className="text-xs text-muted-foreground">(vérifiée RPPS — non modifiable)</span>
              </label>
              <input
                value={profession ? getLabelProfession(profession) : '—'}
                disabled
                className="input-base bg-muted cursor-not-allowed"
              />
              {profession && estEligibleLiberal(profession) && statutLiberal !== 'ACTIF' && heuresCumulees < 3200 && (
                <p className="text-xs text-muted-foreground mt-1">
                  🔒 Passage en libéral disponible à 3 200h — actuellement{' '}
                  <span className="font-semibold text-primary">{heuresCumulees}h</span>/3 200h
                </p>
              )}
            </div>
            {(profession === 'MEDECIN' || profession === 'IDE') && (
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 flex items-center gap-2">
                  <span>Spécialité {profession === 'IDE' ? '(IPA uniquement)' : ''}</span>
                  {specialiteVerifiee && specialiteSource === 'RPPS' && (
                    <span className="inline-flex items-center gap-1 text-[10px] text-success font-semibold">
                      <ShieldCheck className="h-3 w-3" /> Vérifiée RPPS
                    </span>
                  )}
                </label>
                <SelectSpecialiteMedicale
                  value={specialiteMedicale}
                  onChange={setSpecialiteMedicale}
                  professionParent={profession === 'IDE' ? 'IDE' : 'MEDECIN'}
                  disabled={specialiteVerifiee && specialiteSource === 'RPPS'}
                  placeholder={profession === 'IDE' ? 'IPA uniquement (optionnel)' : 'Sélectionnez votre spécialité'}
                />
                {!specialiteVerifiee && specialiteMedicale && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Vérifiable lors de la prochaine vérification RPPS
                  </p>
                )}
              </div>
            )}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">
                  RPPS <span className="text-xs text-muted-foreground">(vérifié — non modifiable)</span>
                </label>
                <input value={rpps} readOnly className="input-base bg-muted cursor-not-allowed" />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">ADELI</label>
                <input
                  value={adeli}
                  onChange={(e) => setAdeli(e.target.value)}
                  className="input-base"
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Informations personnelles */}
      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4">Informations personnelles</h2>
        <div className="space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Prénom{' '}
                {rppsVerifie && (
                  <span className="text-xs text-muted-foreground">(vérifié RPPS — non modifiable)</span>
                )}
              </label>
              <input
                value={prenom}
                onChange={(e) => setPrenom(e.target.value)}
                readOnly={rppsVerifie}
                className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`}
              />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">
                Nom{' '}
                {rppsVerifie && (
                  <span className="text-xs text-muted-foreground">(vérifié RPPS — non modifiable)</span>
                )}
              </label>
              <input
                value={nom}
                onChange={(e) => setNom(e.target.value)}
                readOnly={rppsVerifie}
                className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`}
              />
            </div>
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Téléphone</label>
            <input
              value={telephone}
              onChange={(e) => setTelephone(e.target.value)}
              className="input-base"
            />
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">
              Date de naissance{' '}
              {rppsVerifie && (
                <span className="text-xs text-muted-foreground">(vérifiée — non modifiable)</span>
              )}
            </label>
            <input
              type="date"
              value={dateNaissance}
              onChange={(e) => setDateNaissance(e.target.value)}
              readOnly={rppsVerifie}
              className={`input-base ${rppsVerifie ? 'bg-muted cursor-not-allowed' : ''}`}
            />
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-1.5 block">Email</label>
            <input value={email} disabled className="input-base bg-muted cursor-not-allowed" />
          </div>
        </div>
      </div>

      {/* Adresse */}
      <div className="card-base">
        <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
          <MapPin className="h-4 w-4 text-primary" /> Adresse
        </h2>
        <div className="space-y-3">
          <button
            type="button"
            onClick={demanderGeolocalisation}
            disabled={geoLoading}
            className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-primary/5 border-2 border-dashed border-primary/30 rounded-xl text-primary font-semibold hover:bg-primary/10 transition disabled:opacity-50"
          >
            {geoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
            {geoLoading ? 'Récupération en cours…' : 'Utiliser ma position actuelle'}
          </button>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Latitude</label>
              <input
                type="number"
                step="any"
                value={lat}
                onChange={(e) => setLat(e.target.value)}
                className="input-base"
              />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Longitude</label>
              <input
                type="number"
                step="any"
                value={lng}
                onChange={(e) => setLng(e.target.value)}
                className="input-base"
              />
            </div>
          </div>
          <div className="pt-2 border-t border-border">
            <label className="text-sm font-medium text-foreground mb-1.5 block">🏙️ Ville de recherche</label>
            <p className="text-xs text-muted-foreground mb-2">
              Indiquez la ville où vous cherchez des missions. Utile si vous êtes en déplacement ou en vacances.
            </p>
            <input
              value={villeRecherche}
              onChange={(e) => setVilleRecherche(e.target.value)}
              placeholder="Ex : Lyon, Paris..."
              className="input-base"
            />
          </div>
        </div>
      </div>

      {/* Type d'exercice */}
      {profession && (
        <div className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-4">Type d'exercice</h2>
          {uniqueType ? (
            <div className="p-3 bg-primary/5 border border-primary/20 rounded-xl">
              <p className="text-sm text-foreground">
                En tant que <strong>{getLabelProfession(profession)}</strong>, votre type d'exercice est automatiquement défini comme{' '}
                <strong>
                  {uniqueType === 'SALARIE' ? 'salarié' : uniqueType === 'LIBERAL' ? 'libéral' : 'mixte'}
                </strong>
                .
              </p>
            </div>
          ) : (
            <RadioGroup
              value={typeExercice}
              onValueChange={(v) => {
                setTypeExercice(v);
                if (v === 'SALARIE') setAttestationCumul(false);
              }}
              className="space-y-3"
            >
              {(!typesAutorises || typesAutorises.includes('SALARIE')) && (
                <label className="flex items-start gap-3 cursor-pointer rounded-lg border border-input px-4 py-3 hover:bg-accent/50 transition-colors has-[:checked]:border-primary has-[:checked]:bg-primary/5">
                  <RadioGroupItem value="SALARIE" id="ex-salarie" className="mt-0.5" />
                  <div>
                    <Label htmlFor="ex-salarie" className="font-medium cursor-pointer">Salarié(e)</Label>
                    <p className="text-xs text-muted-foreground mt-0.5">Je suis salarié(e) dans un établissement</p>
                  </div>
                </label>
              )}
              {(!typesAutorises || typesAutorises.includes('LIBERAL')) && (
                <label
                  className={`flex items-start gap-3 rounded-lg border border-input px-4 py-3 transition-colors ${
                    statutLiberal === 'ACTIF' ? 'cursor-pointer hover:bg-accent/50 has-[:checked]:border-primary has-[:checked]:bg-primary/5' : 'opacity-50 cursor-not-allowed'
                  }`}
                >
                  <RadioGroupItem value="LIBERAL" id="ex-liberal" className="mt-0.5" disabled={statutLiberal !== 'ACTIF'} />
                  <div>
                    <Label htmlFor="ex-liberal" className={`font-medium ${statutLiberal !== 'ACTIF' ? 'cursor-not-allowed' : 'cursor-pointer'}`}>
                      Libéral
                    </Label>
                    <p className="text-xs text-muted-foreground mt-0.5">J'exerce en libéral</p>
                    {statutLiberal !== 'ACTIF' && (
                      <p className="text-xs text-destructive mt-1">
                        ⚠️ Vous devez d'abord finaliser votre passage en libéral.{' '}
                        <button
                          type="button"
                          onClick={() => navigate('/soignant/passer-en-liberal')}
                          className="text-primary underline"
                        >
                          Accéder au parcours →
                        </button>
                      </p>
                    )}
                  </div>
                </label>
              )}
              {(!typesAutorises || typesAutorises.includes('MIXTE')) && (
                <label
                  className={`flex items-start gap-3 rounded-lg border border-input px-4 py-3 transition-colors ${
                    statutLiberal === 'ACTIF' ? 'cursor-pointer hover:bg-accent/50 has-[:checked]:border-primary has-[:checked]:bg-primary/5' : 'opacity-50 cursor-not-allowed'
                  }`}
                >
                  <RadioGroupItem value="MIXTE" id="ex-mixte" className="mt-0.5" disabled={statutLiberal !== 'ACTIF'} />
                  <div>
                    <Label htmlFor="ex-mixte" className={`font-medium ${statutLiberal !== 'ACTIF' ? 'cursor-not-allowed' : 'cursor-pointer'}`}>
                      Mixte
                    </Label>
                    <p className="text-xs text-muted-foreground mt-0.5">Je cumule salarié et libéral</p>
                    {statutLiberal !== 'ACTIF' && (
                      <p className="text-xs text-destructive mt-1">
                        ⚠️ Validation parcours libéral requise.{' '}
                        <button
                          type="button"
                          onClick={() => navigate('/soignant/passer-en-liberal')}
                          className="text-primary underline"
                        >
                          Parcours →
                        </button>
                      </p>
                    )}
                  </div>
                </label>
              )}
            </RadioGroup>
          )}

          {(typeExercice === 'MIXTE' || typeExercice === 'LIBERAL') && !uniqueType && (
            <div className="mt-4 p-3 bg-warning/5 border border-warning/20 rounded-xl">
              <label className="flex items-start gap-3 cursor-pointer">
                <Checkbox
                  checked={attestationCumul}
                  onCheckedChange={(v) => setAttestationCumul(!!v)}
                  className="mt-0.5"
                />
                <span className="text-sm text-foreground">
                  J'atteste avoir vérifié que mon contrat de travail actuel autorise le cumul d'activités conformément à l'article L1222-5 du Code du travail.
                </span>
              </label>
            </div>
          )}
        </div>
      )}

      {/* Save button */}
      <div className="flex justify-end pt-2">
        <button
          type="button"
          onClick={onSave}
          disabled={saving}
          className="btn-primary disabled:opacity-50"
        >
          {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
        </button>
      </div>
    </div>
  );
}
