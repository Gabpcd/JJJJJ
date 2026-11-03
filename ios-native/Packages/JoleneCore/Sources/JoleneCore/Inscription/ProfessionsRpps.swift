import Foundation

/// Listes RPPS de `src/lib/constantes.ts`, recopiées verbatim et gardées par le vecteur de dérive
/// `professions-rpps.json` (correction 20, décision 11 du lot 3). Ce n'est pas une règle juridique
/// nouvelle : la même liste que le web (`InscriptionSoignant.tsx` l.201-208, l.221-225) et que
/// `register-soignant` (l.49, l.260-261), qui seul vérifie le numéro.
public enum ProfessionsRpps {
    /// `PROFESSIONS_SANS_RPPS` (constantes.ts l.55) : vérification par diplôme et pièce d'identité.
    public static let sansRpps = ["AS", "AES", "AUXILIAIRE_PUERICULTURE"]

    /// `PROFESSIONS_RPPS_REQUIS` (constantes.ts l.61) : numéro exigé à l'inscription.
    public static let rppsRequis = ["MEDECIN", "DENTISTE", "SAGE_FEMME", "PHARMACIEN"]

    public static func estSansRpps(_ profession: String) -> Bool { sansRpps.contains(profession) }

    public static func exigeRpps(_ profession: String) -> Bool { rppsRequis.contains(profession) }
}
