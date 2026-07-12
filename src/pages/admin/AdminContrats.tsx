import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, FileText, Loader2, CheckCircle2, XCircle } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { FileDeTravail } from '@/components/admin/FileDeTravail';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useDebounce } from '@/hooks/useDebounce';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface ContratLigne {
  id: string;
  numero_contrat: string | null;
  mission_id: string;
  mission_intitule: string;
  soignant_id: string;
  soignant_nom: string;
  etablissement_id: string;
  etablissement_nom: string;
  type_contrat: string;
  statut: string;
  hash_court: string | null;
  signature_soignant: boolean;
  signature_etablissement: boolean;
  signature_soignant_le: string | null;
  signature_etablissement_le: string | null;
  mode_signature: string | null;
  dpae_effectuee: boolean;
  dpae_numero: string | null;
  cree_le: string;
}

const STATUTS_FILTRES = ['Tous', 'EN_ATTENTE_SIGNATURE_SOIGNANT', 'EN_ATTENTE_SIGNATURE_ETAB', 'SIGNE_COMPLET', 'ANNULE', 'EXPIRE'] as const;

/** Libellés français des statuts (les valeurs brutes restent celles envoyées aux RPCs). */
const STATUT_LABEL: Record<string, string> = {
  EN_ATTENTE_SIGNATURE_SOIGNANT: 'En attente signature soignant',
  EN_ATTENTE_SIGNATURE_ETAB: 'En attente signature établissement',
  SIGNE_COMPLET: 'Signé',
  ANNULE: 'Annulé',
  EXPIRE: 'Expiré',
};

const libelleStatut = (s: string) =>
  STATUT_LABEL[s]
  ?? (s?.startsWith('EXPIRE') ? 'Expiré'
    : s?.startsWith('EN_ATTENTE_SIGNATURE') ? 'En attente de signature'
    : s);

const TYPE_CONTRAT_LABEL: Record<string, string> = {
  CDD: 'CDD',
  VACATION: 'CDD court',
  LIBERAL: 'Libéral',
  SALARIE: 'Salarié',
};

const libelleTypeContrat = (t: string) => TYPE_CONTRAT_LABEL[t] ?? t;

/** Contrat soumis à DPAE (CDD/Salarié), signé, mais sans numéro DPAE enregistré : obligation légale à traiter. */
const estDpaeManquante = (c: ContratLigne) =>
  c.statut === 'SIGNE_COMPLET' &&
  (c.type_contrat?.startsWith('CDD') || c.type_contrat === 'SALARIE') &&
  !(c.dpae_effectuee && c.dpae_numero);

const PAR_PAGE = 50;

export default function AdminContrats() {
  usePageTitle('Admin · Contrats');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [contrats, setContrats] = useState<ContratLigne[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [filtreStatut, setFiltreStatut] = useState<string>('Tous');
  const [recherche, setRecherche] = useState('');
  const rechercheDeb = useDebounce(recherche, 400);

  // Task 9 — valider/refuser contrat établissement
  const [validerModal, setValiderModal] = useState<{ etabId: string; valider: boolean } | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_contrats' as any, {
      p_filtre_statut: filtreStatut === 'Tous' ? null : filtreStatut,
      p_recherche: rechercheDeb.trim() || null,
      p_limit: PAR_PAGE,
      p_offset: page * PAR_PAGE,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      setLoading(false);
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: result?.error || 'Erreur.' });
      setLoading(false);
      return;
    }
    setContrats(result.contrats as ContratLigne[]);
    setTotal(result.total as number);
    setLoading(false);
  }

  useEffect(() => { charger(); }, [filtreStatut, rechercheDeb, page]);

  // File de travail (Session D) :
  // À traiter = signatures en attente (plus anciens d'abord), puis CDD/Salarié signés sans numéro DPAE.
  // Historique = signés complets (DPAE ok ou non concernés), annulés, expirés — plus récents d'abord.
  const { aTraiter, historique } = useMemo(() => {
    const parAnciennete = (a: ContratLigne, b: ContratLigne) => (a.cree_le || '').localeCompare(b.cree_le || '');
    const enAttenteSignature = contrats
      .filter((c) => c.statut?.startsWith('EN_ATTENTE_SIGNATURE'))
      .sort(parAnciennete);
    const dpaeManquante = contrats.filter(estDpaeManquante).sort(parAnciennete);
    const file = [...enAttenteSignature, ...dpaeManquante];
    const idsFile = new Set(file.map((c) => c.id));
    const clos = contrats
      .filter((c) => !idsFile.has(c.id))
      .sort((a, b) => (b.cree_le || '').localeCompare(a.cree_le || ''));
    return { aTraiter: file, historique: clos };
  }, [contrats]);

  // Task 9
  const validerContratEtablissement = async () => {
    if (!validerModal) return;
    const { data, error } = await supabase.rpc('fn_admin_valider_contrat_etablissement' as any, {
      p_etablissement_id: validerModal.etabId,
      p_valider: validerModal.valider,
    });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || error?.message || 'Erreur.');
      setValiderModal(null);
      return;
    }
    toast.success(validerModal.valider ? 'Contrat validé' : 'Contrat refusé');
    setValiderModal(null);
    charger();
  };

  if (loading && contrats.length === 0) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const totalPages = Math.ceil(total / PAR_PAGE);

  const colonnes: ColonneTableau<ContratLigne>[] = [
    { cle: 'numero', titre: 'N° / Mission' },
    { cle: 'soignant', titre: 'Soignant' },
    { cle: 'etab', titre: 'Établissement' },
    { cle: 'type', titre: 'Type' },
    { cle: 'statut', titre: 'Statut' },
    { cle: 'hash', titre: 'Hash' },
    { cle: 'signe', titre: 'Signé le' },
    { cle: 'dpae', titre: 'DPAE' },
    { cle: 'actions', titre: '', align: 'right' },
  ];

  const statutBadge = (c: ContratLigne) => (
    <span className="inline-flex flex-wrap items-center gap-1">
      <span className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
        c.statut === 'SIGNE_COMPLET' ? 'bg-success/20 text-success' :
        c.statut === 'ANNULE' ? 'bg-destructive/20 text-destructive' :
        c.statut?.startsWith('EXPIRE') ? 'bg-muted text-muted-foreground' :
        'bg-warning/20 text-warning'
      }`}>
        {libelleStatut(c.statut)}
      </span>
      {estDpaeManquante(c) && (
        <span className="text-[11px] px-2 py-0.5 rounded-full font-medium bg-destructive/20 text-destructive">
          DPAE manquante
        </span>
      )}
    </span>
  );

  const dpaeBadge = (c: ContratLigne) =>
    c.dpae_effectuee && c.dpae_numero ? (
      <span className="text-success text-xs">Validée · {c.dpae_numero.slice(0, 8)}…</span>
    ) : c.type_contrat?.startsWith('CDD') || c.type_contrat === 'SALARIE' ? (
      <span className="text-warning text-xs">⏳ À déclarer</span>
    ) : <span className="text-muted-foreground text-xs">Non requise</span>;

  const dateSigne = (c: ContratLigne) =>
    c.signature_soignant_le && c.signature_etablissement_le
      ? format(new Date(Math.max(new Date(c.signature_soignant_le).getTime(), new Date(c.signature_etablissement_le).getTime())), 'dd MMM yyyy', { locale: fr })
      : '—';

  const listeContrats = (donnees: ContratLigne[]) => (
    <TableOuCartes
      colonnes={colonnes}
      donnees={donnees}
      getId={(c) => c.id}
      onClickLigne={(c) => navigate(`/admin/contrats/${c.id}`)}
      renduCellule={(c, col) => {
        switch (col.cle) {
          case 'numero':
            return (
              <div>
                <p className="font-mono text-xs">{c.numero_contrat || '—'}</p>
                <p className="text-[11px] text-muted-foreground truncate max-w-[200px]">{c.mission_intitule}</p>
              </div>
            );
          case 'soignant':
            return <span className="text-xs">{c.soignant_nom}</span>;
          case 'etab':
            return <span className="text-xs">{c.etablissement_nom}</span>;
          case 'type':
            return <span className="text-xs">{libelleTypeContrat(c.type_contrat)}</span>;
          case 'statut':
            return statutBadge(c);
          case 'hash':
            return <span className="text-xs font-mono text-muted-foreground">{c.hash_court || '—'}</span>;
          case 'signe':
            return <span className="text-[11px]">{dateSigne(c)}</span>;
          case 'dpae':
            return dpaeBadge(c);
          case 'actions':
            return (
              <div className="flex items-center gap-1 justify-end" onClick={(e) => e.stopPropagation()}>
                {c.statut !== 'SIGNE_COMPLET' && c.etablissement_id && (
                  <>
                    <BoutonY2K size="sm" variant="secondary" onClick={() => setValiderModal({ etabId: c.etablissement_id, valider: true })} iconeGauche={<CheckCircle2 className="h-3.5 w-3.5" />}>
                      Valider
                    </BoutonY2K>
                    <BoutonY2K size="sm" variant="destructive" onClick={() => setValiderModal({ etabId: c.etablissement_id, valider: false })} iconeGauche={<XCircle className="h-3.5 w-3.5" />}>
                      Refuser
                    </BoutonY2K>
                  </>
                )}
                <button
                  onClick={() => navigate(`/admin/contrats/${c.id}`)}
                  className="btn-secondary text-xs py-1 px-3"
                >
                  Voir
                </button>
              </div>
            );
          default:
            return null;
        }
      }}
      renduCarte={(c) => (
        <div className="space-y-2">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-mono text-xs text-foreground">{c.numero_contrat || '—'}</p>
              <p className="text-sm text-foreground truncate">{c.mission_intitule}</p>
            </div>
            {statutBadge(c)}
          </div>
          <div className="text-xs text-muted-foreground space-y-0.5">
            <p>Soignant : {c.soignant_nom}</p>
            <p>Établissement : {c.etablissement_nom}</p>
            <p className="flex items-center gap-2">
              <span>{libelleTypeContrat(c.type_contrat)}</span>
              {c.hash_court && <span className="font-mono">#{c.hash_court}</span>}
            </p>
            <p className="flex items-center gap-2">
              <span>Signé : {dateSigne(c)}</span>
              <span>DPAE : {dpaeBadge(c)}</span>
            </p>
          </div>
        </div>
      )}
    />
  );

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <FileText className="h-6 w-6 text-primary" /> Contrats
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Consultation de tous les contrats Jolene avec hash SHA-256 + certificat + audit trail.
        </p>
      </div>

      {/* Filtres */}
      <div className="flex flex-col sm:flex-row gap-2 mb-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <input
            type="text"
            value={recherche}
            onChange={(e) => { setRecherche(e.target.value); setPage(0); }}
            placeholder="Numéro, mission, soignant, étab…"
            className="input-base pl-9"
          />
        </div>
        <select
          value={filtreStatut}
          onChange={(e) => { setFiltreStatut(e.target.value); setPage(0); }}
          className="input-base sm:w-64"
        >
          {STATUTS_FILTRES.map((s) => (
            <option key={s} value={s}>{s === 'Tous' ? 'Tous statuts' : libelleStatut(s)}</option>
          ))}
        </select>
      </div>

      <p className="text-xs text-muted-foreground mb-2">{total} contrat{total > 1 ? 's' : ''} {loading && <Loader2 className="inline h-3 w-3 animate-spin" />}</p>

      {/* File de travail : signatures en attente + DPAE manquantes d'abord, le reste en historique replié */}
      {contrats.length === 0 ? (
        <EmptyState titre="Aucun contrat" description="Aucun contrat ne correspond à ces critères." />
      ) : (
        <FileDeTravail
          nbATraiter={aTraiter.length}
          aTraiter={listeContrats(aTraiter)}
          nbHistorique={historique.length}
          historique={listeContrats(historique)}
          labelATraiter="À traiter (signatures en attente, DPAE manquantes)"
          labelHistorique="Historique (signés, annulés, expirés)"
          titreVide="Aucun contrat à traiter"
          descriptionVide="Aucune signature en attente ni DPAE manquante sur cette page."
          iconeVide={<FileText />}
        />
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between mt-4">
          <p className="text-xs text-muted-foreground">Page {page + 1} / {totalPages}</p>
          <div className="flex gap-2">
            <button onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0} className="btn-secondary text-xs disabled:opacity-50">Précédent</button>
            <button onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1} className="btn-secondary text-xs disabled:opacity-50">Suivant</button>
          </div>
        </div>
      )}

      {/* Task 9 — Modal valider/refuser contrat établissement */}
      {validerModal && (
        <ModalConfirmation
          ouvert={!!validerModal}
          onFermer={() => setValiderModal(null)}
          onConfirmer={validerContratEtablissement}
          titre={validerModal.valider ? 'Valider le contrat' : 'Refuser le contrat'}
          message={validerModal.valider
            ? 'Valider le contrat de cet établissement ? Il pourra publier des missions.'
            : 'Refuser le contrat de cet établissement ? Il sera notifié.'}
          labelConfirmer={validerModal.valider ? 'Valider' : 'Refuser'}
          variante={validerModal.valider ? 'primaire' : 'danger'}
        />
      )}
    </LayoutAdmin>
  );
}
