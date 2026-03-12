import { Printer, Send } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface NoteHonorairesProps {
  mission: any;
  soignant: any;
  etablissement?: any;
  onAudit?: () => void;
}

function fmt(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function NoteHonoraires({ mission, soignant, etablissement, onAudit }: NoteHonorairesProps) {
  const m = mission;
  const etab = etablissement || m.etablissements;
  const duree = m.duree_heures ?? 0;
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;
  const sousTotal = duree * tauxEffectif;

  const handlePrint = () => {
    onAudit?.();
    window.print();
  };

  return (
    <div className="bg-card border border-border rounded-2xl p-6 shadow-sm print:shadow-none print:border-0 print:p-0">
      {/* Header */}
      <div className="text-center mb-6 print:mb-4">
        <h2 className="text-lg font-bold text-foreground">NOTE D'HONORAIRES</h2>
        <p className="text-sm text-primary font-semibold mt-1">N° {m.numero_note_honoraires || 'NH-XXXX-XXXX'}</p>
      </div>

      {/* De / À */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6 text-sm">
        <div className="bg-muted/30 rounded-xl p-4">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">De :</p>
          <p className="font-semibold text-foreground">{soignant?.prenom} {soignant?.nom}</p>
          {soignant?.numero_rpps && <p className="text-xs text-muted-foreground">RPPS : {soignant.numero_rpps}</p>}
          {soignant?.siret_liberal && <p className="text-xs text-muted-foreground">SIRET : {soignant.siret_liberal}</p>}
          {soignant?.adresse_rue && <p className="text-xs text-muted-foreground mt-1">{soignant.adresse_rue}, {soignant.adresse_code_postal} {soignant.adresse_ville}</p>}
        </div>
        <div className="bg-muted/30 rounded-xl p-4">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">À :</p>
          <p className="font-semibold text-foreground">{etab?.nom}</p>
          {etab?.siret && <p className="text-xs text-muted-foreground">SIRET : {etab.siret}</p>}
          {etab?.finess && <p className="text-xs text-muted-foreground">FINESS : {etab.finess}</p>}
          {etab?.adresse_rue && <p className="text-xs text-muted-foreground mt-1">{etab.adresse_rue}, {etab.adresse_code_postal} {etab.adresse_ville}</p>}
        </div>
      </div>

      {/* Prestation */}
      <div className="border-t border-border pt-4 mb-4">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Prestation</p>
        <p className="text-sm text-foreground">
          Date : {format(new Date(m.debut_le), 'd MMMM yyyy', { locale: fr })} — {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
        </p>
        <p className="text-sm text-foreground">Nature : {m.intitule}{m.service ? ` — ${m.service}` : ''}</p>
        <p className="text-sm text-foreground">Durée : {duree}h</p>
      </div>

      {/* Décomposition */}
      <div className="border-t border-border pt-4 space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-muted-foreground">Taux horaire</span>
          <span className="font-medium">{tauxEffectif?.toFixed(2)} €/h</span>
        </div>
        <div className="flex justify-between">
          <span className="text-muted-foreground">Sous-total ({duree}h × {tauxEffectif?.toFixed(2)} €)</span>
          <span className="font-medium">{fmt(sousTotal)}</span>
        </div>

        {(m.montant_majoration_nuit || 0) > 0 && (
          <div className="flex justify-between">
            <span className="text-muted-foreground">🌙 Majoration nuit</span>
            <span className="font-medium text-primary">+{fmt(m.montant_majoration_nuit)}</span>
          </div>
        )}
        {(m.montant_majoration_dimanche || 0) > 0 && (
          <div className="flex justify-between">
            <span className="text-muted-foreground">☀️ Majoration dimanche</span>
            <span className="font-medium text-primary">+{fmt(m.montant_majoration_dimanche)}</span>
          </div>
        )}
        {(m.montant_majoration_ferie || 0) > 0 && (
          <div className="flex justify-between">
            <span className="text-muted-foreground">🎌 Majoration jour férié</span>
            <span className="font-medium text-primary">+{fmt(m.montant_majoration_ferie)}</span>
          </div>
        )}

        <div className="border-t-2 border-primary/30 pt-3 mt-3">
          <div className="flex justify-between">
            <span className="font-bold text-foreground">TOTAL HT</span>
            <span className="text-xl font-bold text-primary">{fmt(m.total_brut)}</span>
          </div>
        </div>

        {/* TVA exemption */}
        <div className="bg-muted/30 rounded-xl p-3 mt-3">
          <p className="text-xs text-muted-foreground italic">
            Dispensé de TVA — Art. 261-4-1° du CGI<br />
            (Soins dispensés par les professions médicales et paramédicales réglementées)
          </p>
        </div>

        <div className="border-t-2 border-foreground/20 pt-3">
          <div className="flex justify-between">
            <span className="font-bold text-foreground text-lg">TOTAL À PAYER</span>
            <span className="text-2xl font-bold text-primary">{fmt(m.total_brut)}</span>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-3 mt-6 print:hidden">
        <button onClick={handlePrint} className="btn-primary flex-1 flex items-center justify-center gap-2">
          <Printer className="h-4 w-4" /> Imprimer
        </button>
        <button className="btn-secondary flex-1 flex items-center justify-center gap-2 opacity-50 cursor-not-allowed" disabled>
          <Send className="h-4 w-4" /> Envoyer à ma compta
        </button>
      </div>

      <p className="text-[10px] text-muted-foreground/60 italic text-center mt-3 print:hidden">
        Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
      </p>
    </div>
  );
}
