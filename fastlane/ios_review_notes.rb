# Notes pour la revue Apple de l'app Swift (lane `ios submit_native`, docs/mobile-swift/APP_STORE.md,
# section « Notes pour la revue et compte de démonstration »).
#
# Personne ne se connecte au site App Store Connect : tout passe par l'API, avec la clé du job `soumettre`.
# Dans l'appStoreReviewDetail de la version modifiable, la lane écrit :
# - le champ `notes` (bloc versionné en tête, puis les notes existantes) ;
# - SEULEMENT si la version n'a pas de compte de démonstration complet : une copie, d'API à API, de la fiche de la
#   version distribuée (compte de démonstration, puis contacts et notes là où la cible est vide). Une fiche qui a
#   déjà un compte de démonstration n'est jamais écrasée.
# Elle ne passe pas par `upload_to_app_store(app_review_information: …)` : deliver y remet `demoAccountRequired` à
# faux dès que le nom ou le mot de passe manque (fastlane 2.240.1, deliver/lib/deliver/upload_metadata.rb).
#
# Aucune valeur de la fiche (compte de démonstration, contacts, texte des notes, qui porte les identifiants du compte
# établissement) n'est affichée ou journalisée, pas même masquée : les messages ne citent que des noms de champs,
# des longueurs et des états.
require 'rubygems/version'
require_relative 'ios_review_submission'

module IosReviewSubmission
  # Ordre de la lane submit_native, son seul appelant : pré-vol des notes en lecture seule, gardes de la revue en
  # cours (attente du build, annulation éventuelle d'une revue en attente), écriture de la fiche, puis soumission.
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
  # la version contrôlée ici est celle que deliver éditera puis soumettra. Une erreur d'Apple peut citer le corps de
  # la réponse, donc une valeur : seule sa classe est reprise.
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

    # Source de la copie : toutes les pages, filtrées encore une fois par ReviewNotes.choisir_source.
    def distributed_versions
      @app.get_app_store_versions(filter: { appVersionState: 'READY_FOR_DISTRIBUTION', platform: 'IOS' })
    end

    # nil quand Apple répond sans fiche (`data: null`) ; toute erreur arrête la lane : une fiche illisible n'est
    # jamais tenue pour absente, donc jamais écrasée.
    def review_detail(version_id)
      response = @client.get_app_store_review_detail(app_store_version_id: version_id)
      body = response.body
      return nil if body.is_a?(Hash) && body.key?('data') && body['data'].nil?
      response.to_models.first
    rescue Failure
      raise
    rescue StandardError => error
      raise Failure, "Fiche « Informations pour la vérification de l'app » illisible (#{error.class}) : compte de démonstration non vérifiable, soumission arrêtée (voir #{ReviewNotes::DOC})"
    end

    def create_review_detail(version_id, attributes)
      @client.post_app_store_review_detail(app_store_version_id: version_id, attributes: attributes)
    rescue StandardError => error
      raise Failure, "Création de la fiche de vérification refusée par Apple (#{error.class}) : soumission arrêtée (voir #{ReviewNotes::DOC})"
    end

    def update_review_detail(detail_id, attributes)
      @client.patch_app_store_review_detail(app_store_review_detail_id: detail_id, attributes: attributes)
    rescue StandardError => error
      raise Failure, "Copie de la fiche de vérification refusée par Apple (#{error.class}) : soumission arrêtée (voir #{ReviewNotes::DOC})"
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
    # Copie depuis la version distribuée : attribut Apple → attribut du modèle Spaceship. Le compte de démonstration
    # est copié d'un bloc ; contacts et notes seulement là où la cible est vide. Aucun autre attribut n'est écrit.
    CHAMPS_DEMO = {
      'demoAccountName' => :demo_account_name,
      'demoAccountPassword' => :demo_account_password,
      'demoAccountRequired' => :demo_account_required
    }.freeze
    CHAMPS_SI_VIDES = {
      'contactFirstName' => :contact_first_name,
      'contactLastName' => :contact_last_name,
      'contactPhone' => :contact_phone,
      'contactEmail' => :contact_email,
      'notes' => :notes
    }.freeze
    CHAMPS_COPIE = CHAMPS_DEMO.merge(CHAMPS_SI_VIDES).freeze

    def self.normaliser(texte)
      texte.to_s.gsub(/\r\n?/, "\n").strip
    end

    def self.vide?(valeur)
      valeur.nil? || valeur.to_s.strip.empty?
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

    # Ce qui manque au compte de démonstration d'une fiche, nommé sans jamais citer une valeur.
    def self.manques_compte_demo(detail)
      return ['fiche absente'] if detail.nil?
      [
        ('« Connexion requise » décoché (demoAccountRequired faux)' unless detail.demo_account_required == true),
        ('nom du compte vide' if vide?(detail.demo_account_name)),
        ('mot de passe vide' if vide?(detail.demo_account_password))
      ].compact
    end

    def self.compte_demo_complet?(detail)
      manques_compte_demo(detail).empty?
    end

    # Verrou : sans compte de démonstration complet, Apple ne peut pas se connecter et refuse la version.
    def self.exiger_compte_demo!(detail, marketing)
      manques = manques_compte_demo(detail)
      return true if manques.empty?
      raise Failure, "Compte de démonstration incomplet pour la version #{marketing} dans App Store Connect (#{manques.join(', ')}) : " \
        "rien n'est soumis. Le saisir par l'API avant de relancer (voir #{DOC})"
    end

    # Fonction pure. La version distribuée (READY_FOR_DISTRIBUTION) unique, plus ancienne que la cible ; nil s'il n'y
    # en a pas.
    def self.choisir_source(versions, marketing)
      distribuees = Array(versions).select { |v| v.platform == 'IOS' && v.app_version_state == 'READY_FOR_DISTRIBUTION' }
      return nil if distribuees.empty?
      raise Failure, "#{distribuees.length} versions iOS distribuées : source de la fiche de vérification ambiguë, rien n'est soumis (voir #{DOC})" if distribuees.length > 1
      source = distribuees.first
      unless source.version_string.to_s.match?(/\A\d+(?:\.\d+){0,2}\z/) && Gem::Version.new(source.version_string) < Gem::Version.new(marketing)
        raise Failure, "La version distribuée #{source.version_string.inspect} n'est pas antérieure à #{marketing} : rien n'est copié ni soumis (voir #{DOC})"
      end
      raise Failure, "Version distribuée #{source.version_string} sans identifiant Apple : rien n'est soumis (voir #{DOC})" if source.id.to_s.empty?
      source
    end

    # Fonction pure. Attributs à écrire dans la fiche cible, nil si la cible a déjà un compte de démonstration
    # complet (rien n'est jamais écrasé). La source doit en avoir un, sinon le verrou refuse. Les valeurs vont de la
    # réponse d'Apple à la requête d'Apple : elles ne sont ni transformées, ni affichées.
    def self.attributs_de_copie(source:, cible:, marketing:, source_version:)
      return nil if compte_demo_complet?(cible)
      manques_source = manques_compte_demo(source)
      unless manques_source.empty?
        raise Failure, "Compte de démonstration incomplet pour la version #{marketing} (#{manques_compte_demo(cible).join(', ')}) " \
          "et dans la version distribuée #{source_version} (#{manques_source.join(', ')}) : rien n'est copié ni soumis. " \
          "Le saisir par l'API avant de relancer (voir #{DOC})"
      end
      attributs = CHAMPS_DEMO.to_h { |api, champ| [api, source.public_send(champ)] }
      CHAMPS_SI_VIDES.each do |api, champ|
        valeur = source.public_send(champ)
        next if vide?(valeur) || !(cible.nil? || vide?(cible.public_send(champ)))
        attributs[api] = valeur
      end
      attributs
    end

    # Fonction pure. Fiche telle qu'elle sera après la copie (pré-vol, et contrôle de la relecture).
    def self.fusionner(cible, attributs)
      champs = CHAMPS_COPIE.values.to_h { |champ| [champ, cible&.public_send(champ)] }
      attributs.each { |api, valeur| champs[CHAMPS_COPIE.fetch(api)] = valeur }
      Struct.new(:id, *champs.keys, keyword_init: true).new(id: cible&.id, **champs)
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

    # Pré-vol en lecture seule, avant les gardes de la revue en cours (donc avant toute annulation) : rien n'est écrit,
    # pas même la copie de la fiche. Si la version que deliver éditera existe, ce doit être la version configurée ; sa
    # fiche, telle qu'elle sera après une copie éventuelle, doit avoir un compte de démonstration complet et des notes
    # composables. Si elle n'existe pas encore, la fiche de la version distribuée sert de prévision.
    def verifier!
      @version_vue = @gateway.edit_version
      @verifie = true
      exiger_version!(@version_vue) if @version_vue
      cible = @version_vue && @gateway.review_detail(@version_vue.id)
      attributs, source = planifier_copie(cible, prevision: @version_vue.nil?)
      if @version_vue.nil? && source.nil?
        @journal.call("Aucune version iOS modifiable ni distribuée : la version #{@marketing} sera créée après les gardes, puis contrôlée.")
        return :a_creer
      end
      prevue = attributs ? ReviewNotes.fusionner(cible, attributs) : cible
      # Filet : la fiche prévue reprend un compte de démonstration déjà contrôlé ; ce verrou ne cède que si la copie
      # prévue est fausse.
      ReviewNotes.exiger_compte_demo!(prevue, @marketing)
      ReviewNotes.composer(bloc: @bloc, existantes: prevue.notes)
      if @version_vue.nil?
        @journal.call("Pré-vol des notes pour la revue : la version #{@marketing} sera créée après les gardes ; la fiche de la version distribuée #{source.version_string} a un compte de démonstration.")
        return :a_creer
      end
      if attributs
        @journal.call("Pré-vol des notes pour la revue : la version #{@marketing} n'a pas de compte de démonstration ; il sera copié depuis la version distribuée #{source.version_string} à l'écriture.")
      else
        @journal.call("Pré-vol des notes pour la revue : version #{@marketing} trouvée, compte de démonstration renseigné.")
      end
      :pret
    end

    # Après les gardes, avant la soumission : la version est retrouvée (ou créée si absente), la fiche complétée
    # depuis la version distribuée si elle n'a pas de compte de démonstration, le verrou rejoué, puis le champ `notes`
    # écrit et relu.
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
      detail = copier_si_besoin(version, @gateway.review_detail(version.id))
      ReviewNotes.exiger_compte_demo!(detail, @marketing)
      composition = ReviewNotes.composer(bloc: @bloc, existantes: detail.notes)
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

    # [attributs à copier ou nil, version source ou nil]. Lecture seule. Une cible déjà complète ne lit pas la source.
    # `prevision` : la version n'existe pas encore ; sans version distribuée, sa fiche (créée par Apple) n'est
    # contrôlée qu'à l'écriture.
    def planifier_copie(cible, prevision: false)
      return [nil, nil] if ReviewNotes.compte_demo_complet?(cible)
      source_version = ReviewNotes.choisir_source(@gateway.distributed_versions, @marketing)
      if source_version.nil?
        return [nil, nil] if prevision
        raise Failure, "Compte de démonstration incomplet pour la version #{@marketing} (#{ReviewNotes.manques_compte_demo(cible).join(', ')}) " \
          "et aucune version distribuée d'où le copier : rien n'est soumis. Le saisir par l'API avant de relancer (voir #{DOC})"
      end
      source = @gateway.review_detail(source_version.id)
      [ReviewNotes.attributs_de_copie(source: source, cible: cible, marketing: @marketing, source_version: source_version.version_string), source_version]
    end

    # Seule écriture hors du champ notes, et seulement si la cible n'a pas de compte de démonstration complet.
    def copier_si_besoin(version, cible)
      attributs, source_version = planifier_copie(cible)
      return cible if attributs.nil?
      if cible.nil?
        @gateway.create_review_detail(version.id, attributs)
      else
        raise Failure, "Fiche de vérification sans identifiant Apple : rien n'est soumis (voir #{DOC})" if cible.id.to_s.empty?
        @gateway.update_review_detail(cible.id, attributs)
      end
      relu = @gateway.review_detail(version.id)
      attendu = ReviewNotes.fusionner(cible, attributs)
      ecarts = CHAMPS_COPIE.select do |api, champ|
        attributs.key?(api) && ReviewNotes.normaliser(relu&.public_send(champ)) != ReviewNotes.normaliser(attendu.public_send(champ))
      end.keys
      unless relu && ecarts.empty?
        raise Failure, "Fiche de vérification relue différente de la copie (#{relu ? ecarts.join(', ') : 'fiche absente'}) : rien n'est soumis (voir #{DOC})"
      end
      @journal.call("Fiche de vérification de la version #{@marketing} #{cible.nil? ? 'créée' : 'complétée'} depuis la version distribuée " \
        "#{source_version.version_string} (champs copiés : #{attributs.keys.join(', ')} ; aucune valeur affichée).")
      relu
    end
  end
end
