import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Calendar, Clock, Banknote, User, Copy, XCircle, RotateCcw, Bell, AlertTriangle, Star, Siren } from 'lucide-react';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { getLabelProfession, extraireContratPreference, getContratBadge } from '@/lib/constantes';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

/** Nouvelles dates choisies lors d'une republication (F3). */
export interface RepublierDates {
  debut: string;
  fin: string;
}

interface CarteMissionProps {
  mission: any;
  afficherEtablissement?: boolean;
  onDupliquer?: (mission: any) => void;
  onAnnuler?: (mission: any) => void;
  /**
   * Republier la mission. Le second argument `dates` (optionnel) porte les nouvelles
   * dates choisies dans la bottom-sheet « Republier » (Session F — F3). Les appelants
   * historiques qui ignorent ce paramètre restent compatibles.
   */
  onRepublier?: (mission: any, dates?: RepublierDates) => void;
}

function formatMontant(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function tempsDepuis(dateStr: string): { texte: string; couleur: string; jours: number } {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 60) return { texte: `Il y a ${minutes} min`, couleur: 'text-success', jours: 0 };
  const heures = Math.floor(minutes / 60);
  if (heures < 24) return { texte: `Il y a ${heures}h`, couleur: 'text-warning', jours: 0 };
  const jours = Math.floor(heures / 24);
  return { texte: `Il y a ${jours} jour${jours > 1 ? 's' : ''}`, couleur: 'text-destructive', jours };
}

function scoreColor(score: number): string {
  if (score >= 70) return 'text-success';
  if (score >= 40) return 'text-warning';
  return 'text-destructive';
}

export const CarteMission = React.memo(function CarteMission({ mission, afficherEtablissement, onDupliquer, onAnnuler, onRepublier }: CarteMissionProps) {
  const navigate = useNavigate();
  const m = mission;
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  const duree = m.duree_heures ?? ((fin.getTime() - debut.getTime()) / 3600000);
  const heureDebut = format(debut, 'HH:mm');
  const heureFin = format(fin, 'HH:mm');
  const dateFormatee = format(debut, 'EEEE d MMMM yyyy', { locale: fr });
  // Lot 11 : l'ancienneté seule n'est pas un signal — le rouge est réservé au
  // cas actionnable « ouverte, ancienne ET sans candidature ». Sinon, neutre.
  const anciennete = m.statut === 'OUVERTE' ? tempsDepuis(m.cree_le) : null;
  const sansCandidatureDepuis = anciennete && anciennete.jours >= 2 && (m.nb_candidatures_attente ?? 0) === 0
    ? anciennete.jours : null;
  const tempsInfo = anciennete && sansCandidatureDepuis == null
    ? { texte: `Publiée ${anciennete.texte.toLowerCase()}`, couleur: 'text-muted-foreground' }
    : null;
  // Mission multi-jours : « 8 h/jour · 120 h au total » est lisible là où
  // « 13:00 → 21:00 (120h) » ne l'est pas.
  const nbJoursMission = Math.max(1, Math.round((fin.getTime() - debut.getTime()) / 86400000));
  const estMultiJours = duree > 24 && nbJoursMission > 1;
  const heuresParJour = estMultiJours ? Math.round((duree / nbJoursMission) * 10) / 10 : 0;
  const estAnnulee = m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT';
  const estTerminee = m.statut === 'TERMINEE';
  // F3 — « Republier » disponible sur les missions passées : annulées ET terminées.
  const peutRepublier = !!onRepublier && (estAnnulee || estTerminee);
  const contratPref = m.type_contrat_recherche || extraireContratPreference(m.description);
  const contratBadge = getContratBadge(contratPref);

  // F4 — candidatures en attente à traiter (count agrégé côté ListeMissions).
  const nbCandidatures: number = m.nb_candidatures_attente ?? 0;
  const afficheCandidatures = m.statut === 'OUVERTE' && nbCandidatures > 0;
  const derniereCandidatureLe: string | null = m.derniere_candidature_le ?? null;
  const tempsCandidature = afficheCandidatures && derniereCandidatureLe ? tempsDepuis(derniereCandidatureLe) : null;

  const couleurTheme = m.etablissements?.couleur_theme || m.couleur_theme;

  // F3 — bottom-sheet « Republier cette mission » avec nouvelles dates.
  const [republierOuvert, setRepublierOuvert] = useState(false);
  const [republierDebut, setRepublierDebut] = useState('');
  const [republierFin, setRepublierFin] = useState('');

  const ouvrirRepublier = () => {
    setRepublierDebut('');
    setRepublierFin('');
    setRepublierOuvert(true);
  };

  const datesRepublierValides = !!republierDebut && !!republierFin && new Date(republierFin) > new Date(republierDebut);

  const confirmerRepublier = () => {
    if (!onRepublier) return;
    if (republierDebut && republierFin && datesRepublierValides) {
      onRepublier(m, {
        debut: new Date(republierDebut).toISOString(),
        fin: new Date(republierFin).toISOString(),
      });
    } else {
      // Aucune nouvelle date saisie : republication simple (l'établissement ajuste après).
      onRepublier(m);
    }
    setRepublierOuvert(false);
  };

  return (
    <div
      className="card-base hover:shadow-md transition-shadow cursor-pointer overflow-hidden"
      onClick={() => navigate(`/etablissement/missions/${m.id}`)}
    >
      {couleurTheme && <div className="h-1 -mt-4 md:-mt-6 -mx-4 md:-mx-6 mb-3" style={{ backgroundColor: couleurTheme }} />}
      <div className="flex items-start justify-between mb-2">
        <div className="flex items-center gap-2 flex-wrap">
           {m.est_urgente && (
            <span className="badge-base bg-destructive/10 text-destructive text-[10px] inline-flex items-center gap-1" aria-label={`Urgence niveau ${m.niveau_urgence === 3 ? 'critique' : m.niveau_urgence === 2 ? 'élevé' : 'standard'}`}>
              <Siren aria-hidden="true" className="h-3 w-3" />
              {m.niveau_urgence === 3 ? 'URGENT · critique' : m.niveau_urgence === 2 ? 'URGENT · élevé' : 'URGENT'}
            </span>
          )}
          <BadgeStatut statut={m.statut} />
          {m.has_litige && (
            <span className="badge-base bg-warning/10 text-warning text-[10px] inline-flex items-center gap-1"><AlertTriangle aria-hidden="true" className="h-3 w-3" />Litige</span>
          )}
          {/* F4 — candidatures en attente à traiter */}
          {afficheCandidatures && (
            <BadgeY2K variant="warning" size="sm" icone={<Bell className="h-3 w-3" />}>
              {nbCandidatures} candidature{nbCandidatures > 1 ? 's' : ''} à traiter
            </BadgeY2K>
          )}
          {tempsInfo && (
            <span className={`text-[10px] font-medium ${tempsInfo.couleur}`}>{tempsInfo.texte}</span>
          )}
        </div>
      </div>

      {/* Signal actionnable : ouverte, ancienne, zéro candidature → suggérer un levier */}
      {sansCandidatureDepuis != null && (
        <p className="text-[10px] font-medium text-destructive mb-2 flex items-center gap-1">
          <AlertTriangle aria-hidden="true" className="h-3 w-3 shrink-0" />
          Aucune candidature depuis {sansCandidatureDepuis} j — essayez d'ajuster le taux ou de passer la mission en urgente.
        </p>
      )}

      <h3 className="font-semibold text-sm text-foreground mb-1">{m.intitule}</h3>
      <p className="text-xs text-muted-foreground mb-2">
        {m.service && `${m.service} · `}{getLabelProfession(m.profession_requise)}
        <span className={`badge-base text-[10px] ml-2 ${contratBadge.classes}`}>{contratBadge.label}</span>
      </p>

      {/* F4 — ancienneté de la dernière candidature reçue */}
      {tempsCandidature && (
        <p className={`text-[10px] font-medium mb-2 ${tempsCandidature.couleur}`}>
          Dernière candidature reçue {tempsCandidature.texte.toLowerCase()}
        </p>
      )}

      <div className="flex items-center gap-4 text-xs text-muted-foreground mb-2">
        <span className="flex items-center gap-1"><Calendar className="h-3.5 w-3.5" />{dateFormatee}</span>
      </div>
      <div className="flex items-center gap-4 text-xs text-muted-foreground mb-3">
        <span className="flex items-center gap-1">
          <Clock className="h-3.5 w-3.5" />
          {estMultiJours
            ? `${heuresParJour} h/jour · ${Math.round(duree * 10) / 10} h au total`
            : `${heureDebut} → ${heureFin} (${Math.round(duree * 10) / 10}h)`}
        </span>
      </div>

      <div className="flex items-center gap-2 text-xs mb-2">
        <Banknote className="h-3.5 w-3.5 text-primary" />
        <span className="text-foreground font-medium">{m.taux_horaire_base?.toFixed(2)} €/h</span>
        {(m.net_estime ?? m.net_a_payer ?? 0) > 0 && (
          <span className="text-muted-foreground">→ Net estimé soignant (indicatif) : <strong className="text-primary">{formatMontant(m.net_estime ?? (m.net_a_payer != null ? m.net_a_payer * 0.78 : null))}</strong></span>
        )}
      </div>
      {m.rist_plafond_applique && (
        <p className="text-[10px] text-warning font-medium mb-2 flex items-center gap-1"><AlertTriangle aria-hidden="true" className="h-3 w-3 shrink-0" />Taux plafonné Loi Rist</p>
      )}

      <div className="flex items-center gap-2 text-xs text-muted-foreground mb-3">
        {m.soignants ? (
          <>
            <AvatarDisplay
              src={m.soignants.avatar_url}
              prenom={m.soignants.prenom}
              nom={m.soignants.nom}
              size={24}
            />
            <span>
              {m.soignants.prenom} {m.soignants.nom}
              {m.soignants.score_fiabilite != null && m.soignants.total_missions_terminees >= 3 ? (
                <span className={`ml-1 font-semibold inline-flex items-center gap-0.5 ${scoreColor(m.soignants.score_fiabilite)}`}>
                  (<Star aria-hidden="true" className="h-3 w-3" />{m.soignants.score_fiabilite}/100)
                </span>
              ) : estTerminee ? (
                /* Lot 11 : au lieu d'un constat passif, le CTA contextuel */
                <button
                  onClick={(e) => { e.stopPropagation(); navigate(`/etablissement/missions/${m.id}`); }}
                  className="ml-1 text-primary font-medium hover:underline"
                >
                  Évaluer ce soignant
                </button>
              ) : (
                <span className="ml-1 text-muted-foreground">(nouveau sur Jolene)</span>
              )}
            </span>
          </>
        ) : (
          <>
            <User className="h-3.5 w-3.5" />
            <span className="italic">— En attente d'un soignant</span>
          </>
        )}
      </div>

      {/* Mission passée : « Republier » devient l'action primaire proéminente
          (re-pourvoir un besoin récurrent = nouvelle mission en 1 tap). */}
      {peutRepublier && (
        <div className="mt-3" onClick={(e) => e.stopPropagation()}>
          <BoutonY2K variant="primary" size="sm" onClick={ouvrirRepublier} iconeGauche={<RotateCcw className="h-4 w-4" />} className="w-full sm:w-auto">
            Republier cette mission
          </BoutonY2K>
          {/* Lot 11 : Republier ≠ Dupliquer — sous-textes explicites */}
          <p className="text-[10px] text-muted-foreground mt-1">Mêmes paramètres, nouvelles dates — publiée directement.</p>
        </div>
      )}

      <div className="flex gap-3 mt-2 flex-wrap items-center min-h-[44px]" onClick={(e) => e.stopPropagation()}>
        <button
          onClick={() => navigate(`/etablissement/missions/${m.id}`)}
          className="text-xs font-medium text-primary hover:underline py-2"
        >
          Voir détail
        </button>
        {onDupliquer && (
          <button onClick={() => onDupliquer(m)} title="Crée un brouillon éditable à partir de cette mission" className="text-xs font-medium text-muted-foreground hover:text-foreground flex items-center gap-1 py-2">
            <Copy className="h-3 w-3" aria-hidden="true" /> Dupliquer <span className="hidden sm:inline text-muted-foreground/70">(brouillon éditable)</span>
          </button>
        )}
        {onAnnuler && (m.statut === 'OUVERTE' || m.statut === 'ASSIGNEE') && (
          /* Lot 11 : action destructive séparée du groupe (ml-auto) — la
             confirmation vit dans la modale du parent. */
          <button onClick={() => onAnnuler(m)} className="text-xs font-medium text-destructive hover:underline flex items-center gap-1 py-2 ml-auto">
            <XCircle className="h-3 w-3" aria-hidden="true" /> Annuler
          </button>
        )}
      </div>

      {/* F3 — bottom-sheet « Republier cette mission » */}
      {peutRepublier && (
        <DialogResponsive open={republierOuvert} onOpenChange={setRepublierOuvert}>
          <DialogResponsiveContent
            maxWidth="md"
            onClick={(e) => e.stopPropagation()}
            onOpenAutoFocus={(e) => e.preventDefault()}
          >
            <DialogResponsiveHeader>
              <DialogResponsiveTitle>Republier cette mission</DialogResponsiveTitle>
              <DialogResponsiveDescription>
                Une nouvelle mission sera créée à partir de « {m.intitule} ». Choisissez de nouvelles dates.
              </DialogResponsiveDescription>
            </DialogResponsiveHeader>

            <DialogResponsiveBody className="space-y-4">
              {/* Récapitulatif (lecture seule) des paramètres conservés */}
              <div className="rounded-2xl border border-border bg-muted/30 p-3 text-sm space-y-1.5">
                <p className="font-semibold text-foreground">{m.intitule}</p>
                <p className="text-muted-foreground">
                  {m.service && `${m.service} · `}{getLabelProfession(m.profession_requise)}
                </p>
                <p className="text-muted-foreground flex items-center gap-1">
                  <Banknote className="h-3.5 w-3.5 text-primary" />
                  {m.taux_horaire_base?.toFixed(2)} €/h brut
                </p>
                <p className="text-muted-foreground flex items-center gap-1">
                  <Clock className="h-3.5 w-3.5" />
                  Durée d'origine : {Math.round(duree * 10) / 10}h
                </p>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label htmlFor={`republier-debut-${m.id}`} className="text-xs text-muted-foreground mb-1 block">
                    Nouvelle date et heure de début *
                  </label>
                  <input
                    id={`republier-debut-${m.id}`}
                    type="datetime-local"
                    value={republierDebut}
                    min={format(new Date(), "yyyy-MM-dd'T'HH:mm")}
                    onChange={(e) => setRepublierDebut(e.target.value)}
                    className="input-base"
                  />
                </div>
                <div>
                  <label htmlFor={`republier-fin-${m.id}`} className="text-xs text-muted-foreground mb-1 block">
                    Nouvelle date et heure de fin *
                  </label>
                  <input
                    id={`republier-fin-${m.id}`}
                    type="datetime-local"
                    value={republierFin}
                    min={republierDebut || format(new Date(), "yyyy-MM-dd'T'HH:mm")}
                    onChange={(e) => setRepublierFin(e.target.value)}
                    className="input-base"
                  />
                </div>
              </div>

              {republierDebut && republierFin && !datesRepublierValides && (
                <p className="text-xs text-destructive font-medium">La fin doit être après le début.</p>
              )}
              <p className="text-[10px] text-muted-foreground">
                Vous pourrez ajuster tous les détails sur la page de création avant de publier.
              </p>
            </DialogResponsiveBody>

            <DialogResponsiveFooter>
              <BoutonY2K variant="secondary" onClick={() => setRepublierOuvert(false)}>
                Annuler
              </BoutonY2K>
              <BoutonY2K
                variant="primary"
                onClick={confirmerRepublier}
                disabled={!!republierDebut && !!republierFin && !datesRepublierValides}
                iconeGauche={<RotateCcw className="h-4 w-4" />}
              >
                Republier
              </BoutonY2K>
            </DialogResponsiveFooter>
          </DialogResponsiveContent>
        </DialogResponsive>
      )}
    </div>
  );
});
