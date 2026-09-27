/**
 * FiltresSauvegardes — sidebar + modal pour sauvegarder/charger les filtres de
 * recherche (missions côté soignant, soignants côté étab) avec alertes email.
 *
 * Utilisé par RechercheMissions (audience SOIGNANT_RECHERCHE_MISSIONS) et plus
 * tard par la page recherche soignants côté étab (audience ETAB_RECHERCHE_SOIGNANTS).
 *
 * J2.3.C.1
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Bell, BellOff, Save, Trash2, Edit2, Search } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import { logger } from '@/lib/logger';

export type FiltreAudience = 'SOIGNANT_RECHERCHE_MISSIONS' | 'ETAB_RECHERCHE_SOIGNANTS';
export type FrequenceAlerte = 'IMMEDIATE' | 'QUOTIDIENNE' | 'HEBDOMADAIRE';

export interface FiltreSauvegarde {
  id: string;
  nom: string;
  audience: FiltreAudience;
  filtres: Record<string, unknown>;
  alerte_active: boolean;
  frequence_alerte: FrequenceAlerte;
  dernier_check_le: string;
  nb_resultats_dernier_check: number;
  cree_le: string;
  mis_a_jour_le: string;
}

interface Props {
  audience: FiltreAudience;
  /** Filtres courants à sauvegarder lorsque l'utilisateur clique "Sauvegarder" */
  filtresCourants: Record<string, unknown>;
  /** Callback déclenché lorsqu'un filtre est cliqué dans la liste (réapplique). */
  onCharger: (filtres: Record<string, unknown>) => void;
  /** Masque la création/modification d'alertes lorsque leur moteur ne couvre pas tous les critères. */
  alertesDisponibles?: boolean;
}

const FREQUENCE_LABELS: Record<FrequenceAlerte, string> = {
  IMMEDIATE: 'Toutes les heures',
  QUOTIDIENNE: 'Quotidien (au moins 24 h entre vérifications)',
  HEBDOMADAIRE: 'Hebdomadaire (au moins 7 jours entre vérifications)',
};

export function FiltresSauvegardes({ audience, filtresCourants, onCharger, alertesDisponibles = true }: Props) {
  const [list, setList] = useState<FiltreSauvegarde[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurListe, setErreurListe] = useState(false);
  const [saveOpen, setSaveOpen] = useState(false);
  const [editing, setEditing] = useState<FiltreSauvegarde | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    setErreurListe(false);
    try {
      const { data, error } = await supabase.rpc('fn_lister_mes_filtres_sauvegardes', { p_audience: audience });
      if (error || !Array.isArray(data)) throw error || new Error('Réponse de recherches invalide');
      setList(data as unknown as FiltreSauvegarde[]);
    } catch (error) {
      logger.error('[RecherchesSauvegardees] lister error', error);
      setErreurListe(true);
      toast.error('Impossible de charger vos recherches sauvegardées');
    } finally {
      setLoading(false);
    }
  }, [audience]);

  useEffect(() => { void reload(); }, [reload]);

  const handleDelete = async (f: FiltreSauvegarde) => {
    if (!confirm(`Supprimer la recherche « ${f.nom} » ?`)) return;
    const { data, error } = await supabase.rpc('fn_supprimer_filtre_sauvegarde', { p_id: f.id });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur suppression');
      return;
    }
    toast.success('Recherche supprimée');
    reload();
  };

  const handleToggleAlerte = async (f: FiltreSauvegarde) => {
    const { data, error } = await supabase.rpc('fn_modifier_filtre_sauvegarde', {
      p_id: f.id, p_alerte_active: !f.alerte_active,
    });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur mise à jour');
      return;
    }
    toast.success(!f.alerte_active ? 'Alerte activée' : 'Alerte désactivée');
    reload();
  };

  // §7.4 Lot 7a — tant qu'il n'y a rien à afficher, pas de carte pleine avec
  // paragraphe explicatif : une simple ligne compacte (icône + action).
  if (!loading && !erreurListe && list.length === 0) {
    return (
      <>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="text-xs text-muted-foreground flex items-center gap-1.5 min-w-0">
            <Search className="h-3.5 w-3.5 shrink-0" /> Recherches sauvegardées
          </span>
          <BoutonY2K size="sm" variant="ghost" onClick={() => setSaveOpen(true)} iconeGauche={<Save className="h-4 w-4" />}>
            Sauvegarder cette recherche
          </BoutonY2K>
        </div>
        <ModalSave
          open={saveOpen}
          onOpenChange={setSaveOpen}
          audience={audience}
          filtres={filtresCourants}
          onSaved={reload}
          alertesDisponibles={alertesDisponibles}
        />
      </>
    );
  }

  return (
    <div className="border rounded-lg p-4 bg-white space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="font-medium flex items-center gap-2">
          <Search className="h-4 w-4" /> Mes recherches sauvegardées
        </h3>
        <BoutonY2K size="sm" variant="secondary" onClick={() => setSaveOpen(true)} iconeGauche={<Save className="h-4 w-4" />}>
          Sauvegarder
        </BoutonY2K>
      </div>

      {erreurListe ? (
        <div role="alert" className="space-y-2 text-sm">
          <p>Vos recherches sauvegardées n’ont pas pu être chargées.</p>
          <button className="underline" onClick={() => { void reload(); }}>Réessayer</button>
        </div>
      ) : loading ? (
        <p className="text-sm text-gray-500">Chargement…</p>
      ) : (
        <ul className="space-y-2">
          {list.map((f) => (
            <li key={f.id} className="flex items-center justify-between gap-2 border rounded p-2 hover:bg-gray-50">
              <button
                type="button"
                className="text-left flex-1 min-w-0"
                onClick={() => { onCharger(f.filtres); toast.success(`Filtres « ${f.nom} » appliqués`); }}
                title="Cliquer pour réappliquer ces filtres"
              >
                <div className="font-medium text-sm truncate">{f.nom}</div>
                <div className="text-xs text-gray-500">
                  {f.alerte_active
                    ? <>🔔 Alertes {f.frequence_alerte.toLowerCase()}</>
                    : <>🔕 Alertes désactivées</>}
                </div>
              </button>
              <div className="flex items-center gap-1 shrink-0">
                {alertesDisponibles && <BoutonY2K size="sm" variant="ghost" onClick={() => handleToggleAlerte(f)}
                  title={f.alerte_active ? 'Désactiver alertes' : 'Activer alertes'}
                  aria-label={f.alerte_active ? 'Désactiver alertes' : 'Activer alertes'}>
                  {f.alerte_active
                    ? <Bell className="h-4 w-4 text-blue-600" />
                    : <BellOff className="h-4 w-4 text-gray-400" />}
                </BoutonY2K>}
                <BoutonY2K size="sm" variant="ghost" onClick={() => setEditing(f)} title="Modifier" aria-label="Modifier">
                  <Edit2 className="h-4 w-4" />
                </BoutonY2K>
                <BoutonY2K size="sm" variant="ghost" onClick={() => handleDelete(f)} title="Supprimer" aria-label="Supprimer">
                  <Trash2 className="h-4 w-4 text-red-500" />
                </BoutonY2K>
              </div>
            </li>
          ))}
        </ul>
      )}

      {/* Modal Sauvegarder */}
      <ModalSave
        open={saveOpen}
        onOpenChange={setSaveOpen}
        audience={audience}
        filtres={filtresCourants}
        onSaved={reload}
        alertesDisponibles={alertesDisponibles}
      />

      {/* Modal Modifier */}
      <ModalEdit
        filtre={editing}
        onOpenChange={(o) => { if (!o) setEditing(null); }}
        onSaved={() => { reload(); setEditing(null); }}
        alertesDisponibles={alertesDisponibles}
      />
    </div>
  );
}

function ModalSave({
  open, onOpenChange, audience, filtres, onSaved, alertesDisponibles,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  audience: FiltreAudience;
  filtres: Record<string, unknown>;
  onSaved: () => void;
  alertesDisponibles: boolean;
}) {
  const [nom, setNom] = useState('');
  const [alerteActive, setAlerteActive] = useState(alertesDisponibles);
  const [frequence, setFrequence] = useState<FrequenceAlerte>('QUOTIDIENNE');
  const [submitting, setSubmitting] = useState(false);

  const etaitOuvert = useRef(false);
  useEffect(() => {
    if (open && !etaitOuvert.current) { setNom(''); setAlerteActive(alertesDisponibles); setFrequence('QUOTIDIENNE'); }
    etaitOuvert.current = open;
  }, [open, alertesDisponibles]);

  const submit = async () => {
    if (nom.trim().length === 0) { toast.error('Donnez un nom à votre recherche'); return; }
    setSubmitting(true);
    const { data, error } = await supabase.rpc('fn_creer_filtre_sauvegarde', {
      p_nom: nom.trim(), p_audience: audience, p_filtres: filtres as Json,
      p_alerte_active: alertesDisponibles && alerteActive, p_frequence_alerte: frequence,
    });
    setSubmitting(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur enregistrement');
      return;
    }
    toast.success('Recherche sauvegardée');
    onOpenChange(false);
    onSaved();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Sauvegarder cette recherche</DialogTitle>
          <DialogDescription>
            {alertesDisponibles
              ? 'Vous pourrez réappliquer ces filtres plus tard et recevoir des alertes email automatiques quand de nouveaux résultats matchent vos critères.'
              : 'Cette sauvegarde vous permet de retrouver et réappliquer vos filtres. Elle ne crée pas d’alerte email.'}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div>
            <Label htmlFor="filtre-nom">Nom de la recherche</Label>
            <Input
              id="filtre-nom" maxLength={100}
              placeholder={audience === 'SOIGNANT_RECHERCHE_MISSIONS' ? 'IDE Paris > 25 €/h' : 'IDE expérimenté disponible week-end'}
              value={nom} onChange={(e) => setNom(e.target.value)}
            />
            <p className="text-xs text-gray-500 mt-1">{nom.length}/100 caractères</p>
          </div>

          {alertesDisponibles && <div className="flex items-center justify-between">
            <Label htmlFor="alerte-toggle" className="cursor-pointer">
              Recevoir des alertes email
            </Label>
            <Switch id="alerte-toggle" checked={alerteActive} onCheckedChange={setAlerteActive} />
          </div>}

          {alertesDisponibles && alerteActive && (
            <div>
              <Label htmlFor="freq-select">Fréquence des alertes</Label>
              <Select value={frequence} onValueChange={(v) => setFrequence(v as FrequenceAlerte)}>
                <SelectTrigger id="freq-select"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(FREQUENCE_LABELS) as FrequenceAlerte[]).map((k) => (
                    <SelectItem key={k} value={k}>{FREQUENCE_LABELS[k]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-gray-500 mt-2">
                Vous pouvez modifier vos préférences globales d'emails dans
                <em> Paramètres → Notifications</em>. Les emails d'urgence ne sont jamais désactivables.
              </p>
            </div>
          )}
        </div>
        <DialogFooter>
          <BoutonY2K variant="secondary" onClick={() => onOpenChange(false)} disabled={submitting}>Annuler</BoutonY2K>
          <BoutonY2K onClick={submit} disabled={submitting} loading={submitting}>
            {submitting ? 'Enregistrement…' : 'Enregistrer'}
          </BoutonY2K>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ModalEdit({
  filtre, onOpenChange, onSaved, alertesDisponibles,
}: {
  filtre: FiltreSauvegarde | null;
  onOpenChange: (o: boolean) => void;
  onSaved: () => void;
  alertesDisponibles: boolean;
}) {
  const [nom, setNom] = useState('');
  const [alerteActive, setAlerteActive] = useState(false);
  const [frequence, setFrequence] = useState<FrequenceAlerte>('QUOTIDIENNE');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (filtre) {
      setNom(filtre.nom);
      setAlerteActive(filtre.alerte_active);
      setFrequence(filtre.frequence_alerte);
    }
  }, [filtre]);

  if (!filtre) return null;

  const submit = async () => {
    if (nom.trim().length === 0) { toast.error('Nom requis'); return; }
    setSubmitting(true);
    const { data, error } = await supabase.rpc('fn_modifier_filtre_sauvegarde', {
      p_id: filtre.id, p_nom: nom.trim(),
      ...(alertesDisponibles ? { p_alerte_active: alerteActive, p_frequence_alerte: frequence } : {}),
    });
    setSubmitting(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur mise à jour');
      return;
    }
    toast.success('Recherche mise à jour');
    onSaved();
  };

  return (
    <Dialog open={!!filtre} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Modifier la recherche</DialogTitle>
          <DialogDescription>
            {alertesDisponibles
              ? "Vous pouvez renommer et changer les préférences d'alertes. Pour modifier les critères de recherche, supprimez celle-ci et créez-en une nouvelle."
              : 'Vous pouvez renommer cette recherche. Ses critères et ses éventuelles alertes existantes sont conservés.'}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div>
            <Label htmlFor="edit-nom">Nom</Label>
            <Input id="edit-nom" maxLength={100} value={nom} onChange={(e) => setNom(e.target.value)} />
          </div>
          {alertesDisponibles && <div className="flex items-center justify-between">
            <Label htmlFor="edit-alerte">Alertes email</Label>
            <Switch id="edit-alerte" checked={alerteActive} onCheckedChange={setAlerteActive} />
          </div>}
          {alertesDisponibles && alerteActive && (
            <div>
              <Label htmlFor="edit-freq">Fréquence</Label>
              <Select value={frequence} onValueChange={(v) => setFrequence(v as FrequenceAlerte)}>
                <SelectTrigger id="edit-freq"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(FREQUENCE_LABELS) as FrequenceAlerte[]).map((k) => (
                    <SelectItem key={k} value={k}>{FREQUENCE_LABELS[k]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>
        <DialogFooter>
          <BoutonY2K variant="secondary" onClick={() => onOpenChange(false)} disabled={submitting}>Annuler</BoutonY2K>
          <BoutonY2K onClick={submit} disabled={submitting} loading={submitting}>
            {submitting ? 'Enregistrement…' : 'Enregistrer'}
          </BoutonY2K>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
