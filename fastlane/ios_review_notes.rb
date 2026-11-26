# Notes pour la revue Apple de l'app Swift (lanes `ios submit_native` et `ios preflight_review_native`,
# docs/mobile-swift/APP_STORE.md, section « Notes pour la revue et compte de démonstration »).
#
# Personne ne se connecte au site App Store Connect : tout passe par l'API, avec la clé ASC du workflow. Dans
# l'appStoreReviewDetail de la version modifiable, la lane écrit :
# - le champ `notes` (bloc versionné, choisi d'après le rôle vérifié du compte de démonstration, en tête, puis les
#   notes existantes) ;
# - SEULEMENT si la version n'a pas d'identifiants de démonstration : une copie, d'API à API, de la fiche de la
#   version distribuée (identifiants, puis contacts et notes là où la cible est vide). Des identifiants présents ne
#   sont jamais écrasés ;
# - `demoAccountRequired = true`, seulement s'il est inconnu (null) alors que les identifiants sont présents et que
#   la connexion du compte a réussi au pré-vol.
# Elle ne passe pas par `upload_to_app_store(app_review_information: …)` : deliver y remet `demoAccountRequired` à
# faux dès que le nom ou le mot de passe manque (fastlane 2.240.1, deliver/lib/deliver/upload_metadata.rb).
#
# Journal GitHub : aucune valeur de la fiche (identifiants, contacts, texte des notes, qui porte des identifiants),
# pas même masquée ; seulement des noms de champs, des longueurs, des états et « compte de démo : … ». Limite connue
# (APP_STORE.md) : Spaceship écrit chaque requête et chaque réponse de l'API Apple, corps compris, dans
# `$TMPDIR/spaceship*.log` (sur la sortie standard avec VERBOSE) ; jamais VERBOSE ni --verbose, jamais d'artefact
# du dossier temporaire, et le workflow efface ces journaux.
require 'digest'
require 'rubygems/version'
require_relative 'ios_review_submission'
require_relative 'ios_review_demo_account'

module IosReviewSubmission
  # Ordre de la lane submit_native, son seul appelant : pré-vol en lecture seule (compte de démonstration connecté
  # puis déconnecté), gardes de la revue en cours (attente du build, annulation éventuelle d'une revue en attente),
  # écriture de la fiche, puis soumission. Un verrou qui échoue lève avant `soumettre` : rien n'est soumis.
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
      raise Failure, "Fiche « Informations pour la vérification de l'app » illisible (#{error.class}) : compte de démonstration non vérifiable, soumission arrêtée (voir #{DOC_NOTES})"
    end

    def create_review_detail(version_id, attributes)
      @client.post_app_store_review_detail(app_store_version_id: version_id, attributes: attributes)
    rescue StandardError => error
      raise Failure, "Création de la fiche de vérification refusée par Apple (#{error.class}) : soumission arrêtée (voir #{DOC_NOTES})"
    end

    def update_review_detail(detail_id, attributes)
      @client.patch_app_store_review_detail(app_store_review_detail_id: detail_id, attributes: attributes)
    rescue StandardError => error
      raise Failure, "Écriture de la fiche de vérification refusée par Apple (#{error.class}) : soumission arrêtée (voir #{DOC_NOTES})"
    end

    def update_notes(detail_id, notes)
      @client.patch_app_store_review_detail(app_store_review_detail_id: detail_id, attributes: { notes: notes })
    rescue StandardError => error
      raise Failure, "Écriture des notes pour la revue refusée par Apple (#{error.class}) : soumission arrêtée (voir #{DOC_NOTES})"
    end
  end

  class ReviewNotes
    DOC = DOC_NOTES
    # Un bloc par rôle vérifié du compte des champs « Sign-in required » (CompteDemo::ROLES).
    FICHIERS = {
      soignant: 'config/ios-review-notes-2.0-soignant.txt',
      etablissement: 'config/ios-review-notes-2.0-etablissement.txt'
    }.freeze
    SEPARATEUR = '--- Notes from version 1.0.7 (previous hybrid app) ---'
    # Limite Apple du champ « Notes » : 4 000 caractères. Marge : 3 900 unités UTF-16 (un émoji en compte deux),
    # fins de ligne ramenées à `\n`.
    LIMITE = 3900
    EMAIL = /[^\s@<>"'()]+@[^\s@<>"'()]+\.[A-Za-z]{2,}/
    # Copie depuis la version distribuée : attribut Apple → attribut du modèle Spaceship. Les identifiants sont copiés
    # d'un bloc ; contacts et notes seulement là où la cible est vide. Aucun autre attribut n'est écrit.
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

    def self.longueur(texte)
      texte.to_s.encode('UTF-16LE').bytesize / 2
    end

    # Le bloc vient d'un dépôt public : jamais d'adresse (donc jamais d'identifiant), jamais le séparateur, et
    # assez court pour laisser de la place aux notes précédentes.
    def self.valider_bloc!(bloc, fichier = 'le bloc')
      texte = normaliser(bloc)
      raise Failure, "#{fichier} est vide (voir #{DOC})" if texte.empty?
      raise Failure, "#{fichier} contient une adresse e-mail : aucun identifiant dans le dépôt public (voir #{DOC})" if texte.match?(EMAIL)
      if texte.lines.any? { |ligne| ligne.strip == SEPARATEUR }
        raise Failure, "#{fichier} contient la ligne de séparation « #{SEPARATEUR} » (voir #{DOC})"
      end
      if longueur(texte) + longueur(SEPARATEUR) + 2 > LIMITE
        raise Failure, "#{fichier} fait #{longueur(texte)} unités UTF-16 : avec le séparateur, il dépasse seul la marge de #{LIMITE} (voir #{DOC})"
      end
      texte
    end

    def self.valider_blocs!(blocs)
      unless blocs.is_a?(Hash) && blocs.keys.sort == FICHIERS.keys.sort
        raise Failure, "Un bloc par rôle attendu : #{FICHIERS.values.join(', ')} (voir #{DOC})"
      end
      FICHIERS.to_h { |role, fichier| [role, valider_bloc!(blocs.fetch(role), fichier)] }
    end

    def self.identifiants_presents?(detail)
      !detail.nil? && !vide?(detail.demo_account_name) && !vide?(detail.demo_account_password)
    end

    # Ce qui manque au compte de démonstration d'une fiche, nommé sans jamais citer une valeur. `null_admis` : au
    # pré-vol, un `demoAccountRequired` inconnu (null) sera écrit à true si la connexion réussit.
    def self.manques_compte_demo(detail, null_admis: false)
      return ['fiche absente'] if detail.nil?
      requis = detail.demo_account_required
      [
        ('« Connexion requise » décoché (demoAccountRequired faux)' if requis == false),
        ('« Connexion requise » inconnu (demoAccountRequired null)' if requis.nil? && !null_admis),
        ('« Connexion requise » illisible (demoAccountRequired)' unless [true, false, nil].include?(requis)),
        ('nom du compte vide' if vide?(detail.demo_account_name)),
        ('mot de passe vide' if vide?(detail.demo_account_password))
      ].compact
    end

    def self.compte_demo_complet?(detail)
      manques_compte_demo(detail).empty?
    end

    # Verrou : sans compte de démonstration complet, Apple ne peut pas se connecter et refuse la version.
    def self.exiger_compte_demo!(detail, marketing, null_admis: false)
      manques = manques_compte_demo(detail, null_admis: null_admis)
      return true if manques.empty?
      raise Failure, "Compte de démonstration incomplet pour la version #{marketing} dans App Store Connect (#{manques.join(', ')}) : " \
        "rien n'est soumis. Le saisir par l'API avant de relancer (voir #{DOC})"
    end

    # Empreinte en mémoire des identifiants connectés au pré-vol, jamais affichée : la fiche soumise doit porter les
    # mêmes.
    def self.empreinte(detail)
      Digest::SHA256.hexdigest("#{detail.demo_account_name.to_s.strip}\u0000#{detail.demo_account_password}")
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

    # Fonction pure. Attributs à écrire dans la fiche cible, nil si la cible a déjà des identifiants (jamais écrasés).
    # La source doit en avoir, sans « Connexion requise » décoché ; `demoAccountRequired` est écrit à true, la
    # connexion de ces identifiants ayant réussi au pré-vol. Les valeurs vont de la réponse d'Apple à la requête
    # d'Apple : elles ne sont ni transformées, ni affichées.
    def self.attributs_de_copie(source:, cible:, marketing:, source_version:)
      return nil if identifiants_presents?(cible)
      manques_source = manques_compte_demo(source, null_admis: true)
      unless manques_source.empty?
        raise Failure, "Compte de démonstration incomplet pour la version #{marketing} (#{manques_compte_demo(cible).join(', ')}) " \
          "et dans la version distribuée #{source_version} (#{manques_source.join(', ')}) : rien n'est copié ni soumis. " \
          "Le saisir par l'API avant de relancer (voir #{DOC})"
      end
      attributs = {
        'demoAccountName' => source.demo_account_name,
        'demoAccountPassword' => source.demo_account_password,
        'demoAccountRequired' => true
      }
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
    # notes existantes). Le bloc n'est jamais doublé ; au-delà de LIMITE unités UTF-16, échec.
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
        raise Failure, "Le bloc apparaîtrait #{notes.scan(bloc).length} fois dans les notes pour la revue : rien n'est soumis (voir #{DOC})"
      end
      if longueur(notes) > LIMITE
        raise Failure, "Notes pour la revue trop longues : #{longueur(notes)} unités UTF-16 pour #{LIMITE} au plus " \
          "(bloc #{longueur(bloc)}, notes précédentes #{longueur(anciennes)}) ; raccourcir le bloc, rien n'est soumis (voir #{DOC})"
      end
      { statut: statut, notes: notes, anciennes_avec_email: anciennes.match?(EMAIL) }
    end

    def initialize(gateway:, marketing_version:, blocs:, compte_demo:, journal: ->(_message) {})
      @gateway, @marketing, @compte_demo, @journal = gateway, marketing_version.to_s, compte_demo, journal
      @blocs = ReviewNotes.valider_blocs!(blocs)
      raise Failure, 'Invalid iOS release configuration' unless @marketing.match?(/\A\d+(?:\.\d+){0,2}\z/)
    end

    # Pré-vol, sans écriture chez Apple : avant les gardes de la revue en cours (donc avant toute annulation), et seul
    # appel de la lane `preflight_review_native` (mode `verifier`). La fiche que deliver soumettra, telle qu'elle sera
    # après une copie éventuelle, doit avoir des identifiants ; ils se connectent à la production (session aussitôt
    # révoquée) sur un rôle servi par l'app, qui choisit le bloc ; les notes doivent être composables.
    def verifier!
      @verifie, @role, @empreinte = false, nil, nil
      @version_vue = @gateway.edit_version
      exiger_version!(@version_vue) if @version_vue
      distribuees = @version_vue ? nil : @gateway.distributed_versions
      if distribuees && deja_distribuee?(distribuees)
        # Relance après la mise en vente (publication progressive comprise) : la garde de la revue conclut.
        @journal.call("Version #{@marketing} déjà distribuée : aucune fiche à vérifier, la garde de la revue conclut.")
        @verifie, @etat = true, :deja_distribuee
        return :deja_distribuee
      end
      cible = @version_vue && @gateway.review_detail(@version_vue.id)
      attributs, source = planifier_copie(cible, distribuees)
      prevue = attributs ? ReviewNotes.fusionner(cible, attributs) : cible
      ReviewNotes.exiger_compte_demo!(prevue, @marketing, null_admis: true)
      @role = @compte_demo.verifier!(nom: prevue.demo_account_name, mot_de_passe: prevue.demo_account_password)
      raise Failure, "compte de démo : rôle non pris en charge (voir #{DOC})" unless @blocs.key?(@role)
      @journal.call("compte de démo : connexion OK, rôle #{CompteDemo::LIBELLES.fetch(@role)}")
      ReviewNotes.composer(bloc: @blocs.fetch(@role), existantes: prevue.notes)
      @empreinte = ReviewNotes.empreinte(prevue)
      @journal.call(plan(prevue, attributs, source))
      @verifie, @etat = true, (@version_vue ? :pret : :a_creer)
      @etat
    end

    # Après les gardes, avant la soumission : la version est retrouvée (ou créée si absente), la fiche complétée
    # depuis la version distribuée si elle n'a pas d'identifiants, `demoAccountRequired` écrit à true s'il est
    # inconnu, le verrou rejoué, puis le champ `notes` écrit et relu.
    def appliquer!
      raise Failure, 'Notes pour la revue appliquées sans pré-vol' unless @verifie
      raise Failure, "Version #{@marketing} déjà distribuée : rien à écrire (voir #{DOC})" if @etat == :deja_distribuee
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
      detail = exiger_meme_compte!(copier_si_besoin(version, @gateway.review_detail(version.id)))
      detail = exiger_meme_compte!(requis_si_inconnu(version, detail))
      ReviewNotes.exiger_compte_demo!(detail, @marketing)
      composition = ReviewNotes.composer(bloc: @blocs.fetch(@role), existantes: detail.notes)
      unless composition[:anciennes_avec_email]
        @journal.call("Avertissement : les notes de la version précédente ne contiennent aucune adresse e-mail ; le bloc y renvoie pourtant pour les identifiants de l'autre compte (voir #{DOC}).")
      end
      if composition[:statut] == :inchange
        @journal.call('Notes pour la revue déjà à jour (bloc 2.0 en tête) : aucune écriture.')
        return :inchange
      end
      raise Failure, "Fiche de vérification sans identifiant Apple : rien n'est soumis (voir #{DOC})" if detail.id.to_s.empty?
      @gateway.update_notes(detail.id, composition[:notes])
      relu = exiger_meme_compte!(@gateway.review_detail(version.id))
      ReviewNotes.exiger_compte_demo!(relu, @marketing)
      unless ReviewNotes.normaliser(relu.notes) == ReviewNotes.normaliser(composition[:notes])
        raise Failure, "Notes pour la revue relues différentes de celles écrites : rien n'est soumis (voir #{DOC})"
      end
      @journal.call("Notes pour la revue #{composition[:statut] == :remplace ? 'remplacées' : 'complétées'} : bloc 2.0 (#{CompteDemo::LIBELLES.fetch(@role)}) en tête, " \
        "#{ReviewNotes.longueur(composition[:notes])} unités UTF-16 sur #{LIMITE}.")
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

    # La fiche écrite et soumise porte les identifiants connectés au pré-vol, et eux seuls.
    def exiger_meme_compte!(detail)
      unless ReviewNotes.identifiants_presents?(detail) && ReviewNotes.empreinte(detail) == @empreinte
        raise Failure, "Le compte de démonstration de la fiche n'est pas celui connecté au pré-vol : rien n'est soumis, relancer le workflow entier (voir #{DOC})"
      end
      detail
    end

    def deja_distribuee?(versions)
      Array(versions).any? do |v|
        v.platform == 'IOS' && v.app_version_state == 'READY_FOR_DISTRIBUTION' &&
          v.version_string.to_s.match?(/\A\d+(?:\.\d+){0,2}\z/) && Gem::Version.new(v.version_string) == Gem::Version.new(@marketing)
      end
    end

    # [attributs à copier ou nil, version source ou nil]. Lecture seule. Une cible qui a des identifiants ne lit pas
    # la source.
    def planifier_copie(cible, distribuees = nil)
      return [nil, nil] if ReviewNotes.identifiants_presents?(cible)
      source_version = ReviewNotes.choisir_source(distribuees || @gateway.distributed_versions, @marketing)
      if source_version.nil?
        raise Failure, "Compte de démonstration absent de la version #{@marketing} (#{ReviewNotes.manques_compte_demo(cible).join(', ')}) " \
          "et aucune version distribuée d'où le copier : rien n'est soumis. Le saisir par l'API avant de relancer (voir #{DOC})"
      end
      source = @gateway.review_detail(source_version.id)
      [ReviewNotes.attributs_de_copie(source: source, cible: cible, marketing: @marketing, source_version: source_version.version_string), source_version]
    end

    def plan(prevue, attributs, source)
      if @version_vue.nil?
        "Pré-vol des notes pour la revue : la version #{@marketing} sera créée après les gardes ; identifiants de la version distribuée #{source.version_string} vérifiés."
      elsif attributs
        "Pré-vol des notes pour la revue : la version #{@marketing} n'a pas d'identifiants de démonstration ; ils seront copiés depuis la version distribuée #{source.version_string} à l'écriture."
      elsif prevue.demo_account_required.nil?
        "Pré-vol des notes pour la revue : version #{@marketing} trouvée ; « Connexion requise » inconnu (null), il sera écrit à true à l'écriture."
      else
        "Pré-vol des notes pour la revue : version #{@marketing} trouvée, compte de démonstration renseigné."
      end
    end

    # Écriture hors du champ notes, seulement si la cible n'a pas d'identifiants de démonstration.
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

    # Seule autre écriture hors notes et hors copie : « Connexion requise » inconnu (null) alors que les identifiants,
    # connectés au pré-vol, sont présents.
    def requis_si_inconnu(version, detail)
      return detail unless detail.demo_account_required.nil?
      @gateway.update_review_detail(detail.id, { 'demoAccountRequired' => true })
      relu = @gateway.review_detail(version.id)
      @journal.call('« Connexion requise » inconnu (null) : écrit à true, la connexion du compte de démonstration ayant réussi au pré-vol.')
      relu
    end
  end
end
