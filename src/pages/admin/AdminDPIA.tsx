import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { CardY2K } from '@/components/y2k/CardY2K';
import { AlertTriangle, CircleDashed, FileText } from 'lucide-react';

type StatutMesure = 'PARTIEL' | 'A_IMPLEMENTER' | 'A_DOCUMENTER';

const LIBELLES_STATUT: Record<StatutMesure, string> = {
  PARTIEL: 'Partiel',
  A_IMPLEMENTER: 'À implémenter',
  A_DOCUMENTER: 'À documenter',
};

function BadgeStatutMesure({ statut }: { statut: StatutMesure }) {
  const classe = statut === 'PARTIEL'
    ? 'border-warning/40 bg-warning/10 text-warning'
    : 'border-destructive/40 bg-destructive/10 text-destructive';
  return <span className={`inline-flex rounded-full border px-2 py-1 text-xs font-semibold ${classe}`}>{LIBELLES_STATUT[statut]}</span>;
}

export default function AdminDPIA() {
  usePageTitle('DPIA — Analyse d’impact');

  const risques: Array<{
    risque: string;
    gravite: string;
    mesureRequise: string;
    constat: string;
    statut: StatutMesure;
  }> = [
    {
      risque: 'Document valide rejeté par l’IA',
      gravite: 'Haute',
      mesureRequise: 'Recours humain visible depuis chaque document et file de revue avec accès au fichier.',
      constat: 'La file admin existe partiellement, mais le parcours de contestation et la prévisualisation ne sont pas complets.',
      statut: 'A_IMPLEMENTER',
    },
    {
      risque: 'Document frauduleux accepté',
      gravite: 'Haute',
      mesureRequise: 'Seuil documenté et revue humaine obligatoire sous le seuil.',
      constat: 'Un score de confiance est produit, sans preuve qu’une revue humaine soit imposée dans tous les cas à risque.',
      statut: 'PARTIEL',
    },
    {
      risque: 'Divulgation de documents au prestataire IA',
      gravite: 'Haute',
      mesureRequise: 'DPA, localisation, rétention, transferts, sous-traitants ultérieurs et procédure d’incident documentés.',
      constat: 'Le transport HTTPS est utilisé. Les garanties contractuelles et de rétention doivent être rattachées à des preuves à jour.',
      statut: 'A_DOCUMENTER',
    },
    {
      risque: 'Biais ou erreur d’analyse',
      gravite: 'Haute',
      mesureRequise: 'Jeu de tests représentatif, mesure des erreurs par type de document et contrôle humain.',
      constat: 'Les prompts limitent la finalité, mais aucun résultat d’évaluation représentative n’est joint à cette page.',
      statut: 'A_IMPLEMENTER',
    },
    {
      risque: 'Décision automatisée sans recours effectif',
      gravite: 'Haute',
      mesureRequise: 'Aucun rejet définitif sans voie de recours accessible et traçable.',
      constat: 'Le bouton de demande de revue manuelle annoncé dans les textes publics n’est pas disponible sur chaque document rejeté.',
      statut: 'A_IMPLEMENTER',
    },
    {
      risque: 'Indisponibilité du prestataire IA',
      gravite: 'Moyenne',
      mesureRequise: 'Passage en attente de revue manuelle, sans rejet automatique.',
      constat: 'Le runtime utilise Anthropic. Aucun basculement Gemini opérationnel n’a été vérifié.',
      statut: 'A_IMPLEMENTER',
    },
  ];

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <FileText className="h-5 w-5 text-primary" /> Analyse d’impact relative à la protection des données
        </h1>
        <p className="text-sm text-muted-foreground">Article 35 RGPD — vérification de documents assistée par IA</p>
      </div>

      <div role="alert" className="mb-6 max-w-4xl rounded-xl border border-warning/40 bg-warning/10 p-4 flex items-start gap-3">
        <AlertTriangle className="h-5 w-5 text-warning shrink-0" />
        <div>
          <p className="font-semibold text-foreground">Document de travail — non validé</p>
          <p className="text-sm text-muted-foreground mt-1">
            Cette page décrit l’état réellement vérifié dans l’application. Elle ne constitue ni une validation DPO ni une conclusion juridique tant que les mesures ci-dessous et leurs preuves ne sont pas complètes.
          </p>
        </div>
      </div>

      <div className="space-y-6 max-w-4xl">
        <CardY2K hoverLift={false}>
          <h2 className="text-base font-semibold text-foreground mb-3">1. Description du traitement</h2>
          <div className="space-y-2 text-sm text-muted-foreground">
            <p><strong className="text-foreground">Finalité :</strong> assister la vérification de lisibilité, cohérence et authenticité de documents professionnels.</p>
            <p><strong className="text-foreground">Données :</strong> images/PDF, identité déclarée, type de document et informations extraites. Certains justificatifs peuvent révéler des informations liées à la santé.</p>
            <p><strong className="text-foreground">Prestataire observé dans le runtime :</strong> Anthropic. La configuration, le DPA, la rétention et les transferts doivent être vérifiés et archivés avant validation.</p>
            <p><strong className="text-foreground">Base légale :</strong> à confirmer par le DPO pour chaque catégorie de document et chaque finalité.</p>
          </div>
        </CardY2K>

        <CardY2K hoverLift={false}>
          <h2 className="text-base font-semibold text-foreground mb-3">2. Nécessité et proportionnalité</h2>
          <div className="space-y-3">
            {[
              'Documenter pourquoi chaque catégorie de document est indispensable à la mission proposée.',
              'Limiter les champs transmis au prestataire et retirer les métadonnées inutiles.',
              'Prévoir une méthode manuelle réellement accessible avant tout rejet définitif.',
              'Mesurer les faux positifs et faux négatifs sur un jeu représentatif.',
              'Aligner politique de confidentialité, consentements et déclarations stores sur le runtime.',
            ].map((text) => (
              <div key={text} className="flex items-start gap-2 text-sm">
                <CircleDashed className="h-4 w-4 text-warning mt-0.5 shrink-0" />
                <span className="text-foreground">{text}</span>
              </div>
            ))}
          </div>
        </CardY2K>

        <CardY2K hoverLift={false}>
          <h2 className="text-base font-semibold text-foreground mb-3">3. Risques et mesures vérifiées</h2>
          <div className="space-y-3">
            {risques.map((row) => (
              <div key={row.risque} className="rounded-xl border border-border p-4 space-y-2">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="font-semibold text-foreground">{row.risque}</p>
                    <p className="text-xs text-destructive font-semibold">Gravité : {row.gravite}</p>
                  </div>
                  <BadgeStatutMesure statut={row.statut} />
                </div>
                <p className="text-sm text-foreground"><strong>Mesure requise :</strong> {row.mesureRequise}</p>
                <p className="text-sm text-muted-foreground"><strong>Constat :</strong> {row.constat}</p>
              </div>
            ))}
          </div>
        </CardY2K>

        <CardY2K hoverLift={false}>
          <h2 className="text-base font-semibold text-foreground mb-3">4. Droits des personnes</h2>
          <ul className="space-y-2 text-sm text-foreground list-disc pl-5">
            <li>Information préalable : présente dans les textes, à réaligner avec les données et prestataires réellement utilisés.</li>
            <li>Accès au verdict : présent dans l’espace Documents.</li>
            <li>Contestation et revue humaine : parcours complet à implémenter et tester.</li>
            <li>Effacement : à revalider de bout en bout, y compris compte Auth, sessions, stockage et données du prestataire.</li>
            <li>Traçabilité et durées de conservation : à démontrer par une politique approuvée et des tests.</li>
          </ul>
        </CardY2K>

        <CardY2K hoverLift={false} className="bg-warning/5 border-warning/30">
          <h2 className="text-base font-semibold text-foreground mb-3">5. Conclusion provisoire</h2>
          <p className="text-sm text-foreground">
            Le risque résiduel n’est pas déclaré acceptable à ce stade. La validation finale et l’éventuelle nécessité d’une consultation préalable doivent être décidées par le DPO sur la base des mesures effectivement déployées et de leurs preuves.
          </p>
        </CardY2K>
      </div>
    </LayoutAdmin>
  );
}
