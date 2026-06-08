import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { Shield, AlertTriangle, CheckCircle, FileText } from 'lucide-react';

export default function AdminDPIA() {
  usePageTitle('DPIA — Analyse d\'impact');

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2"><FileText className="h-5 w-5 text-primary" /> Analyse d'Impact (DPIA)</h1>
        <p className="text-sm text-muted-foreground">Article 35 RGPD — Vérification automatisée des documents par IA</p>
      </div>

      <div className="space-y-6 max-w-4xl">
        {/* 1. Description du traitement */}
        <section className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-3">1. Description du traitement</h2>
          <div className="space-y-2 text-sm text-muted-foreground">
            <p><strong className="text-foreground">Finalité :</strong> Vérification automatisée de l'authenticité et de la conformité des documents professionnels des soignants (pièce d'identité, diplômes, attestation RCP, KBIS).</p>
            <p><strong className="text-foreground">Base légale :</strong> Intérêt légitime (Art. 6.1.f RGPD) — sécurité de la plateforme et protection des établissements de santé.</p>
            <p><strong className="text-foreground">Données traitées :</strong> Documents téléversés (images/PDF), nom et prénom du soignant, type de document déclaré.</p>
            <p><strong className="text-foreground">Sous-traitant IA :</strong> Anthropic PBC (Claude) — fallback : Google (Gemini via passerelle). Documents transmis via TLS 1.3, non conservés par le prestataire.</p>
            <p><strong className="text-foreground">Volume estimé :</strong> 5-50 documents/jour en phase de lancement, jusqu'à 500/jour à maturité.</p>
          </div>
        </section>

        {/* 2. Nécessité et proportionnalité */}
        <section className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-3">2. Nécessité et proportionnalité</h2>
          <div className="space-y-3">
            {[
              { ok: true, text: 'La vérification est nécessaire pour garantir que seuls des professionnels qualifiés accèdent aux missions de santé.' },
              { ok: true, text: 'Les données transmises sont limitées au strict nécessaire (document + nom pour cross-check).' },
              { ok: true, text: 'Aucune donnée de santé n\'est traitée par l\'IA.' },
              { ok: true, text: 'Les documents ne sont pas conservés par le prestataire IA au-delà du traitement.' },
              { ok: true, text: 'Une alternative manuelle existe : revue par l\'équipe Jolene en cas de rejet automatique.' },
            ].map((item, i) => (
              <div key={i} className="flex items-start gap-2 text-sm">
                <CheckCircle className="h-4 w-4 text-success mt-0.5 flex-shrink-0" />
                <span className="text-foreground">{item.text}</span>
              </div>
            ))}
          </div>
        </section>

        {/* 3. Risques identifiés */}
        <section className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-3">3. Risques identifiés et mesures</h2>
          {(() => {
            const risques = [
              { risque: 'Faux positif : document valide rejeté par l\'IA', gravite: 'Moyenne', mesure: 'Recours humain systématique. Le soignant peut demander une revue manuelle.', ok: true },
              { risque: 'Faux négatif : document frauduleux accepté', gravite: 'Haute', mesure: 'Score de confiance affiché. Documents FAIBLE confiance → revue manuelle obligatoire.', ok: true },
              { risque: 'Fuite de documents via le prestataire IA', gravite: 'Haute', mesure: 'TLS 1.3. Documents non stockés par Anthropic (API policy). SCC en place.', ok: true },
              { risque: 'Biais discriminatoire dans l\'analyse', gravite: 'Moyenne', mesure: 'L\'IA vérifie uniquement type/authenticité, pas d\'évaluation subjective.', ok: true },
              { risque: 'Décision automatisée sans recours (Art. 22)', gravite: 'Haute', mesure: 'Verdict EN_ATTENTE pour tout doute. Aucun rejet définitif sans possibilité de recours.', ok: true },
              { risque: 'Indisponibilité du prestataire IA', gravite: 'Faible', mesure: 'Fallback Anthropic → Gemini. Si les deux échouent, verdict EN_ATTENTE (revue manuelle).', ok: true },
            ];
            const graviteClass = (g: string) => g === 'Haute' ? 'text-destructive' : g === 'Moyenne' ? 'text-warning' : 'text-muted-foreground';
            return (
              <>
                {/* Desktop table */}
                <div className="hidden md:block overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border">
                        <th className="py-2 px-3 text-left font-medium text-muted-foreground">Risque</th>
                        <th className="py-2 px-3 text-left font-medium text-muted-foreground">Gravité</th>
                        <th className="py-2 px-3 text-left font-medium text-muted-foreground">Mesure d'atténuation</th>
                        <th className="py-2 px-3 text-left font-medium text-muted-foreground">Statut</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border/50">
                      {risques.map((row, i) => (
                        <tr key={i}>
                          <td className="py-2.5 px-3 text-foreground">{row.risque}</td>
                          <td className="py-2.5 px-3"><span className={`text-xs font-semibold ${graviteClass(row.gravite)}`}>{row.gravite}</span></td>
                          <td className="py-2.5 px-3 text-muted-foreground">{row.mesure}</td>
                          <td className="py-2.5 px-3"><CheckCircle className="h-4 w-4 text-success" /></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* Mobile cards */}
                <div className="md:hidden space-y-3">
                  {risques.map((row, i) => (
                    <div key={i} className="card-base space-y-2">
                      <div className="flex items-start justify-between gap-2">
                        <p className="text-sm font-medium text-foreground flex-1">{row.risque}</p>
                        <CheckCircle className="h-4 w-4 text-success shrink-0 mt-0.5" />
                      </div>
                      <div className="flex items-center gap-2 text-xs">
                        <span className="text-muted-foreground">Gravité :</span>
                        <span className={`font-semibold ${graviteClass(row.gravite)}`}>{row.gravite}</span>
                      </div>
                      <p className="text-xs text-muted-foreground">{row.mesure}</p>
                    </div>
                  ))}
                </div>
              </>
            );
          })()}
        </section>

        {/* 4. Droits des personnes */}
        <section className="card-base">
          <h2 className="text-base font-semibold text-foreground mb-3">4. Droits des personnes concernées</h2>
          <div className="space-y-2 text-sm">
            {[
              'Information préalable : mention explicite dans les CGU (Art. 3.2) et la politique de confidentialité (Art. 6.2).',
              'Droit d\'accès : le soignant voit le résultat de vérification (verdict, motif) dans son espace Documents.',
              'Droit de contestation : bouton "Demander une revue manuelle" disponible sur chaque document rejeté.',
              'Droit à l\'effacement : suppression de compte entraîne anonymisation des résultats IA (fn_supprimer_mon_compte).',
              'Audit trail : chaque vérification IA est journalisée (action DOCUMENT_VERIFICATION_AUTO, rétention 5 ans).',
            ].map((item, i) => (
              <div key={i} className="flex items-start gap-2">
                <CheckCircle className="h-4 w-4 text-success mt-0.5 flex-shrink-0" />
                <span className="text-foreground">{item}</span>
              </div>
            ))}
          </div>
        </section>

        {/* 5. Conclusion */}
        <section className="card-base bg-success/5 border-success/20">
          <h2 className="text-base font-semibold text-foreground mb-3">5. Conclusion</h2>
          <p className="text-sm text-foreground">
            Le traitement est proportionné à la finalité poursuivie. Les mesures d'atténuation couvrent l'ensemble des risques identifiés.
            Le niveau de risque résiduel est <strong>acceptable</strong>. Aucune consultation préalable de la CNIL n'est requise (Art. 36 RGPD).
          </p>
          <p className="text-xs text-muted-foreground mt-3">
            DPIA réalisée le 09/04/2026 — Prochaine révision : 09/04/2027 ou en cas de modification significative du traitement.
          </p>
        </section>
      </div>
    </LayoutAdmin>
  );
}
