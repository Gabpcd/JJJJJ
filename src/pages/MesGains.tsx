import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Banknote, Gift, Palmtree, Clock, Copy, FileDown, Download } from 'lucide-react';
import jsPDF from 'jspdf';
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

function genererPDFBulletin(m: any, soignant: any) {
  const doc = new jsPDF();
  const duree = m.duree_heures ?? 0;
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;
  const brutBase = tauxEffectif * duree;
  const totalMajorations = (m.montant_majoration_nuit || 0) + (m.montant_majoration_dimanche || 0) + (m.montant_majoration_ferie || 0);
  const totalBrut = m.total_brut || (brutBase + totalMajorations);
  const ifm = m.montant_ifm || 0;
  const icp = m.montant_icp || 0;
  const superBrut = totalBrut + ifm + icp;
  const netEstime = m.net_estime || (superBrut * 0.78);
  const etab = m.etablissements;

  doc.setFontSize(10);
  doc.setTextColor(100);
  doc.text('BULLETIN DE PAIE — ESTIMATION', 105, 20, { align: 'center' });
  doc.setFontSize(12);
  doc.setTextColor(23, 162, 184);
  doc.text(`Mission du ${format(new Date(m.debut_le), 'd MMMM yyyy', { locale: fr })}`, 105, 28, { align: 'center' });
  doc.setDrawColor(200);
  doc.line(14, 32, 196, 32);

  doc.setFontSize(9);
  doc.setTextColor(0);
  let y = 40;
  doc.setFont('helvetica', 'bold');
  doc.text('SALARIÉ :', 14, y);
  doc.setFont('helvetica', 'normal');
  y += 5;
  doc.text(`${soignant?.prenom || ''} ${soignant?.nom || ''}`, 14, y);
  if (soignant?.profession) { y += 4; doc.text(`Profession : ${soignant.profession}`, 14, y); }

  let yE = 40;
  doc.setFont('helvetica', 'bold');
  doc.text('ÉTABLISSEMENT :', 110, yE);
  doc.setFont('helvetica', 'normal');
  yE += 5;
  doc.text(etab?.nom || '', 110, yE);
  if (etab?.adresse_ville) { yE += 4; doc.text(`${etab.adresse_code_postal} ${etab.adresse_ville}`, 110, yE); }

  let pY = Math.max(y, yE) + 12;
  doc.line(14, pY - 2, 196, pY - 2);
  doc.setFont('helvetica', 'bold');
  doc.text('MISSION', 14, pY + 4);
  doc.setFont('helvetica', 'normal');
  pY += 10;
  doc.text(`${m.intitule}${m.service ? ` — ${m.service}` : ''}`, 14, pY);
  pY += 5;
  doc.text(`${format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → ${format(new Date(m.fin_le), "HH'h'mm", { locale: fr })} (${duree}h)`, 14, pY);

  pY += 10;
  doc.line(14, pY - 2, 196, pY - 2);
  doc.setFont('helvetica', 'bold');
  doc.text('DÉCOMPTE', 14, pY + 4);
  doc.setFont('helvetica', 'normal');
  pY += 10;

  const addLine = (label: string, amount: string) => {
    doc.text(label, 14, pY);
    doc.text(amount, 180, pY, { align: 'right' });
    pY += 5;
  };

  addLine(`Salaire de base (${duree}h × ${tauxEffectif?.toFixed(2)} €)`, `${brutBase.toFixed(2)} €`);
  if ((m.montant_majoration_nuit || 0) > 0) addLine('Majoration nuit', `+${m.montant_majoration_nuit.toFixed(2)} €`);
  if ((m.montant_majoration_dimanche || 0) > 0) addLine('Majoration dimanche', `+${m.montant_majoration_dimanche.toFixed(2)} €`);
  if ((m.montant_majoration_ferie || 0) > 0) addLine('Majoration jour férié', `+${m.montant_majoration_ferie.toFixed(2)} €`);
  pY += 2;
  doc.setFont('helvetica', 'bold');
  addLine('Total brut', `${totalBrut.toFixed(2)} €`);
  doc.setFont('helvetica', 'normal');
  if (ifm > 0) addLine('IFM (10%)', `+${ifm.toFixed(2)} €`);
  if (icp > 0) addLine('ICP (10%)', `+${icp.toFixed(2)} €`);
  pY += 2;
  addLine('Cotisations salariales estimées (~22%)', `-${(superBrut * 0.22).toFixed(2)} €`);
  pY += 3;
  doc.line(14, pY, 196, pY);
  pY += 6;
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  addLine('NET ESTIMÉ', `${netEstime.toFixed(2)} €`);
  doc.setFontSize(9);

  pY += 8;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.setTextColor(120);
  doc.text('Estimation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.', 14, pY);

  const pageH = doc.internal.pageSize.height;
  doc.setFontSize(7);
  doc.setTextColor(150);
  doc.text('Document généré par Jolene — Valeur indicative', 105, pageH - 10, { align: 'center' });

  doc.save(`bulletin_paie_${format(new Date(m.debut_le), 'yyyy-MM-dd')}_${m.id.slice(0, 8)}.pdf`);
}

export default function MesGains() {
  usePageTitle('Mes gains');
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
          montant_ifm, montant_icp, total_brut, net_a_payer, net_estime,
          type_paiement_soignant,
          statut, cree_le, etablissement_id`)
        .eq('soignant_assigne_id', user.id)
        .eq('statut', 'TERMINEE')
        .order('debut_le', { ascending: false });

      if (filtre.debut) query = query.gte('debut_le', filtre.debut.toISOString());
      if (filtre.fin) query = query.lte('debut_le', filtre.fin.toISOString());

      const [{ data: ms }, { data: sg }] = await Promise.all([
        query,
        supabase.from('soignants').select('prenom, nom, profession, numero_rpps, siret_liberal, adresse_rue, adresse_code_postal, adresse_ville, assujetti_tva, iban').eq('id', user.id).single(),
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
    const totalNet = missions.reduce((s, m) => s + (m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0)), 0);
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
    texte += `Net estimé total : ${stats.totalNet.toFixed(2)} €\n`;
    texte += `────────────────────────────\n`;
    texte += `Détail :\n`;
    for (const m of missions) {
      const netM = m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);
      texte += `• ${new Date(m.debut_le).toLocaleDateString('fr-FR')} — ${m.intitule} — ${m.duree_heures}h — ${netM.toFixed(2)} €\n`;
    }
    texte += `\n⚠️ Estimation après cotisations salariales (~22%). Les montants exacts dépendent de votre situation personnelle.\n`;
    texte += `Généré par Jolene le ${new Date().toLocaleDateString('fr-FR')}`;
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
        <CarteKPI icone={Banknote} valeur={fmt(stats.totalNet)} label="Net estimé* total" couleurIcone="text-primary" couleurFond="bg-primary/10" />
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
              const montantAffiche = estLiberal ? m.total_brut : (m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0));
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
                        <span className="float-right font-bold text-primary">{estLiberal ? 'HT' : 'Net estimé*'} : {fmt(montantAffiche || 0)}</span>
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
                      <>
                        <DecompositionFinanciere mission={m} etablissement={m.etablissements} />
                        <div className="mt-3 flex justify-center">
                          <button
                            onClick={() => genererPDFBulletin(m, soignant)}
                            className="flex items-center gap-2 px-4 py-2 rounded-xl bg-primary text-primary-foreground font-semibold text-sm hover:bg-primary/90 transition-colors"
                          >
                            <Download className="h-4 w-4" /> Télécharger le bulletin PDF
                          </button>
                        </div>
                      </>
                    )}
                  </AccordionContent>
                </AccordionItem>
              );
            })}
          </Accordion>
        ) : (
          <EtatVide illustration={<IllustrationTirelire />} titre="Pas encore de gains" sousTitre="Vos gains apparaîtront ici après votre première mission terminée." />
        )}
      </div>
      <ModalAttestation open={modalAttestation} onClose={() => setModalAttestation(false)} />
    </LayoutApp>
  );
}
