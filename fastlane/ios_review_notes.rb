# Notes pour la revue Apple de l'app Swift (lane `ios submit_native`, docs/mobile-swift/APP_STORE.md,
# section « Notes pour la revue et compte de démonstration »).
#
# Personne ne se connecte au site App Store Connect : tout passe par l'API, avec la clé du job `soumettre`.
# La lane écrit SEULEMENT le champ `notes` de l'appStoreReviewDetail de la version modifiable : jamais les
# identifiants du compte de démonstration, ni les contacts, ni `demoAccountRequired`. Elle ne passe donc pas
# par `upload_to_app_store(app_review_information: …)` : deliver y remet `demoAccountRequired` à faux dès que
# le nom ou le mot de passe manque (fastlane 2.240.1, deliver/lib/deliver/upload_metadata.rb, review_information).
#
# Ni le nom ni le mot de passe du compte de démonstration ne sont affichés ou journalisés, pas même masqués ;
# le contenu des notes non plus (les notes de la version précédente portent les identifiants du compte
# établissement) : les messages ne citent que des longueurs et des états.
require_relative 'ios_review_submission'

module IosReviewSubmission
  # Ordre de la lane submit_native, son seul appelant : pré-vol des notes en lecture seule, gardes de la revue en
  # cours (attente du build, annulation éventuelle d'une revue en attente), écriture des notes, puis soumission.
  # Un verrou qui échoue lève avant `soumettre` : rien n'est soumis.
  def self.enchainer!(notes:, guard:, build_absent:, soumettre:)
    notes.verifier!
    return :already_submitted if guard.prepare!(&build_absent) == :already_submitted
    notes.appliquer!
    soumettre.call
    :submitted
  end

  # Accès App Store Connect des notes. Les lectures de version passent par la même méthode Spaceship que deliver
  # (`App#get_edit_app_store_version`, appelée par `ensure_version!`, l'envoi de la fiche et `submit_for_review`) :
  # la version contrôlée ici est celle que deliver éditera puis soumettra.
  class ReviewNotesGateway
    def initialize(client:, app:)
      @client, @app = client, app
      raise Failure, 'Apple app is missing' if app.nil? || app.id.to_s.empty?
    end

    def edit_version
      @app.get_edit_app_store_version(platform: 'IOS')
    end

    # Même requête que `Spaceship::ConnectAPI::App#ensure_version!` quand aucune version modifiable n'existe.
    def create_version(marketing)
      @client.post_app_store_version(app_id: @app.id, attributes: { versionString: marketing, platform: 'IOS' })
    end

    # Une erreur d'Apple peut citer le corps de la réponse : seule sa classe est reprise.
    def review_detail(version_id)
      @client.get_app_store_review_detail(app_store_version_id: version_id).to_models.first
    rescue StandardError => error
      raise Failure, "Fiche « Informations pour la vérification de l'app » absente ou illisible (#{error.class}) : compte de démonstration non vérifiable, soumission arrêtée (voir #{ReviewNotes::DOC})"
    end

    def update_notes(detail_id, notes)
      @client.patch_app_store_review_detail(app_store_review_detail_id: detail_id, attributes: { notes: notes })
    rescue StandardError => error
      raise Failure, "Écriture des notes pour la revue refusée par Apple (#{error.class}) : soumission arrêtée (voir #{ReviewNotes::DOC})"
    end
  end

  class ReviewNotes
    FICHIER = 'config/ios-review-notes-2.0.txt'
    DOC = 'docs/mobile-swift/APP_STORE.md, section « Notes pour la revue et compte de démonstration »'
    SEPARATEUR = '--- Notes de la version précédente ---'
    # Limite Apple du champ « Notes » des informations pour la vérification de l'app.
    LIMITE = 4000
    EMAIL = /[^\s@<>"'()]+@[^\s@<>"'()]+\.[A-Za-z]{2,}/

    def self.normaliser(texte)
      texte.to_s.gsub(/\r\n?/, "\n").strip
    end

    # Le bloc vient d'un dépôt public : jamais d'adresse (donc jamais d'identifiant), jamais le séparateur, et
    # assez court pour laisser de la place aux notes précédentes.
    def self.valider_bloc!(bloc)
      texte = normaliser(bloc)
      raise Failure, "#{FICHIER} est vide (voir #{DOC})" if texte.empty?
      raise Failure, "#{FICHIER} contient une adresse e-mail : aucun identifiant dans le dépôt public (voir #{DOC})" if texte.match?(EMAIL)
      if texte.lines.any? { |ligne| ligne.strip == SEPARATEUR }
        raise Failure, "#{FICHIER} contient la ligne de séparation « #{SEPARATEUR} » (voir #{DOC})"
      end
      if texte.length + SEPARATEUR.length + 2 > LIMITE
        raise Failure, "#{FICHIER} fait #{texte.length} caractères : avec le séparateur, il dépasse seul la limite Apple de #{LIMITE} (voir #{DOC})"
      end
      texte
    end

    # Verrou : sans compte de démonstration complet, Apple ne peut pas se connecter et refuse la version.
    # Le message nomme ce qui manque, jamais une valeur.
    def self.exiger_compte_demo!(detail, marketing)
      manques = if detail.nil?
        ['fiche absente']
      else
        [
          ('« Connexion requise » décoché (demoAccountRequired faux)' unless detail.demo_account_required == true),
          ('nom du compte vide' if detail.demo_account_name.to_s.strip.empty?),
          ('mot de passe vide' if detail.demo_account_password.to_s.strip.empty?)
        ].compact
      end
      return true if manques.empty?
      raise Failure, "Compte de démonstration incomplet pour la version #{marketing} dans App Store Connect (#{manques.join(', ')}) : " \
        "rien n'est soumis. Le saisir par l'API avant de relancer (voir #{DOC})"
    end

    # Fonction pure. Statuts : :inchange (le bloc est déjà en tête, rien à écrire), :remplace (un bloc
    # précédent, placé avant le séparateur, est remplacé), :ajoute (le bloc et le séparateur passent devant les
    # notes existantes). Le bloc n'est jamais doublé ; au-delà de LIMITE caractères, échec.
    def self.composer(bloc:, existantes:)
      bloc = valider_bloc!(bloc)
      actuelles = normaliser(existantes)
      lignes = actuelles.split("\n", -1)
      positions = lignes.each_index.select { |i| lignes[i].strip == SEPARATEUR }
      raise Failure, "Les notes pour la revue contiennent #{positions.length} lignes de séparation : composition ambiguë, rien n'est soumis (voir #{DOC})" if positions.length > 1

      if positions.one?
        tete = lignes[0...positions.first].join("\n").strip
        anciennes = lignes[(positions.first + 1)..].join("\n").strip
        statut = tete == bloc ? :inchange : :remplace
      else
        anciennes = actuelles
        statut = :ajoute
        if actuelles == bloc || actuelles.start_with?("#{bloc}\n")
          statut = :inchange
          anciennes = actuelles.delete_prefix(bloc).strip
        end
      end

      notes = statut == :inchange ? actuelles : [bloc, '', anciennes.empty? ? SEPARATEUR : "#{SEPARATEUR}\n#{anciennes}"].join("\n")
      if notes.scan(bloc).length != 1
        raise Failure, "Le bloc de #{FICHIER} apparaîtrait #{notes.scan(bloc).length} fois dans les notes pour la revue : rien n'est soumis (voir #{DOC})"
      end
      if statut != :inchange && notes.length > LIMITE
        raise Failure, "Notes pour la revue trop longues : #{notes.length} caractères pour #{LIMITE} au plus " \
          "(bloc #{bloc.length}, notes précédentes #{anciennes.length}) ; raccourcir #{FICHIER}, rien n'est soumis (voir #{DOC})"
      end
      { statut: statut, notes: notes, anciennes_avec_email: anciennes.match?(EMAIL) }
    end

    def initialize(gateway:, marketing_version:, bloc:, journal: ->(_message) {})
      @gateway, @marketing, @journal = gateway, marketing_version.to_s, journal
      @bloc = ReviewNotes.valider_bloc!(bloc)
      raise Failure, 'Invalid iOS release configuration' unless @marketing.match?(/\A\d+(?:\.\d+){0,2}\z/)
    end

    # Pré-vol en lecture seule, avant les gardes de la revue en cours (donc avant toute annulation) : si la version
    # que deliver éditera existe déjà, ce doit être la version configurée, avec un compte de démonstration complet et
    # des notes composables. Sinon elle sera créée par appliquer!, qui refait tous les contrôles.
    def verifier!
      @version_vue = @gateway.edit_version
      @verifie = true
      if @version_vue.nil?
        @journal.call("Aucune version iOS modifiable dans App Store Connect : la version #{@marketing} sera créée après les gardes, puis contrôlée.")
        return :a_creer
      end
      exiger_version!(@version_vue)
      lire_et_composer(@version_vue)
      @journal.call("Pré-vol des notes pour la revue : version #{@marketing} trouvée, compte de démonstration renseigné.")
      :pret
    end

    # Après les gardes, avant la soumission : la version est retrouvée (ou créée si absente), le verrou rejoué,
    # puis seul le champ `notes` est écrit et relu.
    def appliquer!
      raise Failure, 'Notes pour la revue appliquées sans pré-vol' unless @verifie
      version = @gateway.edit_version
      if version.nil?
        raise Failure, "La version #{@marketing} vue au pré-vol n'est plus modifiable : rien n'est soumis (voir #{DOC})" if @version_vue
        @gateway.create_version(@marketing)
        version = @gateway.edit_version
        raise Failure, "Version #{@marketing} introuvable après sa création dans App Store Connect : rien n'est soumis (voir #{DOC})" if version.nil?
        @journal.call("Version iOS #{@marketing} créée dans App Store Connect ; sa fiche de vérification est contrôlée avant toute écriture.")
      elsif @version_vue.nil? || version.id != @version_vue.id
        raise Failure, "La version modifiable a changé depuis le pré-vol : rien n'est soumis, relancer le workflow entier (voir #{DOC})"
      end
      exiger_version!(version)
      detail, composition = lire_et_composer(version)
      unless composition[:anciennes_avec_email]
        @journal.call("Avertissement : les notes de la version précédente ne contiennent aucune adresse e-mail ; le bloc y renvoie pourtant pour les identifiants du compte établissement (voir #{DOC}).")
      end
      if composition[:statut] == :inchange
        @journal.call('Notes pour la revue déjà à jour (bloc 2.0 en tête) : aucune écriture.')
        return :inchange
      end
      raise Failure, "Fiche de vérification sans identifiant Apple : rien n'est soumis (voir #{DOC})" if detail.id.to_s.empty?
      @gateway.update_notes(detail.id, composition[:notes])
      relu = @gateway.review_detail(version.id)
      ReviewNotes.exiger_compte_demo!(relu, @marketing)
      unless ReviewNotes.normaliser(relu.notes) == ReviewNotes.normaliser(composition[:notes])
        raise Failure, "Notes pour la revue relues différentes de celles écrites : rien n'est soumis (voir #{DOC})"
      end
      @journal.call("Notes pour la revue #{composition[:statut] == :remplace ? 'remplacées' : 'complétées'} : bloc 2.0 en tête, #{composition[:notes].length} caractères sur #{LIMITE}.")
      composition[:statut]
    end

    private

    # deliver renommerait une autre version modifiable (`ensure_version!`) : refusé ici, avant toute écriture.
    def exiger_version!(version)
      unless version.version_string == @marketing && version.platform == 'IOS'
        raise Failure, "La version iOS modifiable d'App Store Connect est #{version.version_string.inspect}, pas #{@marketing} : " \
          "deliver la renommerait avec sa fiche ; rien n'est soumis (voir #{DOC})"
      end
      raise Failure, "Version #{@marketing} sans identifiant Apple : rien n'est soumis (voir #{DOC})" if version.id.to_s.empty?
    end

    def lire_et_composer(version)
      detail = @gateway.review_detail(version.id)
      ReviewNotes.exiger_compte_demo!(detail, @marketing)
      [detail, ReviewNotes.composer(bloc: @bloc, existantes: detail.notes)]
    end
  end
end
