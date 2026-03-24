import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { format, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ArrowLeft, Clock, MapPin, Radio, AlertTriangle, QrCode, Keyboard, Wifi, CheckCircle, XCircle } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

function fmt(v: number) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function MethodeBadge({ methode }: { methode: string | null }) {
  if (!methode) return <Badge variant="outline" className="text-[10px]"><Wifi className="h-3 w-3 mr-1" />GPS</Badge>;
  if (methode === 'CODE') return <Badge variant="outline" className="text-[10px] border-primary/30 text-primary"><Keyboard className="h-3 w-3 mr-1" />Code</Badge>;
  if (methode === 'QR') return <Badge variant="outline" className="text-[10px] border-primary/30 text-primary"><QrCode className="h-3 w-3 mr-1" />QR Code</Badge>;
  return <Badge variant="outline" className="text-[10px]">{methode}</Badge>;
}

interface Props {
  role?: 'ADMIN_ETABLISSEMENT' | 'SOIGNANT' | 'ADMIN_PLATEFORME';
}

export default function DetailPresencesMission({ role = 'ADMIN_ETABLISSEMENT' }: Props) {
  const { id: missionId } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [mission, setMission] = useState<any>(null);
  const [presences, setPresences] = useState<any[]>([]);
  const [soignant, setSoignant] = useState<any>(null);
  const [codes, setCodes] = useState<{ code_arrivee: string; code_depart: string } | null>(null);

  const layoutRole = role === 'ADMIN_PLATEFORME' ? 'ADMIN_PLATEFORME' : role === 'SOIGNANT' ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT';

  useEffect(() => {
    if (!missionId || !user) return;
    const load = async () => {
      const [{ data: missionData }, { data: presData }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, service, debut_le, fin_le, duree_heures, taux_horaire_base, heures_nuit, heures_dimanche, heures_ferie, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, montant_ifm, montant_icp, total_brut, net_estime, soignant_assigne_id, code_arrivee, code_depart, type_paiement_soignant, etablissement_id')
          .eq('id', missionId)
          .single(),
        supabase
          .from('presences')
          .select('*')
          .eq('mission_id', missionId)
          .order('pointage_arrivee_le', { ascending: true }),
      ]);

      // Only fetch codes for établissement/admin (not soignant)
      let codesData: any = null;
      if (role !== 'SOIGNANT') {
        const codesRes = await supabase.rpc('fn_codes_pointage_mission' as any, { p_mission_id: missionId });
        if (codesRes.data) codesData = codesRes.data;
      }

      if (missionData) {
        setMission(missionData);
        if (missionData.soignant_assigne_id) {
          const { data: sg } = await supabase
            .from('soignants')
            .select('id, prenom, nom, profession, numero_rpps')
            .eq('id', missionData.soignant_assigne_id)
            .single();
          setSoignant(sg);
        }
      }

      setPresences(presData || []);
      setCodes(codesData);
      setLoading(false);
    };
    load();
  }, [missionId, user, role]);

  if (loading) return <LayoutApp role={layoutRole}><ChargementPage /></LayoutApp>;
  if (!mission) return <LayoutApp role={layoutRole}><p className="text-muted-foreground">Mission introuvable.</p></LayoutApp>;

  const brut = mission.total_brut || 0;
  const cotis = brut * 0.22;
  const net = mission.net_estime || brut - cotis;

  // Group presences by day
  const presencesByDay: Record<string, any[]> = {};
  for (const p of presences) {
    const dateKey = p.pointage_arrivee_le
      ? format(new Date(p.pointage_arrivee_le), 'yyyy-MM-dd')
      : 'sans-date';
    if (!presencesByDay[dateKey]) presencesByDay[dateKey] = [];
    presencesByDay[dateKey].push(p);
  }

  const sortedDays = Object.keys(presencesByDay).sort();

  return (
    <LayoutApp role={layoutRole}>
      <Button variant="ghost" size="sm" className="mb-4 gap-1" onClick={() => navigate(-1)}>
        <ArrowLeft className="h-4 w-4" /> Retour
      </Button>

      {/* Mission header */}
      <div className="card-base mb-6">
        <h1 className="text-lg font-bold text-foreground">{mission.intitule}</h1>
        {mission.service && <p className="text-sm text-muted-foreground">{mission.service}</p>}
        <div className="flex flex-wrap gap-x-6 gap-y-1 mt-2 text-sm text-muted-foreground">
          <span>📅 {format(new Date(mission.debut_le), 'dd/MM/yyyy HH:mm')} → {format(new Date(mission.fin_le), 'dd/MM/yyyy HH:mm')}</span>
          <span>⏱ {mission.duree_heures}h prévues</span>
          <span>💰 {fmt(mission.taux_horaire_base)}/h</span>
        </div>
        {soignant && role !== 'SOIGNANT' && (
          <p className="text-sm font-medium text-foreground mt-2">
            👤 {soignant.prenom} {soignant.nom} · {soignant.profession}
            {soignant.numero_rpps && <span className="text-muted-foreground"> · RPPS {soignant.numero_rpps}</span>}
          </p>
        )}
      </div>

      {/* Codes de pointage — only for établissement/admin */}
      {codes && (
        <div className="card-base mb-6">
          <h2 className="font-semibold text-foreground flex items-center gap-2 mb-3">
            <QrCode className="h-5 w-5 text-primary" /> Codes de pointage utilisés
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="border border-primary/20 bg-primary/5 rounded-xl p-4 text-center">
              <p className="text-xs font-semibold text-primary uppercase tracking-wide mb-2">Code arrivée</p>
              <p className="text-2xl font-mono font-black text-foreground tracking-[0.3em] mb-3">
                {codes.code_arrivee.slice(0, 3)} {codes.code_arrivee.slice(3)}
              </p>
              <QRCodeSVG value={codes.code_arrivee} size={100} level="M" />
            </div>
            <div className="border border-muted-foreground/20 bg-muted/30 rounded-xl p-4 text-center">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Code départ</p>
              <p className="text-2xl font-mono font-black text-foreground tracking-[0.3em] mb-3">
                {codes.code_depart.slice(0, 3)} {codes.code_depart.slice(3)}
              </p>
              <QRCodeSVG value={codes.code_depart} size={100} level="M" />
            </div>
          </div>
        </div>
      )}

      {/* Détail des pointages par jour */}
      <h2 className="text-base font-bold text-foreground mb-3 flex items-center gap-2">
        <Clock className="h-5 w-5 text-primary" /> Détail des pointages ({presences.length} enregistrement{presences.length > 1 ? 's' : ''})
      </h2>

      {presences.length === 0 ? (
        <div className="card-base text-center py-8">
          <Clock className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Aucun pointage enregistré pour cette mission.</p>
        </div>
      ) : (
        <div className="space-y-4 mb-6">
          {sortedDays.map(day => (
            <div key={day} className="card-base">
              <h3 className="font-semibold text-foreground text-sm mb-3 border-b border-border pb-2">
                📅 {day !== 'sans-date' ? format(new Date(day), 'EEEE d MMMM yyyy', { locale: fr }) : 'Date inconnue'}
              </h3>
              <div className="space-y-3">
                {presencesByDay[day].map((p: any, idx: number) => {
                  const arrivee = p.pointage_arrivee_le ? new Date(p.pointage_arrivee_le) : null;
                  const depart = p.pointage_depart_le ? new Date(p.pointage_depart_le) : null;
                  const dureeMin = arrivee && depart ? differenceInMinutes(depart, arrivee) : null;

                  return (
                    <div key={p.id} className={`rounded-xl border p-3 space-y-2 ${
                      p.alerte_teleportation ? 'border-destructive/40 bg-destructive/5' :
                      !p.perimetre_gps_valide && p.distance_etablissement_m !== null ? 'border-warning/40 bg-warning/5' :
                      p.valide_par_etablissement ? 'border-success/30 bg-success/5' :
                      'border-border'
                    }`}>
                      {presencesByDay[day].length > 1 && (
                        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">
                          Créneau {idx + 1} / {presencesByDay[day].length}
                          {idx > 0 && ' (reprise après pause)'}
                        </p>
                      )}

                      {/* Arrivée */}
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <span className="text-success text-xs font-medium">▶ Arrivée</span>
                          {arrivee && (
                            <span className="text-sm font-semibold text-foreground">
                              {format(arrivee, 'HH:mm:ss', { locale: fr })}
                            </span>
                          )}
                          <MethodeBadge methode={p.methode_pointage_arrivee} />
                        </div>
                        {p.distance_etablissement_m !== null && (
                          <span className={`flex items-center gap-1 text-xs ${p.perimetre_gps_valide ? 'text-success' : 'text-warning'}`}>
                            <MapPin className="h-3 w-3" />
                            {Math.round(p.distance_etablissement_m)}m
                            {p.perimetre_gps_valide ? <CheckCircle className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                          </span>
                        )}
                      </div>

                      {/* Départ */}
                      {depart ? (
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <span className="text-destructive text-xs font-medium">■ Départ</span>
                            <span className="text-sm font-semibold text-foreground">
                              {format(depart, 'HH:mm:ss', { locale: fr })}
                            </span>
                            <MethodeBadge methode={p.methode_pointage_depart} />
                          </div>
                        </div>
                      ) : (
                        <p className="text-xs text-warning italic">⏳ En cours — départ non pointé</p>
                      )}

                      {/* Duration */}
                      {dureeMin !== null && (
                        <p className="text-xs text-muted-foreground">
                          Durée : <span className="font-medium text-foreground">{Math.floor(dureeMin / 60)}h{String(dureeMin % 60).padStart(2, '0')}</span>
                        </p>
                      )}

                      {/* GPS details */}
                      <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">
                        {p.arrivee_precision_gps_m && (
                          <span className="flex items-center gap-1">
                            <Radio className="h-3 w-3" />
                            Précision arrivée : {Math.round(p.arrivee_precision_gps_m)}m
                          </span>
                        )}
                        {p.depart_precision_gps_m && (
                          <span className="flex items-center gap-1">
                            <Radio className="h-3 w-3" />
                            Précision départ : {Math.round(p.depart_precision_gps_m)}m
                          </span>
                        )}
                        {p.arrivee_id_terminal && (
                          <span>Terminal : {p.arrivee_id_terminal.substring(0, 8)}…</span>
                        )}
                      </div>

                      {/* Alerts */}
                      {p.alerte_teleportation && (
                        <div className="flex items-center gap-1 text-xs text-destructive font-medium">
                          <AlertTriangle className="h-3.5 w-3.5" />
                          🚨 Alerte téléportation détectée
                        </div>
                      )}

                      {/* Validation status */}
                      <div className="text-[11px] pt-1 border-t border-border/50">
                        {p.valide_par_etablissement ? (
                          <span className="text-success font-medium">
                            ✅ Validé{p.valide_le ? ` le ${format(new Date(p.valide_le), 'dd/MM/yyyy HH:mm')}` : ''}
                          </span>
                        ) : depart ? (
                          <span className="text-warning">⏳ En attente de validation</span>
                        ) : (
                          <span className="text-muted-foreground">Mission en cours</span>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Récapitulatif financier */}
      <div className="card-base">
        <h2 className="font-semibold text-foreground mb-3">💶 Récapitulatif financier</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
          <div>
            <p className="text-xs text-muted-foreground">Taux horaire</p>
            <p className="font-semibold text-foreground">{fmt(mission.taux_horaire_base)}</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Heures</p>
            <p className="font-semibold text-foreground">{mission.duree_heures}h</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Base brut</p>
            <p className="font-semibold text-foreground">{fmt((mission.duree_heures || 0) * mission.taux_horaire_base)}</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Total brut</p>
            <p className="font-bold text-foreground">{fmt(brut)}</p>
          </div>
        </div>

        {((mission.montant_majoration_nuit || 0) > 0 || (mission.montant_majoration_dimanche || 0) > 0 || (mission.montant_majoration_ferie || 0) > 0 || (mission.montant_ifm || 0) > 0 || (mission.montant_icp || 0) > 0) && (
          <div className="mt-3 pt-3 border-t border-border">
            <p className="text-xs font-medium text-muted-foreground mb-2">Détail des compléments</p>
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs">
              {(mission.montant_majoration_nuit || 0) > 0 && (
                <div><p className="text-muted-foreground">Maj. nuit</p><p className="font-medium text-foreground">{fmt(mission.montant_majoration_nuit)}</p></div>
              )}
              {(mission.montant_majoration_dimanche || 0) > 0 && (
                <div><p className="text-muted-foreground">Maj. dimanche</p><p className="font-medium text-foreground">{fmt(mission.montant_majoration_dimanche)}</p></div>
              )}
              {(mission.montant_majoration_ferie || 0) > 0 && (
                <div><p className="text-muted-foreground">Maj. férié</p><p className="font-medium text-foreground">{fmt(mission.montant_majoration_ferie)}</p></div>
              )}
              {(mission.montant_ifm || 0) > 0 && (
                <div><p className="text-muted-foreground">IFM</p><p className="font-medium text-foreground">{fmt(mission.montant_ifm)}</p></div>
              )}
              {(mission.montant_icp || 0) > 0 && (
                <div><p className="text-muted-foreground">ICP</p><p className="font-medium text-foreground">{fmt(mission.montant_icp)}</p></div>
              )}
            </div>
          </div>
        )}

        <div className="mt-3 pt-3 border-t border-border flex justify-between items-center">
          <span className="text-sm text-muted-foreground">Net estimé</span>
          <span className="text-lg font-bold text-success">{fmt(net)}</span>
        </div>
        <p className="text-[10px] text-muted-foreground italic mt-1">
          ⚠️ Simulation indicative. Seuls les montants calculés par le moteur de paie font foi.
        </p>
      </div>
    </LayoutApp>
  );
}
