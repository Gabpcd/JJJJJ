import SwiftUI

/// Jauge et liste des critères d'un nouveau mot de passe, port de `JaugeForce` / `Critere`
/// (`src/components/soignant/ChangementMotDePasse.tsx` l.210-242) : barre de progression (`score / 5`),
/// « Force : <libellé> » (six libellés, l.211), puis les cinq critères avec coche quand ils sont remplis.
/// **Aucune règle ici** : chaque critère arrive déjà évalué par le cœur (`ForceMotDePasse`, port de
/// `calculerForce` l.198-208, vecteurs golden T2) ; la vue compte les critères remplis comme le web
/// (`Object.values(criteres).filter(Boolean).length`) et choisit libellé et ton. L'écran (T11) n'affiche la
/// jauge qu'une fois la saisie commencée (`nouveauMdp.length > 0`), comme le web.
///
/// Tons de la barre (`couleurs` l.212 : destructive ×2, warning ×2, primary, success) → `StatusPill.Tone`
/// `error`, `warning`, `info` (mauve : le rose est déjà pris par `error`), `success` ; la force est aussi
/// écrite en toutes lettres, la couleur ne porte jamais seule l'information. Posée sur une carte ou un écran.
public struct PasswordCriteriaList: View {
    public struct Criterion: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var isMet: Bool

        public init(id: String, label: String, isMet: Bool) { self.id = id; self.label = label; self.isMet = isMet }
    }

    /// `const labels = ['Très faible', 'Faible', 'Moyen', 'Bon', 'Fort', 'Excellent']` (l.211).
    nonisolated public static let strengthLabels = ["Très faible", "Faible", "Moyen", "Bon", "Fort", "Excellent"]
    /// `Force : <strong>…</strong>` (l.222).
    nonisolated public static let strengthPrefix = "Force : "
    /// Tons par score, dans l'ordre des `couleurs` du web.
    nonisolated static let strengthTones: [StatusPill.Tone] = [.error, .error, .warning, .warning, .info, .success]

    nonisolated public static let metInkHSL = JoleneColor.cyan900HSL
    nonisolated public static let unmetInkHSL = JoleneColor.bubblegumHSL
    nonisolated public static let strengthInkHSL = JoleneColor.midnightHSL
    nonisolated public static let trackHSL = JoleneColor.mauve100HSL

    /// Les cinq critères du web (clés et ordre de `criteres`, libellés des `<Critere>` l.225-229), valeurs
    /// fournies par le cœur.
    nonisolated public static func criteresWeb(longueur: Bool, majuscule: Bool, minuscule: Bool, chiffre: Bool,
                                               special: Bool) -> [Criterion] {
        [
            Criterion(id: "longueur", label: "12 caractères minimum", isMet: longueur),
            Criterion(id: "majuscule", label: "1 majuscule", isMet: majuscule),
            Criterion(id: "minuscule", label: "1 minuscule", isMet: minuscule),
            Criterion(id: "chiffre", label: "1 chiffre", isMet: chiffre),
            Criterion(id: "special", label: "1 caractère spécial", isMet: special),
        ]
    }

    /// Partie calculable de la jauge.
    public struct Presentation: Equatable, Sendable {
        public var criteria: [Criterion]
        public var score: Int
        public var strengthLabel: String
        public var strengthText: String
        /// `width: (score / 5) * 100 %` : part des critères remplis, de 0 à 1.
        public var progress: Double
        public var tone: StatusPill.Tone

        public static func resolve(_ criteria: [Criterion]) -> Presentation {
            let score = criteria.filter(\.isMet).count
            let rang = min(score, PasswordCriteriaList.strengthLabels.count - 1)
            let libelle = PasswordCriteriaList.strengthLabels[rang]
            return Presentation(criteria: criteria, score: score, strengthLabel: libelle,
                                strengthText: PasswordCriteriaList.strengthPrefix + libelle,
                                progress: criteria.isEmpty ? 0 : Double(score) / Double(criteria.count),
                                tone: PasswordCriteriaList.strengthTones[min(rang, PasswordCriteriaList.strengthTones.count - 1)])
        }
    }

    /// Identifiants : la racine reçoit `identifier`, la force `<identifier>-force`, chaque critère
    /// `<identifier>-critere-<cle>`. L'écran du mot de passe (T11) passe `compte-mdp`, ce qui donne les ids
    /// `compte-mdp-critere-<cle>` du blueprint (§3 T11) et `compte-mdp-force`.
    /// Libellé vocalisé d'un critère : « <libellé web>, critère rempli / non rempli » — texte d'accessibilité sans
    /// équivalent web (le web n'a que la coche), consigné dans `DECISIONS_LOT3.md` (HARD STOP n°4, §6.7).
    nonisolated public static func strengthIdentifier(_ identifier: String) -> String { "\(identifier)-force" }
    nonisolated public static func criterionIdentifier(_ identifier: String, criterionID: String) -> String {
        "\(identifier)-critere-\(criterionID)"
    }
    nonisolated public static func criterionAccessibilityLabel(_ criterion: Criterion) -> String {
        "\(criterion.label), \(criterion.isMet ? "critère rempli" : "critère non rempli")"
    }

    private let presentation: Presentation
    private let identifier: String

    public init(criteria: [Criterion], identifier: String) {
        self.presentation = Presentation.resolve(criteria); self.identifier = identifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            GeometryReader { geometrie in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(Self.trackHSL))
                    Capsule()
                        .fill(Color(presentation.tone.iconInkHSL))
                        .frame(width: geometrie.size.width * presentation.progress)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                Text(Self.strengthPrefix).foregroundStyle(Color(Self.unmetInkHSL))
                Text(presentation.strengthLabel).fontWeight(.bold).foregroundStyle(Color(Self.strengthInkHSL))
            }
            .font(JoleneFont.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.strengthText)
            .accessibilityIdentifier(Self.strengthIdentifier(identifier))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(presentation.criteria) { critere in
                    HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.xs) {
                        Image(systemName: critere.isMet ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        Text(critere.label).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(JoleneFont.caption)
                    .foregroundStyle(Color(critere.isMet ? Self.metInkHSL : Self.unmetInkHSL))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.criterionAccessibilityLabel(critere))
                    .accessibilityIdentifier(Self.criterionIdentifier(identifier, criterionID: critere.id))
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
