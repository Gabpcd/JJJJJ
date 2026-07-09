import { usePageTitle } from '@/hooks/usePageTitle';
import { useState, useEffect, useMemo } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { CalendarDays, Sun, Moon, Info } from 'lucide-react';
import { format, addDays, startOfWeek } from 'date-fns';
import { fr } from 'date-fns/locale';

/**
 * Lot 17 (F5) — calendrier de disponibilités soignant.
 *
 * 4 semaines glissantes, deux créneaux par jour : Jour (JOURNEE) et Nuit
 * (NUIT). Chaque tap appelle fn_definir_disponibilite (upsert/suppression).
 * En retour :
 *  - matching inversé quotidien « 📅 Des missions collent à ton planning » ;
 *  - vivier « N soignants disponibles ce jour-là » côté établissement à la
 *    création de mission (prénom + score uniquement, jamais de coordonnées).
 */

type Creneau = 'JOURNEE' | 'NUIT';

const cleDispo = (jour: string, creneau: Creneau) => `${jour}|${creneau}`;

export default function MesDisponibilites() {
  usePageTitle('Mes disponibilités');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [dispos, setDispos] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [enCours, setEnCours] = useState<Set<string>>(new Set());

  // 4 semaines complètes à partir de la semaine courante (lundi).
  const semaines = useMemo(() => {
    const debut = startOfWeek(new Date(), { weekStartsOn: 1 });
    return Array.from({ length: 4 }, (_, s) =>
      Array.from({ length: 7 }, (_, j) => addDays(debut, s * 7 + j)),
    );
  }, []);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data, error } = await supabase
        .from('disponibilites_soignant' as any)
        .select('jour, creneau')
        .gte('jour', format(new Date(), 'yyyy-MM-dd'));
      if (!error && data) {
        setDispos(new Set((data as any[]).map((d) => cleDispo(d.jour, d.creneau))));
      }
      setLoading(false);
    })();
  }, [user]);

  const basculer = async (jourDate: Date, creneau: Creneau) => {
    const jour = format(jourDate, 'yyyy-MM-dd');
    const cle = cleDispo(jour, creneau);
    if (enCours.has(cle)) return;
    const nouvelEtat = !dispos.has(cle);

    setEnCours((prev) => new Set(prev).add(cle));
    // Optimiste — rollback si la RPC échoue.
    setDispos((prev) => {
      const next = new Set(prev);
      if (nouvelEtat) next.add(cle); else next.delete(cle);
      return next;
    });

    const { data, error } = await supabase.rpc('fn_definir_disponibilite' as any, {
      p_jour: jour,
      p_creneau: creneau,
      p_disponible: nouvelEtat,
    });
    if (error || (data as any)?.error) {
      setDispos((prev) => {
        const next = new Set(prev);
        if (nouvelEtat) next.delete(cle); else next.add(cle);
        return next;
      });
      afficherNotification({ type: 'erreur', message: (data as any)?.error || extraireMessageErreur(error) });
    }
    setEnCours((prev) => {
      const next = new Set(prev);
      next.delete(cle);
      return next;
    });
  };

  const nbDispos = dispos.size;
  const aujourdHui = format(new Date(), 'yyyy-MM-dd');

  if (loading) {
    return (
      <LayoutApp role="SOIGNANT">
        <ChargementPage />
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-3xl mx-auto px-4 py-6 space-y-5">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <CalendarDays aria-hidden="true" className="h-5 w-5 text-primary" />
            Mes disponibilités
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Indiquez vos jours et nuits disponibles : vous êtes alertée dès que des missions
            correspondent à votre planning, et les établissements voient qu'ils peuvent compter
            sur vous ce jour-là (prénom et score uniquement, jamais vos coordonnées).
          </p>
        </div>

        {nbDispos === 0 && (
          <div className="text-xs text-muted-foreground bg-muted/50 border border-border rounded-lg p-3 flex items-start gap-2">
            <Info aria-hidden="true" className="h-4 w-4 shrink-0 mt-0.5" />
            <span>
              Touchez <strong>Jour</strong> ou <strong>Nuit</strong> sur les dates où vous êtes
              disponible. Vous pouvez tout modifier à tout moment.
            </span>
          </div>
        )}

        <div className="space-y-4">
          {semaines.map((semaine, s) => (
            <div key={s} className="border border-border rounded-xl overflow-hidden">
              <div className="bg-muted/50 px-3 py-2 text-xs font-semibold text-muted-foreground">
                Semaine du {format(semaine[0], 'd MMMM', { locale: fr })}
              </div>
              <div className="divide-y divide-border">
                {semaine.map((jourDate) => {
                  const jour = format(jourDate, 'yyyy-MM-dd');
                  const passe = jour < aujourdHui;
                  const dispoJour = dispos.has(cleDispo(jour, 'JOURNEE'));
                  const dispoNuit = dispos.has(cleDispo(jour, 'NUIT'));
                  return (
                    <div
                      key={jour}
                      className={`flex items-center justify-between px-3 py-2 ${passe ? 'opacity-40' : ''}`}
                    >
                      <span className="text-sm text-foreground capitalize">
                        {format(jourDate, 'EEEE d MMM', { locale: fr })}
                        {jour === aujourdHui && (
                          <span className="ml-1.5 text-[10px] font-semibold text-primary">aujourd'hui</span>
                        )}
                      </span>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          disabled={passe}
                          aria-pressed={dispoJour}
                          onClick={() => basculer(jourDate, 'JOURNEE')}
                          className={`min-h-[36px] px-3 rounded-full text-xs font-medium border transition-colors flex items-center gap-1 ${
                            dispoJour
                              ? 'bg-primary text-primary-foreground border-primary'
                              : 'bg-background text-muted-foreground border-border hover:border-primary/50'
                          }`}
                        >
                          <Sun aria-hidden="true" className="h-3.5 w-3.5" />Jour
                        </button>
                        <button
                          type="button"
                          disabled={passe}
                          aria-pressed={dispoNuit}
                          onClick={() => basculer(jourDate, 'NUIT')}
                          className={`min-h-[36px] px-3 rounded-full text-xs font-medium border transition-colors flex items-center gap-1 ${
                            dispoNuit
                              ? 'bg-jolene-midnight text-white border-jolene-midnight dark:bg-primary dark:border-primary'
                              : 'bg-background text-muted-foreground border-border hover:border-primary/50'
                          }`}
                        >
                          <Moon aria-hidden="true" className="h-3.5 w-3.5" />Nuit
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        <p className="text-[11px] text-muted-foreground">
          {nbDispos > 0
            ? `${nbDispos} créneau${nbDispos > 1 ? 'x' : ''} déclaré${nbDispos > 1 ? 's' : ''}. `
            : ''}
          Déclarer une disponibilité n'engage à rien : c'est un signal de matching, pas un engagement.
        </p>
      </div>
    </LayoutApp>
  );
}
