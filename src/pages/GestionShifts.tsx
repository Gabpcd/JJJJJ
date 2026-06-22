import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { supabase } from '@/integrations/supabase/client';
import { Plus, ChevronLeft, ChevronRight, Users, Clock, Trash2, Calendar, Loader2 } from 'lucide-react';
import { format, startOfWeek, addDays, addWeeks, subWeeks, isSameDay, parseISO } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Equipe { id: string; nom: string; service: string | null; couleur: string; }
interface Shift { id: string; equipe_id: string | null; intitule: string; service: string | null; jour: string; heure_debut: string; heure_fin: string; profession_requise: string | null; nb_postes: number; nb_pourvus: number; }

export default function GestionShifts() {
  usePageTitle('Planning & Shifts');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [equipes, setEquipes] = useState<Equipe[]>([]);
  const [shifts, setShifts] = useState<Shift[]>([]);
  const [semaine, setSemaine] = useState(startOfWeek(new Date(), { weekStartsOn: 1 }));
  const [showForm, setShowForm] = useState(false);
  const [saving, setSaving] = useState(false);
  const [creatingEquipe, setCreatingEquipe] = useState(false);
  const [deletingEquipeId, setDeletingEquipeId] = useState<string | null>(null);
  const [deletingShiftId, setDeletingShiftId] = useState<string | null>(null);
  const [newEquipeNom, setNewEquipeNom] = useState('');
  const [form, setForm] = useState({
    intitule: '', service: '', jour: format(new Date(), 'yyyy-MM-dd'),
    heure_debut: '07:00', heure_fin: '19:00', profession_requise: '',
    nb_postes: 1, equipe_id: '',
  });

  const jours = useMemo(() =>
    Array.from({ length: 7 }, (_, i) => addDays(semaine, i)),
    [semaine]
  );

  const charger = async () => {
    if (!user) return;
    setLoading(true);
    const debutSemaine = format(semaine, 'yyyy-MM-dd');
    const finSemaine = format(addDays(semaine, 6), 'yyyy-MM-dd');
    const [resEquipes, resShifts] = await Promise.all([
      supabase.from('equipes').select('*').eq('etablissement_id', user.id).is('supprime_le', null).order('nom'),
      supabase.from('shifts').select('*').eq('etablissement_id', user.id).gte('jour', debutSemaine).lte('jour', finSemaine).order('heure_debut'),
    ]);
    setEquipes((resEquipes.data as any[]) || []);
    setShifts((resShifts.data as any[]) || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, semaine]);

  const creerEquipe = async () => {
    if (!newEquipeNom.trim() || !user || creatingEquipe) return;
    setCreatingEquipe(true);
    const { error } = await supabase.from('equipes').insert({ etablissement_id: user.id, nom: newEquipeNom.trim() } as any);
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else { setNewEquipeNom(''); charger(); afficherNotification({ type: 'succes', message: 'Équipe créée.' }); }
    setCreatingEquipe(false);
  };

  const supprimerEquipe = async (id: string) => {
    if (deletingEquipeId) return;
    setDeletingEquipeId(id);
    const { error } = await supabase.from('equipes').update({ supprime_le: new Date().toISOString() } as any).eq('id', id);
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else charger();
    setDeletingEquipeId(null);
  };

  const creerShift = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    setSaving(true);
    const { error } = await supabase.from('shifts').insert({
      etablissement_id: user.id,
      intitule: form.intitule || 'Shift',
      service: form.service || null,
      jour: form.jour,
      heure_debut: form.heure_debut,
      heure_fin: form.heure_fin,
      profession_requise: form.profession_requise || null,
      nb_postes: form.nb_postes,
      equipe_id: form.equipe_id || null,
    } as any);
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else { setShowForm(false); charger(); afficherNotification({ type: 'succes', message: 'Shift créé.' }); }
    setSaving(false);
  };

  const supprimerShift = async (id: string) => {
    if (deletingShiftId) return;
    setDeletingShiftId(id);
    await supabase.from('shifts').delete().eq('id', id);
    charger();
    setDeletingShiftId(null);
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground">Planning & Shifts</h1>
          <p className="text-sm text-muted-foreground">Gérez vos équipes et plannings de remplacement</p>
        </div>
        <button onClick={() => setShowForm(!showForm)} className="btn-primary flex items-center gap-2">
          <Plus className="h-4 w-4" /> Nouveau shift
        </button>
      </div>

      {/* Équipes */}
      <div className="card-base mb-6">
        <h2 className="text-base font-semibold text-foreground mb-3">Équipes</h2>
        <div className="flex flex-wrap gap-2 mb-3">
          {equipes.map(eq => (
            <div key={eq.id} className="flex items-center gap-2 bg-muted/30 rounded-lg px-3 py-1.5">
              <div className="h-3 w-3 rounded-full" style={{ backgroundColor: eq.couleur }} />
              <span className="text-sm font-medium text-foreground">{eq.nom}</span>
              {eq.service && <span className="text-xs text-muted-foreground">({eq.service})</span>}
              <button onClick={() => supprimerEquipe(eq.id)} disabled={deletingEquipeId === eq.id} aria-label={`Supprimer l'équipe ${eq.nom}`} className="text-muted-foreground hover:text-destructive ml-1 disabled:opacity-40"><Trash2 className="h-3 w-3" /></button>
            </div>
          ))}
          {equipes.length === 0 && <p className="text-sm text-muted-foreground">Aucune équipe. Créez-en une ci-dessous.</p>}
        </div>
        <div className="flex gap-2">
          <input aria-label="Nom de l'équipe" value={newEquipeNom} onChange={e => setNewEquipeNom(e.target.value)} placeholder="Nom de l'équipe (ex: Nuit A, Jour B...)" className="input-base flex-1" onKeyDown={e => e.key === 'Enter' && creerEquipe()} />
          <button onClick={creerEquipe} disabled={!newEquipeNom.trim() || creatingEquipe} className="btn-primary px-4 disabled:opacity-50">{creatingEquipe ? 'Création…' : 'Créer'}</button>
        </div>
      </div>

      {/* Form nouveau shift */}
      {showForm && (
        <form onSubmit={creerShift} className="card-base mb-6 space-y-3">
          <h2 className="text-base font-semibold text-foreground">Nouveau shift</h2>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div><label className="text-sm font-medium text-foreground mb-1 block">Intitulé</label><input value={form.intitule} onChange={e => setForm(p => ({ ...p, intitule: e.target.value }))} placeholder="Ex: IDE Matin" className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1 block">Service</label><input value={form.service} onChange={e => setForm(p => ({ ...p, service: e.target.value }))} placeholder="Ex: Urgences" className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1 block">Équipe</label>
              <select value={form.equipe_id} onChange={e => setForm(p => ({ ...p, equipe_id: e.target.value }))} className="input-base">
                <option value="">Sans équipe</option>
                {equipes.map(eq => <option key={eq.id} value={eq.id}>{eq.nom}</option>)}
              </select>
            </div>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div><label className="text-sm font-medium text-foreground mb-1 block">Jour</label><input type="date" value={form.jour} onChange={e => setForm(p => ({ ...p, jour: e.target.value }))} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1 block">Début</label><input type="time" value={form.heure_debut} onChange={e => setForm(p => ({ ...p, heure_debut: e.target.value }))} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1 block">Fin</label><input type="time" value={form.heure_fin} onChange={e => setForm(p => ({ ...p, heure_fin: e.target.value }))} className="input-base" /></div>
            <div><label className="text-sm font-medium text-foreground mb-1 block">Postes</label><input type="number" min={1} value={form.nb_postes} onChange={e => setForm(p => ({ ...p, nb_postes: parseInt(e.target.value) || 1 }))} className="input-base" /></div>
          </div>
          <div className="flex gap-2">
            <button type="submit" disabled={saving} className="btn-primary flex items-center gap-2">{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />} Créer le shift</button>
            <button type="button" onClick={() => setShowForm(false)} className="btn-secondary">Annuler</button>
          </div>
        </form>
      )}

      {/* Semaine navigation */}
      <div className="flex items-center justify-between mb-4">
        <button onClick={() => setSemaine(subWeeks(semaine, 1))} className="p-2 rounded-lg hover:bg-muted transition"><ChevronLeft className="h-5 w-5 text-muted-foreground" /></button>
        <h2 className="text-base font-semibold text-foreground">
          Semaine du {format(semaine, 'd MMMM yyyy', { locale: fr })}
        </h2>
        <button onClick={() => setSemaine(addWeeks(semaine, 1))} className="p-2 rounded-lg hover:bg-muted transition"><ChevronRight className="h-5 w-5 text-muted-foreground" /></button>
      </div>

      {/* Planning grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-7 gap-2 overflow-x-auto">
        {jours.map(jour => {
          const jourStr = format(jour, 'yyyy-MM-dd');
          const shiftsJour = shifts.filter(s => s.jour === jourStr);
          const isToday = isSameDay(jour, new Date());
          return (
            <div key={jourStr} className={`min-h-[150px] rounded-xl border p-2 ${isToday ? 'border-primary bg-primary/5' : 'border-border bg-card'}`}>
              <p className={`text-xs font-semibold mb-2 ${isToday ? 'text-primary' : 'text-muted-foreground'}`}>
                {format(jour, 'EEE d', { locale: fr })}
              </p>
              <div className="space-y-1.5">
                {shiftsJour.map(s => {
                  const eq = equipes.find(e => e.id === s.equipe_id);
                  return (
                    <div key={s.id} className="group relative rounded-lg border border-border/50 bg-muted/30 p-1.5 text-[10px] hover:bg-muted/60 transition cursor-default">
                      <div className="flex items-center gap-1">
                        {eq && <div className="h-2 w-2 rounded-full flex-shrink-0" style={{ backgroundColor: eq.couleur }} />}
                        <span className="font-semibold text-foreground truncate">{s.intitule}</span>
                      </div>
                      <p className="text-muted-foreground">{s.heure_debut?.slice(0, 5)} — {s.heure_fin?.slice(0, 5)}</p>
                      <p className="text-muted-foreground">{s.nb_pourvus}/{s.nb_postes} pourvu{s.nb_postes > 1 ? 's' : ''}</p>
                      <button onClick={() => supprimerShift(s.id)} disabled={deletingShiftId === s.id} aria-label="Supprimer le shift" className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition text-muted-foreground hover:text-destructive disabled:opacity-40">
                        <Trash2 className="h-3 w-3" />
                      </button>
                    </div>
                  );
                })}
                {shiftsJour.length === 0 && (
                  <p className="text-[10px] text-muted-foreground/40 text-center py-4">—</p>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Stats résumé */}
      <div className="grid grid-cols-3 gap-3 mt-6">
        <div className="card-base text-center p-4">
          <Calendar className="h-5 w-5 text-primary mx-auto mb-1" />
          <p className="text-xl font-bold text-foreground">{shifts.length}</p>
          <p className="text-xs text-muted-foreground">Shifts cette semaine</p>
        </div>
        <div className="card-base text-center p-4">
          <Users className="h-5 w-5 text-info mx-auto mb-1" />
          <p className="text-xl font-bold text-foreground">{shifts.reduce((s, sh) => s + sh.nb_postes, 0)}</p>
          <p className="text-xs text-muted-foreground">Postes à pourvoir</p>
        </div>
        <div className="card-base text-center p-4">
          <Clock className="h-5 w-5 text-success mx-auto mb-1" />
          <p className="text-xl font-bold text-foreground">{shifts.reduce((s, sh) => s + sh.nb_pourvus, 0)}</p>
          <p className="text-xs text-muted-foreground">Postes pourvus</p>
        </div>
      </div>
    </LayoutApp>
  );
}
