import { useState, useEffect, useMemo } from 'react';
import { Banknote, Gift, Palmtree, Clock, Copy, FileDown } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide, IllustrationTirelire } from '@/components/EtatVide';
import { FiltresPeriode } from '@/components/FiltresPeriode';
import { GraphiqueGainsMensuels } from '@/components/GraphiqueGainsMensuels';
import { DecompositionFinanciere } from '@/components/DecompositionFinanciere';
import { NoteHonoraires } from '@/components/NoteHonoraires';
import { ModalAttestation } from '@/components/ModalAttestation';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { format, startOfMonth, endOfMonth } from 'date-fns';
import { fr } from 'date-fns/locale';

function fmt(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function MesGains() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [missions, setMissions] = useState<any[]>([]);
  const [soignant, setSoignant] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [modalAttestation, setModalAttestation] = useState(false);
  const [filtre, setFiltre] = useState<{ debut: Date | null; fin: Date | null; label: string }>({
    debut: startOfMonth(new Date()), fin: endOfMonth(new Date()), label: format(new Date(), 'MMMM yyyy', { locale: fr }),
  });

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      // Sécurité : ne jamais requêter taux_commission, montant_commission_ht/tva/ttc
      let query = supabase
        .from('missions')
        .select(`id, intitule, service, debut_le, fin_le, duree_heures,
          taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
          heures_nuit, heures_dimanche, heures_ferie,
          montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie,
          montant_ifm, montant_icp, total_brut, net_a_payer,
          type_paiement_soignant,
          statut, cree_le, etablissement_id`)
        .eq('soignant_assigne_id', user.id)
        .eq('statut', 'TERMINEE')
        .order('debut_le', { ascending: false });

      if (filtre.debut) query = query.gte('debut_le', filtre.debut.toISOString());
      if (filtre.fin) query = query.lte('debut_le', filtre.fin.toISOString());

      const [{ data: ms }, { data: sg }] = await Promise.all([
        query,
        supabase.from('soignants').select('prenom, nom, profession').eq('id', user.id).single(),
      ]);
      const enriched = ms ? await enrichirEtablissements(ms as any) : [];
      setMissions(enriched as any[]);
      setSoignant(sg);
      setLoading(false);

      // Audit HDS — tracer la consultation de données personnelles
      supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: null,
        p_details: { page: 'mes_gains', periode: filtre.label },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    };
    load();
  }, [user, filtre]);

  const stats = useMemo(() => {
    const totalNet = missions.reduce((s, m) => s + (m.net_a_payer || 0), 0);
    const totalIFM = missions.reduce((s, m) => s + (m.montant_ifm || 0), 0);
    const totalICP = missions.reduce((s, m) => s + (m.montant_icp || 0), 0);
    const totalHeures = missions.reduce((s, m) => s + (m.duree_heures || 0), 0);
    const tauxMoyenNet = totalHeures > 0 ? totalNet / totalHeures : 0;
    return { totalNet, totalIFM, totalICP, totalHeures, nbMissions: missions.length, tauxMoyenNet };
  }, [missions]);

  async function copierResume() {
    if (!soignant) return;
    // L6: Anonymized resume — no personal identifiers in clipboard
    let texte = `RÉSUMÉ GAINS — ${filtre.label}\n`;
    texte += `────────────────────────────\n`;
    texte += `Missions terminées : ${stats.nbMissions}\n`;
    texte += `Heures travaillées : ${stats.totalHeures}h\n`;
    texte += `Net total : ${stats.totalNet.toFixed(2)} €\n`;
    texte += `────────────────────────────\n`;
    texte += `Détail :\n`;
    for (const m of missions) {
      texte += `• ${new Date(m.debut_le).toLocaleDateString('fr-FR')} — ${m.intitule} — ${m.duree_heures}h — ${m.net_a_payer?.toFixed(2)} €\n`;
    }
    texte += `\n⚠️ Simulation à titre indicatif.\n`;
    texte += `Généré par Soin Direct le ${new Date().toLocaleDateString('fr-FR')}`;
    await navigator.clipboard.writeText(texte);
    // L6: Audit clipboard copy
    supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT',
      p_action: 'DONNEES_PERSO_COPIE_PRESSE_PAPIER',
      p_type_ressource: 'soignant', p_id_ressource: user!.id,
      p_cle_s3: null, p_details: { page: 'mes_gains', nb_missions: missions.length },
      p_ip: null, p_navigateur: navigator.userAgent,
    });
    afficherNotification({ type: 'succes', message: '📋 Résumé copié !' });
  }

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">💰 Mes gains</h1>
        <p className="text-sm text-muted-foreground mt-1">{filtre.label}</p>
      </div>

      <FiltresPeriode onChange={(d, f, l) => setFiltre({ debut: d, fin: f, label: l })} />

      {/* KPI */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-2">
        <CarteKPI icone={Banknote} valeur={fmt(stats.totalNet)} label="Net total gagné" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={Gift} valeur={fmt(stats.totalIFM)} label="Dont IFM" couleurIcone="text-emerald-600" couleurFond="bg-emerald-100" />
        <CarteKPI icone={Palmtree} valeur={fmt(stats.totalICP)} label="Dont ICP" couleurIcone="text-info" couleurFond="bg-info/10" />
        <CarteKPI icone={Clock} valeur={`${Math.round(stats.totalHeures)}h`} label={`sur ${stats.nbMissions} missions`} couleurIcone="text-purple-600" couleurFond="bg-purple-100" />
      </div>
      <p className="text-xs text-muted-foreground italic mb-6">Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.</p>

      {/* Taux moyen */}
      {stats.totalHeures > 0 && (
        <div className="bg-primary/5 border border-primary/20 rounded-xl p-3 mb-6 text-center">
          <p className="text-sm text-foreground">Taux horaire moyen net : <span className="font-bold text-primary">{stats.tauxMoyenNet.toFixed(2)} €/h</span></p>
        </div>
      )}

      {/* Graphique */}
      <div className="mb-6">
        <GraphiqueGainsMensuels missions={missions} />
      </div>

      {/* Liste fiches de paie / notes d'honoraires */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
          <h2 className="text-lg font-bold text-foreground">📋 Fiches de paie & honoraires</h2>
          <div className="flex items-center gap-2">
            <button onClick={() => setModalAttestation(true)} className="flex items-center gap-1.5 bg-primary text-primary-foreground rounded-xl px-4 py-2 font-semibold text-sm hover:opacity-90 transition-opacity">
              <FileDown className="h-4 w-4" /> Attestation d'heures
            </button>
            <button onClick={copierResume} className="flex items-center gap-1 text-sm text-primary font-medium hover:underline">
              <Copy className="h-4 w-4" /> Copier le résumé
            </button>
          </div>
        </div>

        {missions.length > 0 ? (
          <Accordion type="single" collapsible className="space-y-2">
            {missions.map(m => {
              const estLiberal = m.type_paiement_soignant === 'NOTE_HONORAIRES';
              const iconeType = estLiberal ? '🧾' : '📋';
              const labelType = estLiberal ? 'Note d\'honoraires' : 'Bulletin de paie';
              const montantAffiche = estLiberal ? m.total_brut : m.net_a_payer;
              return (
                <AccordionItem key={m.id} value={m.id} className="card-base !p-0 overflow-hidden border">
                  <AccordionTrigger className="px-4 py-3 hover:no-underline">
                    <div className="flex-1 text-left">
                      <p className="text-sm font-semibold text-foreground">
                        📅 {format(new Date(m.debut_le), "EEE d MMM", { locale: fr })} · {m.intitule} · {m.etablissements?.nom}
                      </p>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs font-medium ${estLiberal ? 'bg-purple-100 text-purple-700' : 'bg-primary/10 text-primary'}`}>
                          {iconeType} {labelType}
                        </span>
                        {' '}{m.duree_heures}h · {m.taux_horaire_base} €/h
                        <span className="float-right font-bold text-primary">{estLiberal ? 'HT' : 'Net'} : {fmt(montantAffiche || 0)}</span>
                      </p>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="px-4 pb-4">
                    <div className="mb-2 text-xs text-muted-foreground">
                      {m.etablissements?.nom}, {m.etablissements?.adresse_ville} · {format(new Date(m.debut_le), "HH:mm", { locale: fr })} → {format(new Date(m.fin_le), "HH:mm", { locale: fr })} ({m.duree_heures}h)
                    </div>
                    {estLiberal ? (
                      <NoteHonoraires mission={m} soignant={soignant} etablissement={m.etablissements} />
                    ) : (
                      <DecompositionFinanciere mission={m} etablissement={m.etablissements} />
                    )}
                  </AccordionContent>
                </AccordionItem>
              );
            })}
          </Accordion>
        ) : (
          <EtatVide icone={Banknote} titre="Aucune mission terminée" sousTitre="Vos fiches de paie apparaîtront ici après chaque mission." />
        )}
      </div>
      <ModalAttestation open={modalAttestation} onClose={() => setModalAttestation(false)} />
    </LayoutApp>
  );
}
