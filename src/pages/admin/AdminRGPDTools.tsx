// Sprint 7 PR 7 — Page AdminRGPDTools (P2 §15)
// 2 sections :
// 1. Export JSON des 500 dernières demandes RGPD (suppressions + exports) depuis journaux_audit
// 2. Forcer suppression d'un compte via RPC fn_admin_force_supprimer_compte
//    (à créer Sprint 8 si nécessaire — actuellement renvoie erreur si absente)
// Double confirmation requise ("SUPPRIMER DÉFINITIVEMENT" exact) + motif min 30 chars
// (audit légal).
// Context menu utilisateurs + actions admin missions reportés Sprint 8.

import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import {
  Shield,
  Download,
  AlertTriangle,
  Trash2,
  RefreshCw,
  FileJson,
} from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { telechargerOuPartager } from '@/lib/telechargement';

// Confirmation exacte requise (audit légal RGPD Art. 17)
const CONFIRMATION_PHRASE = 'SUPPRIMER DÉFINITIVEMENT';
const MOTIF_MIN_LENGTH = 30;
const EXPORT_LIMIT = 500;

const ACTIONS_RGPD = ['RGPD_SUPPRESSION_COMPTE', 'RGPD_EXPORT_DONNEES'];

export default function AdminRGPDTools() {
  usePageTitle('Outils RGPD');

  // ── Section 1 : Export demandes RGPD ──
  const [loadingDemandes, setLoadingDemandes] = useState(true);
  const [demandes, setDemandes] = useState<any[]>([]);
  const [exporting, setExporting] = useState(false);

  // ── Section 2 : Forcer suppression compte ──
  const [userIdCible, setUserIdCible] = useState('');
  const [motif, setMotif] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [suppressionEnCours, setSuppressionEnCours] = useState(false);

  const chargerDemandes = async () => {
    setLoadingDemandes(true);
    const { data, error } = await supabase
      .from('journaux_audit')
      .select('*')
      .in('action', ACTIONS_RGPD)
      .order('cree_le', { ascending: false })
      .limit(EXPORT_LIMIT);

    if (error) {
      toast.error('Erreur chargement des demandes RGPD');
      setDemandes([]);
    } else {
      setDemandes(data || []);
    }
    setLoadingDemandes(false);
  };

  useEffect(() => {
    chargerDemandes();
  }, []);

  const handleExportJSON = async () => {
    setExporting(true);
    try {
      const payload = {
        exported_at: new Date().toISOString(),
        nombre_demandes: demandes.length,
        limite: EXPORT_LIMIT,
        demandes: demandes.map((d) => ({
          id: d.id,
          cree_le: d.cree_le,
          action: d.action,
          type_acteur: d.type_acteur,
          acteur_id: d.acteur_id,
          type_ressource: d.type_ressource,
          id_ressource: d.id_ressource,
          details: d.details,
        })),
      };
      await telechargerOuPartager(JSON.stringify(payload, null, 2), `demandes-rgpd-${format(new Date(), 'yyyy-MM-dd-HHmmss')}.json`, 'application/json');
      toast.success(`Export JSON de ${demandes.length} demandes téléchargé`);
    } catch (e: any) {
      toast.error(`Erreur lors de l'export : ${e?.message || 'inconnue'}`);
    } finally {
      setExporting(false);
    }
  };

  const motifValide = motif.trim().length >= MOTIF_MIN_LENGTH;
  const confirmationValide = confirmation === CONFIRMATION_PHRASE;
  const userIdValide = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    userIdCible.trim(),
  );
  const peutSupprimer = motifValide && confirmationValide && userIdValide && !suppressionEnCours;

  const handleForcerSuppression = async () => {
    if (!peutSupprimer) return;
    setSuppressionEnCours(true);
    try {
      // RPC à créer Sprint 8 si nécessaire — actuellement renvoie erreur si absente
      const { data, error } = await (supabase.rpc as any)(
        'fn_admin_force_supprimer_compte',
        {
          p_user_id: userIdCible.trim(),
          p_motif: motif.trim(),
        },
      );
      if (error) {
        // Cas attendu si la RPC n'est pas encore déployée
        if (error.message?.toLowerCase().includes('does not exist') ||
            error.code === '42883' || error.code === 'PGRST202') {
          toast.error(
            'RPC fn_admin_force_supprimer_compte non déployée. À créer Sprint 8.',
          );
        } else {
          toast.error(`Erreur RPC : ${error.message}`);
        }
        return;
      }
      toast.success('Compte supprimé. Action journalisée.');
      setUserIdCible('');
      setMotif('');
      setConfirmation('');
      // Recharger les demandes RGPD pour voir l'audit trail
      chargerDemandes();
    } catch (e: any) {
      toast.error(`Erreur : ${e?.message || 'inconnue'}`);
    } finally {
      setSuppressionEnCours(false);
    }
  };

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Shield className="h-5 w-5 text-primary" /> Outils RGPD
        </h1>
        <p className="text-sm text-muted-foreground">
          Article 17 RGPD (droit à l'effacement) et Article 20 RGPD (portabilité) — actions admin sensibles, audit complet.
        </p>
      </div>

      <div className="space-y-6 max-w-5xl">
        {/* ── Section 1 : Export demandes RGPD ── */}
        <section className="card-base">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-4 gap-3">
            <div>
              <h2 className="text-base font-semibold text-foreground flex items-center gap-2">
                <FileJson className="h-4 w-4 text-primary" /> Export demandes RGPD
              </h2>
              <p className="text-xs text-muted-foreground mt-1">
                {EXPORT_LIMIT} dernières demandes (suppressions + exports) depuis <code>journaux_audit</code>.
              </p>
            </div>
            <div className="flex gap-2">
              <button
                onClick={chargerDemandes}
                disabled={loadingDemandes}
                className="p-2 rounded-lg bg-muted hover:bg-muted/80 disabled:opacity-50"
                aria-label="Recharger"
              >
                <RefreshCw className={`h-4 w-4 text-muted-foreground ${loadingDemandes ? 'animate-spin' : ''}`} />
              </button>
              <button
                onClick={handleExportJSON}
                disabled={exporting || loadingDemandes || demandes.length === 0}
                className="btn-primary inline-flex items-center gap-2 px-4 py-2 text-sm disabled:opacity-50"
              >
                <Download className="h-4 w-4" />
                {exporting ? 'Export…' : `Télécharger JSON (${demandes.length})`}
              </button>
            </div>
          </div>

          {loadingDemandes ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              Chargement des demandes…
            </div>
          ) : demandes.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              Aucune demande RGPD enregistrée.
            </div>
          ) : (
            <>
              {/* Desktop table */}
              <div className="hidden md:block overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border text-left">
                      <th className="py-2 px-3 font-medium text-muted-foreground">Date</th>
                      <th className="py-2 px-3 font-medium text-muted-foreground">Action</th>
                      <th className="py-2 px-3 font-medium text-muted-foreground">Acteur</th>
                      <th className="py-2 px-3 font-medium text-muted-foreground">Ressource</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border/50">
                    {demandes.slice(0, 50).map((d) => (
                      <tr key={d.id} className="hover:bg-muted/30 transition">
                        <td className="py-2 px-3 text-muted-foreground whitespace-nowrap text-xs">
                          {d.cree_le
                            ? format(new Date(d.cree_le), 'dd/MM/yy HH:mm', { locale: fr })
                            : '—'}
                        </td>
                        <td className="py-2 px-3">
                          <span
                            className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                              d.action === 'RGPD_SUPPRESSION_COMPTE'
                                ? 'bg-destructive/10 text-destructive'
                                : 'bg-info/10 text-info'
                            }`}
                          >
                            {d.action}
                          </span>
                        </td>
                        <td className="py-2 px-3 text-xs text-muted-foreground">
                          <span className="font-mono">{d.type_acteur}</span>
                          <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[140px]">
                            {d.acteur_id?.slice(0, 8)}…
                          </p>
                        </td>
                        <td className="py-2 px-3 text-xs text-muted-foreground">
                          <span>{d.type_ressource}</span>
                          {d.id_ressource && (
                            <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[140px]">
                              {d.id_ressource?.slice(0, 8)}…
                            </p>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Mobile cards */}
              <div className="md:hidden space-y-3 mt-2">
                {demandes.slice(0, 50).map((d) => (
                  <div key={d.id} className="card-base space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <span
                        className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold shrink-0 ${
                          d.action === 'RGPD_SUPPRESSION_COMPTE'
                            ? 'bg-destructive/10 text-destructive'
                            : 'bg-info/10 text-info'
                        }`}
                      >
                        {d.action}
                      </span>
                      <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                        {d.cree_le ? format(new Date(d.cree_le), 'dd/MM/yy HH:mm', { locale: fr }) : '—'}
                      </span>
                    </div>
                    <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                      <div>
                        <p className="text-muted-foreground">Acteur</p>
                        <p className="font-mono text-foreground">{d.type_acteur}</p>
                        <p className="text-[10px] text-muted-foreground/60 font-mono">{d.acteur_id?.slice(0, 8)}…</p>
                      </div>
                      <div>
                        <p className="text-muted-foreground">Ressource</p>
                        <p className="text-foreground">{d.type_ressource}</p>
                        {d.id_ressource && (
                          <p className="text-[10px] text-muted-foreground/60 font-mono">{d.id_ressource?.slice(0, 8)}…</p>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              {demandes.length > 50 && (
                <p className="text-xs text-muted-foreground text-center mt-3">
                  Affichage des 50 premières. L'export JSON contient les {demandes.length} demandes.
                </p>
              )}
            </>
          )}
        </section>

        {/* ── Section 2 : Forcer suppression compte ── */}
        <section className="card-base border-destructive/30 bg-destructive/5">
          <div className="mb-4">
            <h2 className="text-base font-semibold text-foreground flex items-center gap-2">
              <Trash2 className="h-4 w-4 text-destructive" /> Forcer suppression d'un compte
            </h2>
            <p className="text-xs text-muted-foreground mt-1">
              Action <strong>irréversible</strong>. À utiliser uniquement sur demande RGPD officielle (Art. 17) après
              vérification d'identité. Audit légal complet dans <code>journaux_audit</code>.
            </p>
          </div>

          <div className="flex items-start gap-2 mb-4 p-3 rounded-lg bg-destructive/10 border border-destructive/20">
            <AlertTriangle className="h-4 w-4 text-destructive mt-0.5 flex-shrink-0" />
            <div className="text-xs text-destructive-foreground">
              <p className="font-semibold text-destructive">Pré-requis avant suppression</p>
              <ul className="list-disc list-inside mt-1 space-y-0.5 text-destructive/90">
                <li>Aucune mission active ou à venir.</li>
                <li>Aucune facture impayée ou en litige.</li>
                <li>Demande écrite ou vérification d'identité documentée.</li>
                <li>Motif détaillé (min. {MOTIF_MIN_LENGTH} caractères) pour traçabilité juridique.</li>
              </ul>
            </div>
          </div>

          <div className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-foreground mb-1">
                ID utilisateur (UUID) <span className="text-destructive">*</span>
              </label>
              <input
                type="text"
                value={userIdCible}
                onChange={(e) => setUserIdCible(e.target.value)}
                placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                className="input-base font-mono text-xs"
                disabled={suppressionEnCours}
              />
              {userIdCible && !userIdValide && (
                <p className="text-xs text-destructive mt-1">Format UUID invalide.</p>
              )}
            </div>

            <div>
              <label className="block text-xs font-semibold text-foreground mb-1">
                Motif RGPD détaillé <span className="text-destructive">*</span>{' '}
                <span className="text-muted-foreground font-normal">
                  ({motif.trim().length}/{MOTIF_MIN_LENGTH} min)
                </span>
              </label>
              <textarea
                value={motif}
                onChange={(e) => setMotif(e.target.value)}
                placeholder="Référence demande, vérification d'identité, contexte légal…"
                rows={3}
                className="input-base text-sm"
                disabled={suppressionEnCours}
              />
              {motif && !motifValide && (
                <p className="text-xs text-destructive mt-1">
                  Motif trop court (min. {MOTIF_MIN_LENGTH} caractères).
                </p>
              )}
            </div>

            <div>
              <label className="block text-xs font-semibold text-foreground mb-1">
                Confirmation <span className="text-destructive">*</span>
              </label>
              <p className="text-xs text-muted-foreground mb-2">
                Saisissez exactement : <code className="font-mono bg-muted/50 px-1.5 py-0.5 rounded">{CONFIRMATION_PHRASE}</code>
              </p>
              <input
                type="text"
                value={confirmation}
                onChange={(e) => setConfirmation(e.target.value)}
                placeholder={CONFIRMATION_PHRASE}
                className="input-base font-mono text-sm"
                disabled={suppressionEnCours}
              />
              {confirmation && !confirmationValide && (
                <p className="text-xs text-destructive mt-1">Confirmation incorrecte.</p>
              )}
            </div>

            <button
              onClick={handleForcerSuppression}
              disabled={!peutSupprimer}
              className="inline-flex items-center gap-2 px-4 py-2 text-sm rounded-lg bg-destructive text-destructive-foreground hover:bg-destructive/90 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Trash2 className="h-4 w-4" />
              {suppressionEnCours ? 'Suppression en cours…' : 'Forcer la suppression définitive'}
            </button>

            <p className="text-[11px] text-muted-foreground">
              Note : la RPC <code>fn_admin_force_supprimer_compte</code> sera créée Sprint 8 si nécessaire. En attendant,
              cette action renvoie une erreur explicite.
            </p>
          </div>
        </section>
      </div>
    </LayoutAdmin>
  );
}
