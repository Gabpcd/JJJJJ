import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { CheckCircle, Star, Clock, ShieldCheck, ShieldAlert, Circle, CheckCircle2, Search, Info, X } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { EtatVide } from '@/components/EtatVide';
import { JaugeProgression } from '@/components/JaugeProgression';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface SoignantData {
  prenom: string; nom: string; telephone: string | null;
  date_naissance: string | null; profession: string; type_contrat: string | null;
  numero_rpps: string | null; numero_adeli: string | null;
  adresse_lat: number | null; adresse_lng: number | null;
  tous_documents_valides: boolean | null; identite_verifiee: boolean | null;
  score_fiabilite: number | null; total_missions_terminees: number | null;
  heures_cumulees: number | null; eligible_conversion_3200h: boolean | null;
}

interface MissionData {
  id: string; intitule: string; service: string | null;
  debut_le: string; fin_le: string; taux_horaire_base: number;
  est_urgente: boolean | null;
  etablissements: { nom: string; adresse_ville: string } | null;
}

function calculerCompletionProfil(s: SoignantData) {
  const checks: [boolean, string][] = [
    [!!s.prenom, 'Prénom'], [!!s.nom, 'Nom'], [!!s.telephone, 'Téléphone'],
    [!!s.date_naissance, 'Date de naissance'], [!!s.profession, 'Profession'],
    [!!s.type_contrat, 'Type de contrat'], [!!(s.numero_rpps || s.numero_adeli), 'Numéro RPPS/ADELI'],
    [!!(s.adresse_lat && s.adresse_lng), 'Adresse géolocalisée'],
    [!!s.tous_documents_valides, 'Documents validés'], [!!s.identite_verifiee, 'Identité vérifiée'],
  ];
  const completes = checks.filter(([ok]) => ok).map(([, l]) => l);
  const manquants = checks.filter(([ok]) => !ok).map(([, l]) => l);
  return { pourcentage: Math.round((completes.length / checks.length) * 100), manquants, completes };
}

function getScoreConfig(score: number) {
  if (score >= 90) return { couleurIcone: 'text-success', couleurFond: 'bg-success/10', label: 'Excellent' };
  if (score >= 70) return { couleurIcone: 'text-primary', couleurFond: 'bg-primary/10', label: 'Fiable' };
  if (score >= 50) return { couleurIcone: 'text-warning', couleurFond: 'bg-warning/10', label: 'Correct' };
  if (score >= 30) return { couleurIcone: 'text-warning', couleurFond: 'bg-warning/10', label: 'À améliorer' };
  return { couleurIcone: 'text-destructive', couleurFond: 'bg-destructive/10', label: 'Critique' };
}

export default function DashboardSoignant() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [missions, setMissions] = useState<MissionData[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalScore, setModalScore] = useState(false);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const [{ data: sg }, { data: ms }] = await Promise.all([
        supabase.from('soignants').select('prenom, nom, telephone, date_naissance, profession, type_contrat, numero_rpps, numero_adeli, adresse_lat, adresse_lng, tous_documents_valides, identite_verifiee, score_fiabilite, total_missions_terminees, heures_cumulees, eligible_conversion_3200h').eq('id', user.id).single(),
        supabase.from('missions').select('id, intitule, service, debut_le, fin_le, taux_horaire_base, est_urgente, etablissements(nom, adresse_ville)').eq('statut', 'OUVERTE').order('debut_le', { ascending: true }).limit(3),
      ]);
      if (sg) setSoignant(sg as any);
      if (ms) setMissions(ms as any);
      setLoading(false);
    };
    load();
  }, [user]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const profil = calculerCompletionProfil(soignant);
  const score = soignant.score_fiabilite ?? 50;
  const scoreConfig = getScoreConfig(score);
  const heures = soignant.heures_cumulees ?? 0;
  const missionsTerminees = soignant.total_missions_terminees ?? 0;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Bonjour, <span className="text-primary">{soignant.prenom}</span> 👋</h1>
        {!soignant.tous_documents_valides ? (
          <p className="text-sm text-warning mt-1">⚠️ Complétez votre profil pour postuler aux missions</p>
        ) : (
          <p className="text-sm text-muted-foreground mt-1">Voici votre activité</p>
        )}
      </div>

      {profil.pourcentage < 100 ? (
        <div className="rounded-2xl bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 p-4 md:p-6 mb-6">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-sm font-semibold text-foreground">Profil complété à {profil.pourcentage}%</h2>
            <button onClick={() => navigate('/soignant/profil')} className="text-xs text-primary font-medium hover:underline">Compléter →</button>
          </div>
          <JaugeProgression valeur={profil.pourcentage} max={100} couleurBarre="bg-primary" couleurFond="bg-primary/10" />
          <div className="mt-3 grid grid-cols-2 gap-1.5">
            {profil.completes.map(c => <div key={c} className="flex items-center gap-1.5 text-xs text-primary"><CheckCircle2 className="h-3.5 w-3.5" />{c}</div>)}
            {profil.manquants.map(m => <div key={m} className="flex items-center gap-1.5 text-xs text-muted-foreground"><Circle className="h-3.5 w-3.5" />{m}</div>)}
          </div>
        </div>
      ) : (
        <div className="rounded-2xl bg-gradient-to-r from-success/5 to-primary/5 border border-success/20 p-4 mb-6 text-center">
          <p className="text-sm font-semibold text-success">✨ Profil complet — Vous êtes prêt(e) à postuler !</p>
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPI icone={CheckCircle} valeur={missionsTerminees} label="Missions terminées" couleurIcone="text-success" couleurFond="bg-success/10" />
        <div className="card-kpi cursor-pointer" onClick={() => setModalScore(true)}>
          <div className="flex items-start gap-3">
            <div className={`rounded-xl p-2.5 ${scoreConfig.couleurFond}`}><Star className={`h-5 w-5 ${scoreConfig.couleurIcone}`} /></div>
            <div>
              <p className="text-2xl font-bold text-foreground">{score}<span className="text-sm text-muted-foreground">/100</span></p>
              <p className="text-xs text-muted-foreground">Score · {scoreConfig.label}</p>
              <p className="text-[10px] text-primary mt-0.5 flex items-center gap-0.5"><Info className="h-3 w-3" /> En savoir plus</p>
            </div>
          </div>
        </div>
        <CarteKPI icone={Clock} valeur={`${heures}h`} label="Heures cumulées" sousLabel="sur 3 200h objectif" couleurIcone="text-purple-600" couleurFond="bg-purple-100" />
        <div className="card-kpi">
          <div className="flex items-start gap-3">
            <div className={`rounded-xl p-2.5 ${soignant.tous_documents_valides ? 'bg-success/10' : 'bg-destructive/10'}`}>
              {soignant.tous_documents_valides ? <ShieldCheck className="h-5 w-5 text-success" /> : <ShieldAlert className="h-5 w-5 text-destructive" />}
            </div>
            <div>
              {soignant.tous_documents_valides ? (
                <span className="badge-base bg-success/10 text-success">✓ Complet</span>
              ) : (
                <><span className="badge-base bg-destructive/10 text-destructive">✗ Incomplet</span><button onClick={() => navigate('/soignant/documents')} className="block text-[10px] text-primary mt-1 hover:underline">Ajouter →</button></>
              )}
              <p className="text-xs text-muted-foreground mt-1">Documents</p>
            </div>
          </div>
        </div>
      </div>

      <div className="mb-6">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Missions disponibles</h2>
          <button onClick={() => navigate('/soignant/missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
        </div>
        {missions.length > 0 ? (
          <div className="space-y-3">
            {missions.map(m => (
              <div key={m.id} className="card-base hover:shadow-md transition-shadow">
                <div className="flex items-start justify-between mb-2">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      {m.est_urgente && <span className="badge-base bg-destructive text-destructive-foreground text-[10px]">🔥 URGENT</span>}
                      <h3 className="font-semibold text-sm text-foreground truncate">{m.intitule}</h3>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">{m.etablissements?.nom} · {m.etablissements?.adresse_ville}</p>
                  </div>
                  <span className="text-primary font-bold text-sm whitespace-nowrap ml-2">{m.taux_horaire_base} €/h</span>
                </div>
                <p className="text-xs text-muted-foreground">
                  {format(new Date(m.debut_le), "EEE d MMM · HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                </p>
                <button className="btn-secondary text-xs px-3 py-1.5 mt-3">Voir</button>
              </div>
            ))}
          </div>
        ) : (
          <EtatVide icone={Search} titre="Aucune mission disponible" sousTitre="De nouvelles missions sont publiées chaque jour. Revenez bientôt !" boutonLabel="Activer les notifications" boutonRoute="#" boutonDisabled />
        )}
      </div>

      <div className="rounded-2xl bg-gradient-to-r from-purple-50 to-purple-100/50 border border-purple-200 p-4 md:p-6">
        <h2 className="text-base font-bold text-foreground mb-1">Mon parcours vers le libéral</h2>
        <p className="text-xs text-muted-foreground mb-4">Objectif : 3 200 heures d'exercice</p>
        <JaugeProgression valeur={heures} max={3200} marqueurs={[800, 1600, 2400, 3200]} couleurBarre="bg-gradient-to-r from-purple-500 to-purple-600" couleurFond="bg-purple-100" />
        <div className="flex justify-between text-[10px] text-muted-foreground mt-1.5"><span>0h</span><span>800h</span><span>1600h</span><span>2400h</span><span>3200h</span></div>
        <p className="text-sm font-semibold text-foreground mt-3"><span className="text-purple-600">{heures}h</span> / 3 200h</p>
        {soignant.eligible_conversion_3200h && (
          <div className="mt-3 rounded-xl bg-warning/10 border border-warning/20 p-3 text-center">
            <p className="text-sm font-semibold text-warning">🎉 Félicitations ! Vous êtes éligible à l'installation libérale</p>
          </div>
        )}
      </div>

      {modalScore && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center">
          <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={() => setModalScore(false)} />
          <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-sm w-full">
            <button onClick={() => setModalScore(false)} className="absolute top-4 right-4 text-muted-foreground"><X className="h-5 w-5" /></button>
            <h3 className="text-lg font-bold text-foreground mb-4 flex items-center gap-2"><Star className="h-5 w-5 text-primary" /> Score de fiabilité</h3>
            <ul className="space-y-2 text-sm text-foreground">
              <li className="flex gap-2"><span className="text-success">+2 pts</span> par mission terminée</li>
              <li className="flex gap-2"><span className="text-destructive">−8 pts</span> par annulation</li>
              <li className="flex gap-2"><span className="text-destructive">−25 pts</span> par absence</li>
              <li className="flex gap-2"><span className="text-destructive">−3 pts</span> par retard au pointage</li>
              <li className="flex gap-2"><span className="text-success">+10 pts</span> bonus après 20 missions</li>
              <li className="flex gap-2"><span className="text-success">+5 pts</span> si zéro absence (après 5 missions)</li>
              <li className="flex gap-2"><span className="text-success">+3 pts</span> si prévoyance active</li>
            </ul>
            <div className="mt-4 rounded-xl bg-primary/5 border border-primary/20 p-3">
              <p className="text-xs text-primary font-medium">Score ≥ 75 = accès prioritaire aux missions urgentes 🚀</p>
            </div>
          </div>
        </div>
      )}
    </LayoutApp>
  );
}
