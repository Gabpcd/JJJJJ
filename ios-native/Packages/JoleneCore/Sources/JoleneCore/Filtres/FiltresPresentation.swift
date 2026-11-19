import Foundation

/// Textes et mise en forme des recherches sauvegardées et de l'alerte rapide (L4-T4), repris de
/// `src/pages/PageRecherchesSauvegardees.tsx` (route `/soignant/parametres/recherches-sauvegardees`, rôle SOIGNANT) et de
/// la confirmation d'alerte de `src/pages/RechercheMissions.tsx` (l.175-226, l.639-670). Aucun texte juridique ; les
/// textes tutoyés du web passent au vouvoiement (décision 9 du lot 1, liste `vouvoiements`) ; les refus serveur sont
/// affichés tels quels (`IssueFiltre.refusee`). Valeurs serveur (nombre de résultats, horodatage) affichées telles
/// quelles. Textes sans équivalent web : `nonConfirmee`, `alerteNonConfirmee` (relecture qui ne confirme pas,
/// PRINCIPES §3), `alerteActiveSansFrequence`, `alerteExisteDeja` et `alerteActiveePour` (alerte existante jamais
/// réécrite, revue B8 de #1167, M1), `etablissementNonRepris` (revue B8 de #1167, m1).
public enum FiltresTextes {
    // source: PageRecherchesSauvegardees.tsx l.57 (`usePageTitle`)
    public static let titre = "Mes recherches sauvegardées"
    // source: l.136 (variante SOIGNANT)
    public static let sousTitre = "Sauvegardez vos critères de recherche missions et activez des alertes email."
    // source: l.144-145
    public static let echecListe = "Vos recherches sauvegardées n’ont pas pu être chargées."
    public static let reessayer = "Réessayer"
    // source: l.78 (toast d'échec de lecture), affiché quand une relecture échoue sur une liste déjà affichée
    public static let chargementImpossible = "Impossible de charger vos recherches sauvegardées"
    // source: l.150, l.155
    public static let vide = "Aucune recherche sauvegardée pour l'instant."
    public static let creerRecherche = "Créer une recherche"
    // source: l.198
    public static let allerRecherche = "Aller à la recherche"
    // source: l.183-192 (titres et libellés des boutons d'icône)
    public static let activerAlertes = "Activer alertes"
    public static let desactiverAlertes = "Désactiver alertes"
    public static let modifier = "Modifier"
    public static let supprimer = "Supprimer"
    // source: l.87 (`confirm`)
    public static func confirmationSuppression(nom: String) -> String { "Supprimer la recherche « \(nom) » ?" }
    // source: l.90, l.93, l.103, l.106, l.275, l.278
    public static let erreurSuppression = "Erreur suppression"
    public static let supprimee = "Recherche supprimée"
    public static let erreurMiseAJour = "Erreur mise à jour"
    public static let alerteActivee = "Alerte activée"
    public static let alerteDesactivee = "Alerte désactivée"
    public static let miseAJour = "Recherche mise à jour"
    // source: l.265
    public static let nomRequis = "Nom requis"
    // source: l.286-290 et libellés du formulaire (variante « alertes disponibles », toujours celle du soignant :
    // `useCapaciteAlertesRecherches`)
    public static let modifierTitre = "Modifier la recherche"
    public static let modifierDescription = "Renommez votre recherche et changez ses préférences d’alertes. Pour modifier les critères, créez une nouvelle sauvegarde depuis la page de recherche."
    public static let nom = "Nom"
    public static let alertesEmail = "Alertes email"
    public static let frequence = "Fréquence"
    public static let annuler = "Annuler"
    public static let enregistrer = "Enregistrer"
    // source: l.207-215
    public static let aideTitre = "Comment fonctionnent les alertes ?"
    public static let aideIntro = "Les alertes sont envoyées par email selon la fréquence choisie :"
    public static let aideFrequences: [(titre: String, texte: String)] = [
        ("Toutes les heures", "recherche de nouveaux résultats au passage du traitement horaire."),
        ("Quotidien", "au moins 24 h entre deux vérifications."),
        ("Hebdomadaire", "au moins 7 jours entre deux vérifications."),
    ]
    public static let aideEnvoi = "Un email est envoyé uniquement si de nouveaux résultats correspondent à vos filtres. Un retard du service peut décaler son envoi."
    // source: l.216-219 (le lien mène aux préférences natives, `CibleNotification.preferences`)
    public static let aideDesactivation = "Vous pouvez désactiver toutes les alertes email globalement dans"
    public static let aideLienPreferences = "Paramètres → Notifications"

    /// Relecture qui ne montre pas la modification demandée (PRINCIPES §3) : jamais un succès annoncé.
    public static let nonConfirmee = "La modification n’a pas pu être confirmée. Réessayez."
    /// Alerte active dont la fréquence n'est pas lisible : libellé neutre (le web lirait une fréquence absente).
    public static let alerteActiveSansFrequence = "🔔 Alertes actives"

    // MARK: Alerte rapide (Explorer)

    // source: RechercheMissions.tsx l.437 (libellé de l'action, emoji retiré du libellé VoiceOver par le bouton)
    public static let alerteRapideAction = "Me prévenir des prochaines missions"
    // source: l.643
    public static let alerteRapideTitre = "🔔 Créer une alerte missions"
    // source: l.662-667
    public static let alerteRapideAnnuler = "Annuler"
    public static let alerteRapideActiver = "Activer l'alerte"
    // source: l.185 (vouvoyé : « Impossible de vérifier vos alertes existantes. Réessayez. » est déjà au vouvoiement)
    public static let alerteVerificationImpossible = "Impossible de vérifier vos alertes existantes. Réessayez."
    // source: l.199, l.213, l.221
    public static let alerteActivationImpossible = "Impossible d'activer l'alerte"
    public static let alerteCreationImpossible = "Impossible de créer l'alerte"
    public static let alerteEnregistrementImpossible = "Impossible d’enregistrer l’alerte. Réessayez."
    // source: l.216 (création : alerte toutes les heures)
    public static let alerteCreee = "Alerte créée : les nouvelles missions seront vérifiées toutes les heures."
    /// Relecture qui ne montre pas l'alerte active (PRINCIPES §3).
    public static let alerteNonConfirmee = "L’alerte n’a pas pu être confirmée. Réessayez."

    /// Recherche identique dont l'alerte est déjà active : rien n'est écrit, sa fréquence réelle est annoncée (le web dit
    /// « vérifiées toutes les heures » quelle que soit la fréquence, l.203).
    public static func alerteExisteDeja(frequence: FrequenceAlerte?) -> String {
        guard let frequence else { return "Une alerte existe déjà pour cette recherche." }
        return "Une alerte existe déjà pour cette recherche (\(FiltresPresentation.rythme(frequence)))."
    }

    /// Recherche identique sans alerte, activée à sa fréquence enregistrée.
    public static func alerteActiveePour(frequence: FrequenceAlerte?) -> String {
        guard let frequence else { return "Alerte activée pour cette recherche." }
        return "Alerte activée pour cette recherche (\(FiltresPresentation.rythme(frequence)))."
    }

    /// Filtre établissement d'Explorer (`?etablissement=`) : refusé par le validateur serveur (clé hors liste), jamais
    /// repris par l'alerte — annoncé dans la confirmation (revue B8 de #1167, m1).
    public static let etablissementNonRepris = "Le filtre établissement n’est pas repris : l’alerte porte sur tous les établissements."

    /// Description de la confirmation (l.644-659), vouvoyée ; profession absente : seconde variante du web ; filtre
    /// établissement actif : `etablissementNonRepris` ajouté.
    public static func alerteRapideDescription(profession: String?, rayonKm: Double, filtreEtablissement: Bool = false) -> String {
        let rayon = MissionPresentation.nombreJavaScript(rayonKm)
        let mission = profession.map { "une mission \($0) correspondant à vos critères" } ?? "une mission correspondant à vos critères"
        let texte = "Les nouvelles missions sont vérifiées toutes les heures. Vous recevrez un email si \(mission) (rayon \(rayon) km) est publiée. Vous pourrez modifier ou désactiver cette alerte à tout moment depuis « Mes recherches sauvegardées »."
        return filtreEtablissement ? texte + " " + etablissementNonRepris : texte
    }

    // source: RechercheMissions.tsx l.157 (toast d'application d'une recherche dans Explorer)
    public static func filtresAppliques(nom: String) -> String { "Filtres « \(nom) » appliqués" }

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1 ; aucun n'est juridique).
    public static let vouvoiements: [(web: String, natif: String)] = [
        ("Les nouvelles missions sont vérifiées toutes les heures. Tu recevras un email si une mission correspondant à tes critères (rayon 50 km) est publiée. Tu pourras modifier ou désactiver cette alerte à tout moment depuis « Mes recherches sauvegardées ».",
         alerteRapideDescription(profession: nil, rayonKm: 50)),
    ]
}

/// Mise en forme d'une recherche sauvegardée (`PageRecherchesSauvegardees.tsx` l.164-178).
public enum FiltresPresentation {
    /// `FREQUENCE_LABELS` (l.49-53), dans l'ordre du sélecteur.
    public static func libelle(_ frequence: FrequenceAlerte) -> String {
        switch frequence {
        case .immediate: return "Toutes les heures"
        case .quotidienne: return "Quotidien"
        case .hebdomadaire: return "Hebdomadaire"
        }
    }

    /// Rythme d'une alerte dans les messages de l'alerte rapide : « toutes les heures », « chaque jour », « chaque semaine ».
    public static func rythme(_ frequence: FrequenceAlerte) -> String {
        switch frequence {
        case .immediate: return "toutes les heures"
        case .quotidienne: return "chaque jour"
        case .hebdomadaire: return "chaque semaine"
        }
    }

    /// « 🔔 Alertes toutes les heures » / « 🔕 Alertes désactivées » (l.166-169).
    public static func etatAlerte(_ recherche: FiltreSauvegarde) -> String {
        guard recherche.alerteActive else { return "🔕 Alertes désactivées" }
        guard let frequence = recherche.frequence else { return FiltresTextes.alerteActiveSansFrequence }
        return "🔔 Alertes \(libelle(frequence).lowercased())"
    }

    /// « Dernier check : 02 nov. 08:00 » (`format(…, 'dd MMM HH:mm', { locale: fr })`, l.172), heure de Paris ;
    /// `nil` si l'horodatage est absent ou illisible.
    public static func dernierCheck(_ recherche: FiltreSauvegarde) -> String? {
        guard let brut = recherche.dernierCheckLe, let instant = try? DateHeureParis.instantJolene(brut) else { return nil }
        let p = DateHeureParis.parties(instant)
        guard (1...12).contains(p.mois) else { return nil }
        let jour = p.jour < 10 ? "0\(p.jour)" : "\(p.jour)"
        let heure = p.heure < 10 ? "0\(p.heure)" : "\(p.heure)"
        let minute = p.minute < 10 ? "0\(p.minute)" : "\(p.minute)"
        return "Dernier check : \(jour) \(DateHeureParis.moisCourts[p.mois - 1]) \(heure):\(minute)"
    }

    /// « 3 résultats » si le dernier passage en a trouvé (l.173-178), `nil` sinon.
    public static func resultats(_ recherche: FiltreSauvegarde) -> String? {
        let n = recherche.nbResultatsDernierCheck
        guard n > 0 else { return nil }
        return "\(n) résultat\(n > 1 ? "s" : "")"
    }

    /// Nom de base de l'alerte rapide (`RechercheMissions.tsx` l.178-179) : `Alerte missions <libellé>` pour la profession choisie dans
    /// Explorer, sinon celle du profil, sinon `Alerte missions`.
    public static func nomBaseAlerte(filtres: ExplorerFiltres, profile: SoignantProfile) -> String {
        guard let profession = professionAlerte(filtres: filtres, profile: profile) else { return "Alerte missions" }
        return "Alerte missions \(profession)"
    }

    /// Libellé de la profession de l'alerte (`professionAlerteLabel`, `RechercheMissions.tsx` l.267-269), `nil` sans profession.
    public static func professionAlerte(filtres: ExplorerFiltres, profile: SoignantProfile) -> String? {
        let code = filtres.profession.isEmpty ? profile.profession : filtres.profession
        return code.isEmpty ? nil : MissionPresentation.professionLabel(code)
    }
}
