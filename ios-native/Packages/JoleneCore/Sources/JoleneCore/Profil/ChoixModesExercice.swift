import Foundation

/// Port de `src/components/ChoixModesExercice.tsx` (préférences de recherche : ne modifie pas le statut
/// d'exercice déclaré) et de `useTypesExerciceAutorises` : quels modes proposer, et quels messages
/// afficher, à partir des contrats acceptés et de la réponse de `fn_types_exercice_autorises` (table
/// paramétrée `regles_exercice_profession`, aucune règle de mode d'exercice en dur : HARD STOP n°4).
/// Libellés et messages verbatim web (apostrophes typographiques comprises), gardés par
/// `ProfilVerbatimTests`. Logique de bascule : `ModesExercice` (golden `preferences-modes-exercice.json`).
///
/// Point de fusion T8 : l'écran de complétion de l'inscription (`CompletionProfilScreen`) réutilise ce
/// même port (`LOT3_PLAN.md` §3 T8-T9, « le même composant »).
public struct ChoixModesExercice: Equatable, Sendable {
    public enum Textes {
        /// `<legend>` l.26.
        public static let titre = "Modes d’exercice recherchés"
        /// l.27.
        public static let aide = "Le mode salarié inclut les CDD et les CDD courts. Vous pouvez sélectionner les deux modes si votre profession le permet."
        /// l.20-21.
        public static let libelleSalarie = "Salarié (CDD compris)"
        public static let libelleLiberal = "Libéral"
        /// l.41.
        public static let chargement = "Vérification des modes d’exercice autorisés…"
        /// l.43.
        public static let indisponible = "Vérification temporairement indisponible. Le mode salarié reste accessible. Vos choix sont conservés ; l’ajout du libéral nécessite une vérification."
        /// l.44.
        public static let reessayer = "Réessayer la vérification"
        /// l.46.
        public static let liberalNonPropose = "Le mode libéral n’est pas proposé pour votre profession sur Jolene. Le mode salarié comprend les CDD et les CDD courts."
        /// l.47.
        public static let anciennePreference = "Une ancienne préférence n’est plus autorisée pour votre profession. Décochez-la pour actualiser vos choix."
        /// l.48.
        public static let aucunMode = "Sélectionnez au moins un mode d’exercice."
    }

    public struct Option: Equatable, Sendable, Identifiable {
        public var mode: PreferenceModeExercice
        public var libelle: String
        public var autorise: Bool
        public var selectionne: Bool

        public var id: String { mode.rawValue }
    }

    /// Modes affichés (`modes.filter(mode => mode.autorise || mode.selectionne)`), salarié d'abord.
    public var options: [Option]
    public var chargement: Bool
    public var indisponible: Bool
    public var liberalNonPropose: Bool
    public var anciennePreference: Bool
    public var aucunMode: Bool

    /// - Parameter typesAutorises: réponse de `fn_types_exercice_autorises` ; nil tant qu'elle n'est pas
    ///   connue (chargement, indisponibilité, profession absente).
    public static func presenter(valeur: [String], typesAutorises: [String]?, chargement: Bool,
                                 indisponible: Bool) -> ChoixModesExercice {
        let connus = typesAutorises != nil
        let types = typesAutorises ?? []
        let salarieAutorise = !connus || types.contains { $0 == "SALARIE" || $0 == "MIXTE" }
        let liberalAutorise = types.contains { $0 == "LIBERAL" || $0 == "MIXTE" }
        let salarieSelectionne = ModesExercice.estSelectionne(valeur, mode: .salarie)
        let liberalSelectionne = ModesExercice.estSelectionne(valeur, mode: .liberal)
        let modes = [
            Option(mode: .salarie, libelle: Textes.libelleSalarie, autorise: salarieAutorise, selectionne: salarieSelectionne),
            Option(mode: .liberal, libelle: Textes.libelleLiberal, autorise: liberalAutorise, selectionne: liberalSelectionne),
        ]
        return ChoixModesExercice(
            options: modes.filter { $0.autorise || $0.selectionne },
            chargement: chargement,
            indisponible: indisponible,
            liberalNonPropose: connus && !liberalAutorise,
            anciennePreference: connus && ((!liberalAutorise && liberalSelectionne) || (!salarieAutorise && salarieSelectionne)),
            aucunMode: valeur.isEmpty)
    }

    /// Bascule d'une case : `modifierPreferenceModeExercice`, refusée si elle viderait la liste
    /// (`onTypesContratChange={valeur => { if (valeur.length) setTypesContrat(valeur); }}`,
    /// `ProfilSoignant.tsx` l.478).
    public static func basculer(_ valeur: [String], mode: PreferenceModeExercice, selectionne: Bool) -> [String] {
        let suivante = ModesExercice.modifier(valeur, mode: mode, selectionne: selectionne)
        return suivante.isEmpty ? valeur : suivante
    }
}
