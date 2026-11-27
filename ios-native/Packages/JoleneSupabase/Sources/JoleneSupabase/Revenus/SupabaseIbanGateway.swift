import Foundation
import JoleneCore
import Supabase

/// `IbanPort` sur Supabase (lot 3, T14b, B9 ; D20, TJ6), port de `SectionIbanPrime` (`SectionPaiements.tsx`
/// l.241-272). Contrats : fiches `fn_consulter_mon_iban` et `fn_enregistrer_mon_iban` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` (dump `supabase/schema/public.sql` l.26027-26075 et l.32788-32847 ;
/// GRANT EXECUTE `authenticated` l.82809 et l.83240). `fn_lier_iban_verifie_document` (service_role seul) n'est jamais
/// appelée : `fn_enregistrer_mon_iban` la délègue côté serveur. Aucune migration.
///
/// - Consulter : `{error}` → « Non authentifié » = session expirée, sinon message serveur ; `iban_renseigne` et
///   `iban_verifie` booléens exigés, sinon contrat ; `verification_requise` absente (profil introuvable, l.25938) =
///   même formule que le serveur (`renseigne && !verifie`, l.25963) ; `iban_last4` exigé quand l'IBAN est vérifié.
/// - Enregistrer : un seul POST, jamais renvoyé. `{success:true}` → relecture `consulter`, succès seulement si elle est
///   probante (`IbanRelecture`, D20) ; `{success:false, error_code, [error]}` → `.refuse` (le web affiche un faux
///   succès quand `error` manque, l.259-262 : jamais ici) ; `NON_AUTHENTIFIE` → session expirée ; `PROFIL_INTROUVABLE`
///   → contrat, message générique (TJ6, règle 2) ; tout autre corps → contrat.
/// Rien n'est journalisé (ni IBAN, ni titulaire, ni quatre derniers caractères).
public struct SupabaseIbanGateway: IbanPort {
    public static let consulterRPC = "fn_consulter_mon_iban"
    public static let enregistrerRPC = "fn_enregistrer_mon_iban"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func consulter(context: MissionReadContext) async throws -> ConsultationIban {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.consulterRPC, fallback: IbanTextes.erreurGenerique)
        return try Self.consultation(reponse)
    }

    public func enregistrer(iban: String, titulaire: String, context: MissionReadContext) async throws -> ResultatIban {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.enregistrerRPC,
                                                    params: ["p_iban": .string(iban), "p_titulaire": .string(titulaire)],
                                                    fallback: IbanTextes.erreurGenerique)
        if reponse.success == true, reponse.erreur == nil, reponse.codeErreur == nil {
            return try IbanRelecture.enregistrement(relue: try await consulter(context: context), ibanEnvoye: iban)
        }
        guard reponse.success == false || reponse.codeErreur != nil || reponse.erreur != nil else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let code = reponse.codeErreur
        if code == CodeRefusIban.nonAuthentifie.rawValue || reponse.erreur.map(RPCResponse.estNonAuthentifie) == true {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        if code == CodeRefusIban.profilIntrouvable.rawValue {
            throw JoleneError(.contract, IbanTextes.erreurGenerique)
        }
        return .refuse(code: code, message: reponse.erreur)
    }

    /// Décodage strict de `fn_consulter_mon_iban` (aucun défaut affiché à la place d'une valeur absente).
    static func consultation(_ reponse: RPCResponse) throws -> ConsultationIban {
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            throw JoleneError(.unknown, erreur)
        }
        let contrat = JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        guard let renseigne = reponse.bool("iban_renseigne"), let verifie = reponse.bool("iban_verifie") else { throw contrat }
        let requise: Bool
        if let brute = reponse.valeur("verification_requise") {
            guard let valeur = brute.boolValue else { throw contrat }
            requise = valeur
        } else {
            requise = renseigne && !verifie
        }
        let last4 = reponse.string("iban_last4").flatMap { $0.isEmpty ? nil : $0 }
        if renseigne && verifie && last4 == nil { throw contrat }
        return ConsultationIban(ibanRenseigne: renseigne, ibanVerifie: verifie, verificationRequise: requise,
                                ibanLast4: last4, ibanTitulaire: reponse.string("iban_titulaire"))
    }
}
