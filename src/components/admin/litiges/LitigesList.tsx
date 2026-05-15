import React, { useMemo } from 'react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Badge } from '@/components/ui/badge';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { AlertTriangle, Euro, Eye, Gavel } from 'lucide-react';
import {
  alerteTresorerie,
  CLASSES_BADGE_COULEUR,
  couleurBadgeCategorie,
  joursDepuis,
  LABELS_CATEGORIE,
  LABELS_TYPE_LITIGE,
  rangGravite,
  type FiltresLitiges,
  type LitigeEnrichi,
} from './types';

const formatDateTime = (d?: string | null) =>
  d
    ? new Date(d).toLocaleString('fr-FR', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

const formatStatutLitige = (statut: string) => statut.replace(/_/g, ' ');

const formatMontant = (v: number | null | undefined): string => {
  if (v == null || Number.isNaN(Number(v))) return '—';
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
    maximumFractionDigits: 2,
  }).format(Number(v));
};

export function filtrerEtTrier(
  litiges: LitigeEnrichi[],
  filtres: FiltresLitiges,
): LitigeEnrichi[] {
  const filtres_AND = litiges.filter((l) => {
    if (filtres.type_litige !== 'TOUS' && l.type_litige !== filtres.type_litige)
      return false;
    if (
      filtres.categorie_litige !== 'TOUTES' &&
      l.categorie_litige !== filtres.categorie_litige
    )
      return false;
    if (filtres.statut !== 'TOUS_OUVERTS' && l.statut !== filtres.statut) return false;
    return true;
  });

  const sorted = [...filtres_AND];
  if (filtres.tri === 'TRESORERIE') {
    sorted.sort((a, b) => {
      const ma = Number(a.montant_tresorerie_bloquee ?? 0);
      const mb = Number(b.montant_tresorerie_bloquee ?? 0);
      if (mb !== ma) return mb - ma;
      return rangGravite(a) - rangGravite(b);
    });
  } else if (filtres.tri === 'ESCALADE_MEDIATION') {
    // escalade_auto_le asc (plus ancienne = plus urgente),
    // les litiges sans escalade en fin de liste.
    sorted.sort((a, b) => {
      const ea = a.escalade_auto_le ? new Date(a.escalade_auto_le).getTime() : Infinity;
      const eb = b.escalade_auto_le ? new Date(b.escalade_auto_le).getTime() : Infinity;
      if (ea !== eb) return ea - eb;
      return rangGravite(a) - rangGravite(b);
    });
  } else {
    sorted.sort((a, b) => {
      const ra = rangGravite(a);
      const rb = rangGravite(b);
      if (ra !== rb) return ra - rb;
      return new Date(a.cree_le).getTime() - new Date(b.cree_le).getTime();
    });
  }
  return sorted;
}

type Props = {
  litiges: LitigeEnrichi[];
  filtres: FiltresLitiges;
  onOpenPreuves: (litige: LitigeEnrichi) => void;
  onOpenResolution: (litige: LitigeEnrichi) => void;
  actionEnCoursId?: string | null;
};

export function LitigesList({
  litiges,
  filtres,
  onOpenPreuves,
  onOpenResolution,
  actionEnCoursId,
}: Props) {
  const visible = useMemo(
    () => filtrerEtTrier(litiges, filtres),
    [litiges, filtres],
  );

  if (visible.length === 0) {
    return (
      <p
        className="py-8 text-center text-sm text-muted-foreground"
        data-testid="litiges-empty"
      >
        Aucun litige correspondant aux filtres.
      </p>
    );
  }

  return (
    <div className="space-y-3" data-testid="litiges-list">
      {visible.map((l) => {
        const couleur = couleurBadgeCategorie(l.categorie_litige, l.type_litige);
        const jours = joursDepuis(l.cree_le);
        const alerte = alerteTresorerie(l);
        const informatif = Boolean(l.est_informatif);

        return (
          <CardY2K
            noPadding
            key={l.id}
            data-testid="litige-card"
            data-litige-id={l.id}
            data-gravite={rangGravite(l)}
            data-categorie={l.categorie_litige ?? 'AUTRE'}
          >
            <CardY2KContent className="pt-5">
              <div className="flex items-start gap-3">
                <div
                  className={`mt-1 flex h-10 w-1.5 shrink-0 rounded-full ${
                    couleur === 'rouge'
                      ? 'bg-red-500'
                      : couleur === 'orange'
                      ? 'bg-orange-500'
                      : couleur === 'jaune'
                      ? 'bg-yellow-400'
                      : couleur === 'vert'
                      ? 'bg-green-500'
                      : 'bg-gray-300'
                  }`}
                  aria-hidden
                  data-testid="badge-gravite"
                  data-couleur={couleur}
                />

                <div className="flex-1 space-y-2">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge
                      variant="outline"
                      className={CLASSES_BADGE_COULEUR[couleur]}
                      data-testid="badge-categorie"
                    >
                      {l.categorie_litige
                        ? LABELS_CATEGORIE[l.categorie_litige as keyof typeof LABELS_CATEGORIE] ?? l.categorie_litige
                        : 'Catégorie —'}
                    </Badge>
                    {l.type_litige && (
                      <Badge variant="secondary" className="text-[10px]">
                        {LABELS_TYPE_LITIGE[l.type_litige as keyof typeof LABELS_TYPE_LITIGE] ??
                          l.type_litige}
                      </Badge>
                    )}
                    <Badge
                      variant={
                        l.statut === 'OUVERT'
                          ? 'destructive'
                          : l.statut === 'EN_MEDIATION'
                          ? 'default'
                          : 'secondary'
                      }
                    >
                      {formatStatutLitige(l.statut)}
                    </Badge>
                    {informatif && (
                      <Badge
                        variant="outline"
                        className="bg-gray-100 text-gray-700 border-gray-200"
                        data-testid="badge-informatif"
                      >
                        Informatif
                      </Badge>
                    )}
                  </div>

                  <p className="text-base font-medium text-foreground">{l.motif}</p>

                  <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
                    <span>Ouvert {formatDateTime(l.cree_le)}</span>
                    <span>
                      Initié par{' '}
                      {l.initie_par === 'SOIGNANT' ? 'soignant' : 'établissement'}
                    </span>
                    {l.mission?.intitule && <span>Mission : {l.mission.intitule}</span>}
                  </div>

                  <div
                    className={`inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium ${
                      alerte
                        ? 'bg-red-50 text-red-700 border border-red-200'
                        : 'bg-muted text-muted-foreground'
                    }`}
                    data-testid="tresorerie-cell"
                    data-alerte={alerte ? '1' : '0'}
                  >
                    {alerte && <AlertTriangle className="h-3.5 w-3.5" />}
                    <Euro className="h-3.5 w-3.5" />
                    <span>
                      Trésorerie bloquée : {formatMontant(l.montant_tresorerie_bloquee ?? 0)}
                    </span>
                    <span className="opacity-70">·</span>
                    <span>
                      {jours} j d'ouverture
                      {alerte && ' — seuil dépassé (> 5 j & > 500 €)'}
                    </span>
                  </div>

                  <div className="flex flex-wrap gap-2 pt-1">
                    <BoutonY2K
                      size="sm"
                      variant="secondary"
                      onClick={() => onOpenPreuves(l)}
                      aria-label={`Voir preuves litige ${l.id}`}
                      iconeGauche={<Eye className="h-3.5 w-3.5" />}
                    >
                      Voir preuves
                    </BoutonY2K>
                    {!informatif && (
                      <BoutonY2K
                        size="sm"
                        onClick={() => onOpenResolution(l)}
                        disabled={actionEnCoursId === l.id}
                        loading={actionEnCoursId === l.id}
                        aria-label={`Résoudre litige ${l.id}`}
                        iconeGauche={actionEnCoursId === l.id ? undefined : <Gavel className="h-3.5 w-3.5" />}
                      >
                        {actionEnCoursId === l.id ? 'Résolution…' : 'Résoudre'}
                      </BoutonY2K>
                    )}
                  </div>
                </div>
              </div>
            </CardY2KContent>
          </CardY2K>
        );
      })}
    </div>
  );
}
