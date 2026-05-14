/**
 * `<TableOuCartes />` Sprint 8 BIS PR 1 (chantier 2.1).
 *
 * Wrapper qui rend un tableau classique sur desktop et des cartes empilées sur mobile.
 *
 * Usage minimal :
 *   <TableOuCartes
 *     colonnes={[
 *       { cle: 'numero', titre: 'N° facture' },
 *       { cle: 'date', titre: 'Date' },
 *       { cle: 'montant', titre: 'Montant', align: 'right' },
 *       { cle: 'statut', titre: 'Statut' },
 *     ]}
 *     donnees={factures}
 *     getId={(f) => f.id}
 *     renduCellule={(f, col) => f[col.cle]}
 *     renduCarte={(f) => (
 *       <div className="space-y-1">
 *         <div className="flex justify-between"><span>{f.numero}</span><Badge>{f.statut}</Badge></div>
 *         <p className="text-sm">{f.date} — {f.montant}</p>
 *       </div>
 *     )}
 *   />
 */
import { ReactNode, memo } from 'react';
import { useViewport } from '@/hooks/useViewport';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';

export type ColonneTableau<T> = {
  cle: string;
  titre: string;
  align?: 'left' | 'right' | 'center';
  className?: string;
  /** Largeur HTML (ex: "w-24") */
  largeur?: string;
};

type Props<T> = {
  colonnes: ColonneTableau<T>[];
  donnees: T[];
  /** Extracteur d'identifiant unique pour key React */
  getId: (item: T) => string;
  /** Rendu d'une cellule pour une ligne donnée (desktop uniquement) */
  renduCellule: (item: T, colonne: ColonneTableau<T>) => ReactNode;
  /** Rendu d'une carte mobile (obligatoire pour mobile-first) */
  renduCarte: (item: T) => ReactNode;
  /** Handler optionnel au clic sur une ligne / carte */
  onClickLigne?: (item: T) => void;
  /** Composant à afficher si donnees est vide (EmptyState typiquement) */
  etatVide?: ReactNode;
  /** Classes additionnelles sur le wrapper */
  className?: string;
};

/**
 * Sprint 8 ter-G PR 5 — mémoïsé via React.memo (shallow equality).
 * Évite les re-renders quand le parent ne change ni `donnees` ni `colonnes`.
 * Bénéfice CPU sur pages avec listes > 30 items (FacturationEtablissement, AdminUtilisateurs…).
 * Note : `as typeof TableOuCartesImpl` préserve la signature générique perdue par React.memo.
 */
function TableOuCartesImpl<T>({
  colonnes,
  donnees,
  getId,
  renduCellule,
  renduCarte,
  onClickLigne,
  etatVide,
  className,
}: Props<T>) {
  const { estMobile } = useViewport();

  if (donnees.length === 0 && etatVide) {
    return <div className={className}>{etatVide}</div>;
  }

  if (estMobile) {
    return (
      <div
        className={cn('space-y-3', className)}
        role="list"
        aria-label="Liste"
      >
        {donnees.map((item) => (
          <div
            key={getId(item)}
            role="listitem"
            onClick={onClickLigne ? () => onClickLigne(item) : undefined}
            className={cn(
              'card-base p-4',
              onClickLigne && 'cursor-pointer hover:bg-muted/50 transition-colors min-h-[44px]',
            )}
          >
            {renduCarte(item)}
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className={cn('rounded-lg border overflow-x-auto', className)}>
      <Table>
        <TableHeader>
          <TableRow>
            {colonnes.map((col) => (
              <TableHead
                key={col.cle}
                className={cn(
                  col.align === 'right' && 'text-right',
                  col.align === 'center' && 'text-center',
                  col.largeur,
                  col.className,
                )}
              >
                {col.titre}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {donnees.map((item) => (
            <TableRow
              key={getId(item)}
              onClick={onClickLigne ? () => onClickLigne(item) : undefined}
              className={cn(
                onClickLigne && 'cursor-pointer hover:bg-muted/50 transition-colors',
              )}
            >
              {colonnes.map((col) => (
                <TableCell
                  key={col.cle}
                  className={cn(
                    col.align === 'right' && 'text-right',
                    col.align === 'center' && 'text-center',
                  )}
                >
                  {renduCellule(item, col)}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

export const TableOuCartes = memo(TableOuCartesImpl) as typeof TableOuCartesImpl;
export default TableOuCartes;
