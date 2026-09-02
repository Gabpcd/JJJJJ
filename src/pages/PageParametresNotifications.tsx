import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, Mail, MessageSquare, Smartphone, Loader2, ArrowLeft, Save, CircleCheck, TriangleAlert } from 'lucide-react';
import { Capacitor } from '@capacitor/core';
import { LayoutApp } from '@/components/LayoutApp';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { toast } from 'sonner';

type Canal = 'EMAIL' | 'SMS' | 'PUSH' | 'IN_APP';

interface PrefsGlobal {
  canal_email: boolean;
  canal_sms: boolean;
  canal_push: boolean;
  canal_in_app: boolean;
}

interface PrefEvenement {
  type_evenement: string;
  canal: Canal;
  actif: boolean;
}

type AutorisationPushNative = 'loading' | 'granted' | 'prompt' | 'denied' | 'unavailable';

interface EventDef {
  type: string;
  label: string;
  description: string;
  canaux: Canal[];
  // Régime auquel l'événement appartient. Un soignant PUREMENT libéral ne reçoit
  // jamais d'événement salarié (CDD), et inversement. MIXTE (cumul) voit tout.
  regime?: 'SALARIE' | 'LIBERAL';
}

const EVENTS_SOIGNANT: EventDef[] = [
  { type: 'NOUVELLE_MISSION_MATCHANT_FILTRE', label: 'Nouvelles missions matchant mes filtres', description: 'Alertes sur les missions correspondant à mes recherches sauvegardées', canaux: ['EMAIL','PUSH'] },
  { type: 'CANDIDATURE_ACCEPTEE', label: 'Ma candidature est acceptée', description: 'Confirmation d\'assignation à une mission', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'MISSION_ASSIGNEE', label: 'Proposition de mission directe', description: 'Quand un établissement me propose directement une mission', canaux: ['EMAIL','PUSH'] },
  { type: 'RAPPEL_J1_MISSION', label: 'Rappel mission J-1', description: 'Rappel la veille du début de mission', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'POINTAGE_MANQUANT', label: 'Pointage manquant', description: 'Si j\'ai oublié de pointer mon départ', canaux: ['EMAIL','PUSH'] },
  { type: 'FACTURE_EMISE', label: 'Facture émise', description: 'Quand Jolene émet une nouvelle facture en mon nom', canaux: ['EMAIL','PUSH'], regime: 'LIBERAL' },
  { type: 'PAIEMENT_RECU', label: 'Paiement reçu', description: 'Quand un établissement règle ma facture', canaux: ['EMAIL','PUSH'], regime: 'LIBERAL' },
  { type: 'CONTRAT_TRAVAIL_DEPOSE', label: 'Contrat de travail SALARIE déposé', description: 'Quand mon établissement upload mon contrat CDD', canaux: ['EMAIL','PUSH'], regime: 'SALARIE' },
  { type: 'LITIGE_OUVERT', label: 'Litige ouvert', description: 'Notifications sur les litiges en cours', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'LITIGE_RESOLU', label: 'Litige résolu', description: 'Quand un litige a été clos', canaux: ['EMAIL','PUSH'] },
  { type: 'DOCUMENT_EXPIRANT', label: 'Document expirant bientôt', description: 'RCP, diplôme ou autre document arrivant à expiration', canaux: ['EMAIL','PUSH'] },
  { type: 'MANDAT_RE_SIGNATURE', label: 'Re-signature du mandat de facturation', description: 'Si une nouvelle version du mandat est publiée', canaux: ['EMAIL','PUSH'], regime: 'LIBERAL' },
  { type: 'SERIE_ONBOARDING', label: 'Série emails de bienvenue (J0-J7)', description: 'Séquence d\'emails d\'accueil pendant la première semaine', canaux: ['EMAIL'] },
];

const EVENTS_ETAB: EventDef[] = [
  { type: 'CANDIDATURE_RECUE', label: 'Nouvelle candidature reçue', description: 'Quand un soignant postule à une de mes missions', canaux: ['EMAIL','PUSH'] },
  { type: 'POINTAGE_MANQUANT', label: 'Pointage soignant manquant', description: 'Alerte si un soignant assigné n\'a pas pointé', canaux: ['EMAIL','PUSH'] },
  { type: 'CONTRAT_TRAVAIL_DEPOSE', label: 'Rappel contrat de travail SALARIE', description: 'Rappel J-1 si le contrat n\'a pas été uploadé', canaux: ['EMAIL'] },
  { type: 'FACTURE_EMISE', label: 'Facture de commission Jolene émise', description: 'Quand Jolene émet une facture de commission', canaux: ['EMAIL'] },
  { type: 'LITIGE_OUVERT', label: 'Litige ouvert par un soignant', description: 'Notifications sur les litiges en cours', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'LITIGE_RESOLU', label: 'Litige résolu', description: 'Quand un litige a été clos', canaux: ['EMAIL'] },
  { type: 'NOUVELLE_MISSION_MATCHANT_FILTRE', label: 'Nouveaux soignants disponibles', description: 'Alertes sur les soignants matchant mes recherches sauvegardées', canaux: ['EMAIL'] },
  { type: 'SERIE_ONBOARDING', label: 'Série emails de bienvenue (J0-J7)', description: 'Séquence d\'emails d\'accueil pendant la première semaine', canaux: ['EMAIL'] },
];

export default function PageParametresNotifications() {
  usePageTitle('Préférences de notifications');
  const navigate = useNavigate();
  const { user } = useAuth();
  const { role } = useRole();
  const isEtab = role === 'ADMIN_ETABLISSEMENT';
  const [typeExercice, setTypeExercice] = useState<string | null>(null);
  // Un soignant purement libéral ne voit pas les événements salarié (CDD) et
  // inversement. MIXTE ou régime inconnu → on affiche tout (B8 régime per-mission).
  const events = useMemo(() => {
    if (isEtab) return EVENTS_ETAB;
    if (typeExercice === 'LIBERAL') return EVENTS_SOIGNANT.filter(e => e.regime !== 'SALARIE');
    if (typeExercice === 'SALARIE') return EVENTS_SOIGNANT.filter(e => e.regime !== 'LIBERAL');
    return EVENTS_SOIGNANT;
  }, [isEtab, typeExercice]);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [activationPushEnCours, setActivationPushEnCours] = useState(false);
  const [autorisationPushNative, setAutorisationPushNative] = useState<AutorisationPushNative | null>(
    Capacitor.isNativePlatform() ? 'loading' : null,
  );
  const [global, setGlobal] = useState<PrefsGlobal>({
    canal_email: true, canal_sms: false, canal_push: true, canal_in_app: true,
  });
  const [parEvenement, setParEvenement] = useState<Map<string, boolean>>(new Map());

  // Toggle granulaire opt-in SMS pour mission urgente + rappel J-1 (soignant uniquement).
  // Stocké directement sur soignants.sms_alertes_actives, indépendant des prefs DB.
  const [smsAlertesActives, setSmsAlertesActives] = useState<boolean>(true);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data, error } = await supabase.rpc('fn_obtenir_mes_preferences_notifications' as any);
      if (error) {
        toast.error('Impossible de charger vos préférences. Vos modifications ne seront pas sauvegardées tant que la page ne charge pas correctement.');
        setLoading(false);
        return;
      }
      if (data && (data as any).global) {
        setGlobal((data as any).global);
        const m = new Map<string, boolean>();
        for (const p of ((data as any).par_evenement || []) as PrefEvenement[]) {
          m.set(`${p.type_evenement}:${p.canal}`, p.actif);
        }
        setParEvenement(m);
      }

      // Lecture du flag SMS d'alerte (soignant uniquement)
      if (!isEtab) {
        const { data: soignant } = await supabase
          .from('soignants')
          .select('sms_alertes_actives, type_exercice')
          .eq('id', user.id)
          .maybeSingle();
        if (soignant && (soignant as any).sms_alertes_actives !== null) {
          setSmsAlertesActives(!!(soignant as any).sms_alertes_actives);
        }
        if (soignant && (soignant as any).type_exercice) {
          setTypeExercice((soignant as any).type_exercice);
        }
      }

      setLoading(false);
    })();
  }, [user, isEtab]);

  useEffect(() => {
    if (!Capacitor.isNativePlatform() || !user) return;
    let actif = true;
    void import('@capacitor/push-notifications')
      .then(async ({ PushNotifications }) => {
        const permission = await PushNotifications.checkPermissions();
        if (!actif) return;
        setAutorisationPushNative(
          permission.receive === 'granted'
            ? 'granted'
            : permission.receive === 'denied'
              ? 'denied'
              : 'prompt',
        );
      })
      .catch(() => {
        if (actif) setAutorisationPushNative('unavailable');
      });
    return () => { actif = false; };
  }, [user]);

  const activerPushSurAppareil = async () => {
    if (!user || !Capacitor.isNativePlatform()) return;
    setActivationPushEnCours(true);
    try {
      const { demanderPermissionNativePush } = await import('@/lib/pushNative');
      const permissionAccordee = await demanderPermissionNativePush(user.id);
      setAutorisationPushNative(permissionAccordee ? 'granted' : 'denied');
      if (permissionAccordee) {
        setGlobal((courant) => ({ ...courant, canal_push: true }));
        toast.success('Notifications autorisées sur cet appareil');
      } else {
        toast.error('Notifications non autorisées. Vérifiez les réglages du téléphone.');
      }
    } catch {
      setAutorisationPushNative('unavailable');
      toast.error("Impossible de vérifier l'autorisation des notifications.");
    } finally {
      setActivationPushEnCours(false);
    }
  };

  const isEnabled = (event: string, canal: Canal) => {
    const key = `${event}:${canal}`;
    return parEvenement.has(key) ? !!parEvenement.get(key) : true;
  };

  const toggle = (event: string, canal: Canal) => {
    const key = `${event}:${canal}`;
    const current = isEnabled(event, canal);
    const m = new Map(parEvenement);
    m.set(key, !current);
    setParEvenement(m);
  };

  const enregistrer = async () => {
    setSaving(true);
    try {
      const par_evenement: any[] = [];
      for (const [key, actif] of parEvenement) {
        const [type_evenement, canal] = key.split(':');
        par_evenement.push({ type_evenement, canal, actif });
      }
      const { data, error } = await supabase.rpc('fn_modifier_preferences_notifications' as any, {
        p_canal_email: global.canal_email,
        p_canal_sms: global.canal_sms,
        p_canal_push: global.canal_push,
        p_canal_in_app: global.canal_in_app,
        p_par_evenement: par_evenement,
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);

      // Mise à jour du flag granulaire SMS d'alerte (soignant uniquement)
      // Cast `as any` car la colonne sms_alertes_actives sera ajoutée par la migration
      // 20260506100000_soignants_sms_alertes_actives.sql et les types ne sont pas
      // encore régénérés. À retirer après prochain `supabase gen types`.
      if (!isEtab && user) {
        const { error: smsErr } = await supabase
          .from('soignants')
          .update({ sms_alertes_actives: smsAlertesActives } as any)
          .eq('id', user.id);
        if (smsErr) {
          // Ne casse pas la sauvegarde des autres prefs, mais signaler à l'user
          toast.error('Préférences générales enregistrées, mais flag SMS d\'alerte non sauvegardé.');
          return;
        }
      }

      toast.success('Préférences enregistrées');
    } catch (err: any) {
      toast.error(err?.message || 'Erreur enregistrement');
    } finally {
      setSaving(false);
    }
  };

  const role_safe = (isEtab ? 'ADMIN_ETABLISSEMENT' : 'SOIGNANT') as any;

  if (loading) {
    return (
      <LayoutApp role={role_safe}>
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role={role_safe}>
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" className="app-inline-back" aria-label="Retour" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <Bell className="h-5 w-5 text-primary" /> Préférences de notifications
            </h1>
            <p className="text-xs text-muted-foreground">Choisissez par canal et par type d'événement</p>
          </div>
        </div>

        {/* SMS d'alerte (soignants uniquement) — opt-in granulaire pour mission
            urgente et rappel J-1. Coupe ces 2 cas sans toucher aux autres SMS. */}
        {!isEtab && (
          <section className="card-base space-y-3">
            <h2 className="text-base font-semibold text-foreground flex items-center gap-2">
              <MessageSquare className="h-4 w-4 text-primary" /> SMS d'alerte
            </h2>
            <p className="text-xs text-muted-foreground">
              Recevoir un SMS pour les missions urgentes et le rappel mission J-1.
              Coût supporté par Jolene. Tu peux désactiver à tout moment.
            </p>
            {!global.canal_sms && (
              <p className="text-xs text-warning">
                Le canal « SMS » est désactivé dans les canaux globaux ci-dessous : active-le pour recevoir ces alertes.
              </p>
            )}
            <ToggleCanal
              icone={<MessageSquare className="h-4 w-4" />}
              label="Recevoir les alertes par SMS"
              actif={smsAlertesActives}
              onChange={setSmsAlertesActives}
              disabled={!global.canal_sms}
            />
          </section>
        )}

        {/* Canaux globaux */}
        <section className="card-base space-y-3">
          <h2 className="text-base font-semibold text-foreground">Canaux globaux</h2>
          <p className="text-xs text-muted-foreground">
            Désactiver un canal ici coupe TOUTES les notifications de ce canal, peu importe les préférences par événement.
          </p>
          <div className="grid sm:grid-cols-2 gap-3">
            <ToggleCanal icone={<Mail className="h-4 w-4" />} label="Email" actif={global.canal_email} onChange={v => setGlobal(g => ({ ...g, canal_email: v }))} />
            <ToggleCanal icone={<Smartphone className="h-4 w-4" />} label="Notifications push (mobile / web)" actif={global.canal_push} onChange={v => setGlobal(g => ({ ...g, canal_push: v }))} />
            <ToggleCanal icone={<MessageSquare className="h-4 w-4" />} label="SMS (urgences uniquement par défaut)" actif={global.canal_sms} onChange={v => setGlobal(g => ({ ...g, canal_sms: v }))} />
            <ToggleCanal icone={<Bell className="h-4 w-4" />} label="In-app (cloche en haut de l'écran)" actif={global.canal_in_app} onChange={v => setGlobal(g => ({ ...g, canal_in_app: v }))} />
          </div>
          {autorisationPushNative && (
            <div
              className={`flex flex-col gap-3 rounded-lg border p-3 sm:flex-row sm:items-center sm:justify-between ${
                autorisationPushNative === 'granted'
                  ? 'border-success/30 bg-success/5'
                  : 'border-warning/30 bg-warning/5'
              }`}
              aria-live="polite"
              data-testid="native-push-permission-status"
            >
              <div className="flex items-start gap-2">
                {autorisationPushNative === 'granted'
                  ? <CircleCheck className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                  : <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-warning" />}
                <div>
                  <p className="text-sm font-medium text-foreground">Autorisation du téléphone</p>
                  <p className="text-xs text-muted-foreground">
                    {autorisationPushNative === 'loading' && 'Vérification de l’autorisation système…'}
                    {autorisationPushNative === 'granted' && (
                      global.canal_push
                        ? 'Les notifications sont autorisées sur cet appareil.'
                        : 'Le téléphone les autorise, mais le canal est désactivé dans Jolene.'
                    )}
                    {autorisationPushNative === 'prompt' && 'Le canal est actif dans Jolene, mais le téléphone doit encore autoriser les notifications.'}
                    {autorisationPushNative === 'denied' && 'Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système.'}
                    {autorisationPushNative === 'unavailable' && 'L’état système n’a pas pu être vérifié. Réessayez dans quelques instants.'}
                  </p>
                </div>
              </div>
              {autorisationPushNative === 'prompt' && global.canal_push && (
                <Button
                  type="button"
                  variant="outline"
                  className="min-h-11 shrink-0"
                  disabled={activationPushEnCours}
                  onClick={() => { void activerPushSurAppareil(); }}
                >
                  {activationPushEnCours && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Activer sur cet appareil
                </Button>
              )}
            </div>
          )}
        </section>

        {/* Préférences par événement */}
        <section className="card-base space-y-3">
          <h2 className="text-base font-semibold text-foreground">Par type d'événement</h2>
          <p className="text-xs text-muted-foreground">
            Pour chaque type d'événement, choisissez les canaux activés. Les notifications d'urgence (sécurité, danger) sont toujours envoyées et non désactivables.
          </p>
          <div className="overflow-x-auto -mx-4 px-4">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 pr-3 font-semibold text-foreground">Événement</th>
                  <th className="text-center py-2 px-2 font-semibold text-foreground w-20">Email</th>
                  <th className="text-center py-2 px-2 font-semibold text-foreground w-20">Push</th>
                  <th className="text-center py-2 px-2 font-semibold text-foreground w-20">SMS</th>
                </tr>
              </thead>
              <tbody>
                {events.map(e => (
                  <tr key={e.type} className="border-b border-border last:border-0">
                    <td className="py-3 pr-3">
                      <p className="font-medium text-foreground">{e.label}</p>
                      <p className="text-xs text-muted-foreground">{e.description}</p>
                    </td>
                    {(['EMAIL','PUSH','SMS'] as Canal[]).map(c => {
                      // Le canal global coupe TOUT : si OFF, on grise le sous-toggle
                      // (il n'aurait aucun effet) plutôt que de laisser croire qu'il agit.
                      const canalGlobalActif = c === 'EMAIL' ? global.canal_email : c === 'PUSH' ? global.canal_push : global.canal_sms;
                      return (
                      <td key={c} className="text-center px-2">
                        {e.canaux.includes(c) ? (
                          <button
                            type="button"
                            role="switch"
                            aria-checked={isEnabled(e.type, c)}
                            disabled={!canalGlobalActif}
                            onClick={() => canalGlobalActif && toggle(e.type, c)}
                            className={`relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors ${!canalGlobalActif ? 'cursor-not-allowed opacity-40' : 'cursor-pointer'} ${isEnabled(e.type, c) ? 'bg-primary' : 'bg-muted-foreground/30'}`}
                            title={!canalGlobalActif ? `Canal ${c} désactivé dans les canaux globaux` : undefined}
                            aria-label={`${c} pour ${e.label} : ${!canalGlobalActif ? 'canal global désactivé' : isEnabled(e.type, c) ? 'activé' : 'désactivé'}`}
                          >
                            <span className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${isEnabled(e.type, c) ? 'translate-x-4' : 'translate-x-0'}`} />
                          </button>
                        ) : (
                          <span className="text-xs text-muted-foreground/50">—</span>
                        )}
                      </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <div className="rounded-xl border border-warning/30 bg-warning/5 p-3 text-xs text-muted-foreground">
          <p className="font-semibold text-foreground mb-1">⚠️ Notifications d'urgence</p>
          Les notifications d'urgence critique (incident sécurité, litige sécurité, alerte fraude) sont toujours envoyées sur tous les canaux configurés et ne peuvent pas être désactivées. C'est une exigence de sécurité.
        </div>

        <div className="flex justify-end sticky bottom-4">
          <BoutonY2K onClick={enregistrer} disabled={saving} loading={saving} className="shadow-lg" iconeGauche={!saving ? <Save className="h-4 w-4" /> : undefined}>
            Enregistrer
          </BoutonY2K>
        </div>
      </div>
    </LayoutApp>
  );
}

function ToggleCanal({ icone, label, actif, onChange, disabled }: { icone: JSX.Element; label: string; actif: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <div className={`flex items-center justify-between gap-3 rounded-lg border border-border p-3 ${disabled ? 'opacity-50' : ''}`}>
      <div className="flex items-center gap-2">
        <span className="text-primary">{icone}</span>
        <span className="text-sm text-foreground">{label}</span>
      </div>
      <button
        type="button"
        role="switch"
        aria-label={label}
        aria-checked={actif}
        onClick={() => !disabled && onChange(!actif)}
        disabled={disabled}
        className={`relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors ${disabled ? 'cursor-not-allowed' : 'cursor-pointer'} ${actif ? 'bg-primary' : 'bg-muted-foreground/30'}`}
      >
        <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${actif ? 'translate-x-5' : 'translate-x-0'}`} />
      </button>
    </div>
  );
}
