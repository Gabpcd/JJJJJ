#!/usr/bin/env ruby
# Fixtures only: no Fastlane load, credentials, or network. Every account value below is fictitious.
require 'json'
require 'ostruct'
require 'socket'
require_relative 'ios_review_notes'
require_relative 'ios_review_submission.test'

module IosReviewNotesTest
  ROOT = File.expand_path('..', __dir__)
  N = IosReviewSubmission::ReviewNotes
  C = IosReviewSubmission::CompteDemo
  SEP = N::SEPARATEUR
  BLOC = "Jolene 2.0 fixture block, professional variant.\n\nSecond paragraph of the fixture block."
  BLOC_ETAB = "Jolene 2.0 fixture block, facility variant.\n\nSecond paragraph of the fixture block."
  BLOCS = { soignant: BLOC, etablissement: BLOC_ETAB }.freeze
  DEMO_NOM = 'revue-soignant@example.test'
  DEMO_MDP = 'mdp-fictif'
  SRC_NOM = 'revue-source@example.test'
  SRC_MDP = 'mdp-source-fictif'
  SRC_CONTACT = { contact_first_name: 'Prenom-source', contact_last_name: 'Nom-source',
                  contact_phone: '+33100000001', contact_email: 'contact-source@example.test' }.freeze
  ETAB = 'etab-revue@example.test / mdp-etab-fictif'
  ANCIENNES = "Version 1.0.7. Compte établissement : #{ETAB}\nCompte administrateur : voir ci-dessus."
  JETON = 'jeton-acces-fictif-0123456789'
  USER_ID = '11111111-2222-3333-4444-555555555555'
  ETAB_ID = '66666666-7777-8888-9999-000000000000'
  URL = 'https://abcdefghijklmnopqrst.supabase.co'
  CLE = 'sb_publishable_fixture-cle-publique-0123'
  SECRETS = [DEMO_NOM, DEMO_MDP, SRC_NOM, SRC_MDP, *SRC_CONTACT.values, 'contact@example.test', '+33100000000',
             'etab-revue@example.test', 'mdp-etab-fictif', 'Compte administrateur', JETON, USER_ID, ETAB_ID].freeze

  def self.assert(value, message = 'assertion failed')
    raise message unless value
  end

  # Returns the failure so callers can also check that it never echoes an account value.
  def self.rejects(pattern, &block)
    error = begin
      block.call
      nil
    rescue IosReviewSubmission::Failure => failure
      failure
    end
    assert(error && error.message.match?(pattern), "Expected #{pattern}, got #{error&.message.inspect}")
    SECRETS.each { |secret| assert(!error.message.include?(secret), "failure message echoes an account value: #{pattern}") }
    error
  end

  def self.detail(id: 'd200', notes: ANCIENNES, required: true, nom: DEMO_NOM, mdp: DEMO_MDP, **contacts)
    contacts = { contact_first_name: 'Prenom', contact_last_name: 'Nom', contact_phone: '+33100000000',
                 contact_email: 'contact@example.test' }.merge(contacts)
    OpenStruct.new(id: id, notes: notes, demo_account_required: required, demo_account_name: nom,
      demo_account_password: mdp, **contacts)
  end

  def self.source_detail(**options)
    detail(id: 'd107', nom: SRC_NOM, mdp: SRC_MDP, **SRC_CONTACT, **options)
  end

  def self.version(chaine = '2.0.0', state = 'PREPARE_FOR_SUBMISSION', id = 'v200')
    OpenStruct.new(id: id, version_string: chaine, platform: 'IOS', app_version_state: state)
  end

  # App Store Connect simulé, une fiche par version (nil : Apple répond `data: null`).
  class FakeNotesGateway
    attr_accessor :edit, :details, :distribuees, :on_patch, :on_edit, :on_copy, :detail_after_create, :illisibles
    attr_reader :events, :patches, :created, :copies, :edit_reads
    def initialize(edit: IosReviewNotesTest.version, detail: IosReviewNotesTest.detail, events: [],
        source: IosReviewNotesTest.version('1.0.7', 'READY_FOR_DISTRIBUTION', 'v107'), source_detail: IosReviewNotesTest.source_detail,
        autres: [])
      @edit, @events, @patches, @created, @copies, @edit_reads, @illisibles = edit, events, [], [], [], 0, []
      @details = {}
      @details[edit.id] = detail if edit
      # Versions iOS hors des états modifiables (versions_ios rend aussi la modifiable, comme Apple).
      @distribuees = (source ? [source] : []) + autres
      @details[source.id] = source_detail if source
    end
    def cible = @details[@edit&.id]
    def edit_version
      @events << :edit_version
      @edit_reads += 1
      @on_edit&.call(self)
      @edit&.dup
    end
    def create_version(marketing)
      @events << :create_version
      @created << marketing
      @edit = IosReviewNotesTest.version(marketing)
      @details['v200'] = @detail_after_create
    end
    def versions_ios
      @events << :read_versions
      (@distribuees + [@edit].compact).map(&:dup)
    end
    def review_detail(version_id)
      @events << :read_detail
      raise IosReviewSubmission::Failure, 'Fiche illisible (fixture)' if @illisibles.include?(version_id)
      @details[version_id]&.dup
    end
    def create_review_detail(version_id, attributes)
      @events << :create_detail
      @copies << [:create, version_id, attributes]
      fiche = OpenStruct.new(id: 'dNew')
      ecrire(fiche, attributes)
      @details[version_id] = fiche
      @on_copy&.call(self)
    end
    def update_review_detail(detail_id, attributes)
      @events << :update_detail
      @copies << [:update, detail_id, attributes]
      ecrire(trouver(detail_id), attributes)
      @on_copy&.call(self)
    end
    def update_notes(detail_id, notes)
      @events << :patch_notes
      @patches << [detail_id, notes]
      trouver(detail_id).notes = notes
      @on_patch&.call(self)
    end
    private
    def trouver(detail_id) = @details.values.compact.find { |d| d.id == detail_id }
    def ecrire(fiche, attributes)
      attributes.each { |api, valeur| fiche[IosReviewSubmission::ReviewNotes::CHAMPS_COPIE.fetch(api)] = valeur }
    end
  end

  # Vérification du compte simulée au niveau du parcours (la vraie, CompteDemo, est testée en HTTP plus bas).
  class StubCompte
    attr_reader :appels
    def initialize(events, role: :soignant, erreur: nil)
      @events, @role, @erreur, @appels = events, role, erreur, []
    end
    def verifier!(nom:, mot_de_passe:)
      @events << :sign_in
      @appels << [nom, mot_de_passe]
      raise IosReviewSubmission::Failure, @erreur if @erreur
      @role
    end
  end

  # Supabase Auth et PostgREST simulés au niveau HTTP : une réponse (ou une exception) par chemin.
  class FakeTransport
    attr_reader :calls
    def initialize(reponses)
      @reponses, @calls = reponses, []
    end
    def post(url, entetes, corps)
      @calls << { url: url, entetes: entetes, corps: corps }
      reponse = @reponses.fetch(@reponses.keys.find { |chemin| url.include?(chemin) })
      raise reponse if reponse.is_a?(Exception)
      reponse
    end
  end

  def self.http(token: [200, { access_token: JETON, user: { id: USER_ID, email: DEMO_NOM } }.to_json],
      role: [200, { user_id: USER_ID, role: 'SOIGNANT', etablissement_id: nil }.to_json], logout: [204, ''])
    FakeTransport.new('/auth/v1/token' => token, '/rest/v1/rpc/fn_get_my_role' => role, '/auth/v1/logout' => logout)
  end

  def self.notes(gateway, journal: [], marketing: '2.0.0', blocs: BLOCS, compte: nil)
    N.new(gateway: gateway, marketing_version: marketing, blocs: blocs, compte_demo: compte || StubCompte.new(gateway.events),
      journal: ->(message) { journal << message })
  end

  # Client Spaceship simulé : vérifie la forme exacte des requêtes de ReviewNotesGateway.
  class FakeClient
    attr_reader :posts, :patches, :detail_posts
    attr_accessor :detail_error, :detail_body
    def initialize
      @posts, @patches, @detail_posts = [], [], []
      @detail_body = { 'data' => { 'id' => 'd200' } }
    end
    def post_app_store_version(**args) = @posts << args
    def patch_app_store_review_detail(**args) = @patches << args
    def post_app_store_review_detail(**args) = @detail_posts << args
    def get_app_store_review_detail(**)
      raise detail_error if detail_error
      OpenStruct.new(body: detail_body, to_models: [IosReviewNotesTest.detail])
    end
  end

  class FakeApp
    attr_reader :id, :filters
    def initialize = (@id, @filters = 'app6774672845', [])
    def get_edit_app_store_version(platform:) = IosReviewNotesTest.version
    def get_app_store_versions(filter:)
      @filters << filter
      [IosReviewNotesTest.version('1.0.7', 'READY_FOR_DISTRIBUTION', 'v107')]
    end
  end

  class StubGuard
    def initialize(events, result: :ready, build_present: true)
      @events, @result, @build_present = events, result, build_present
    end
    def prepare!
      @events << :guard_prepare
      yield unless @build_present
      @result
    end
  end

  def self.enchainer(notes, guard, events)
    IosReviewSubmission.enchainer!(notes: notes, guard: guard,
      build_absent: -> { raise IosReviewSubmission::Failure, 'build absent (fixture)' },
      soumettre: -> { events << :submit })
  end

  ECRITURES = %i[create_version create_detail update_detail patch_notes].freeze

  def self.run
    journal_global = []
    cases = {
      'composition puts the block, a blank line and the English separator before untouched previous notes' => lambda {
        assert(SEP == '--- Notes from version 1.0.7 (previous hybrid app) ---')
        result = N.composer(bloc: BLOC, existantes: ANCIENNES)
        assert(result[:statut] == :ajoute && result[:notes] == "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}" && result[:anciennes] == ANCIENNES)
      },
      'composition is idempotent, including after Apple normalises line endings and trailing spaces' => lambda {
        premiere = N.composer(bloc: BLOC, existantes: ANCIENNES)[:notes]
        again = N.composer(bloc: BLOC, existantes: premiere)
        assert(again[:statut] == :inchange && again[:notes] == premiere)
        crlf = N.composer(bloc: "#{BLOC}\n", existantes: "  #{premiere.gsub("\n", "\r\n")}  \r\n")
        assert(crlf[:statut] == :inchange && crlf[:anciennes] == ANCIENNES)
      },
      'a block already at the head without separator is never doubled' => lambda {
        result = N.composer(bloc: BLOC, existantes: "#{BLOC}\n#{ANCIENNES}")
        assert(result[:statut] == :inchange && result[:notes].scan(BLOC).length == 1)
        assert(N.composer(bloc: BLOC, existantes: BLOC)[:statut] == :inchange)
      },
      'a previous block at the head is replaced, including the other role variant; previous notes kept once' => lambda {
        ancienne_version = "Jolene 2.0 draft block, older wording.\nWith a second line."
        result = N.composer(bloc: BLOC, existantes: "#{ancienne_version}\n\n#{SEP}\n#{ANCIENNES}")
        assert(result[:statut] == :remplace && result[:notes] == "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}")
        assert(!result[:notes].include?('older wording') && result[:notes].scan(SEP).length == 1)
        assert(N.composer(bloc: BLOC, existantes: result[:notes])[:statut] == :inchange)
        autre_role = N.composer(bloc: BLOC_ETAB, existantes: result[:notes])
        assert(autre_role[:statut] == :remplace && autre_role[:notes] == "#{BLOC_ETAB}\n\n#{SEP}\n#{ANCIENNES}")
        plus_long = N.composer(bloc: BLOC, existantes: "#{BLOC}\nExtra sentence.\n\n#{SEP}\n#{ANCIENNES}")
        assert(plus_long[:statut] == :remplace && !plus_long[:notes].include?('Extra sentence'))
      },
      'empty previous notes give the block and the separator, without an address' => lambda {
        [nil, '', "  \n"].each do |vide|
          result = N.composer(bloc: BLOC, existantes: vide)
          assert(result[:statut] == :ajoute && result[:notes] == "#{BLOC}\n\n#{SEP}" && result[:anciennes] == '')
          assert(N.composer(bloc: BLOC, existantes: result[:notes])[:statut] == :inchange)
        end
      },
      'margin: 3900 UTF-16 units, an emoji counts double, CRLF counts as one, notes never echoed' => lambda {
        assert(N::LIMITE == 3900 && N.longueur("a\u{1F600}") == 3)
        fixe = N.longueur("#{BLOC}\n\n#{SEP}\n")
        juste = 'a' * (N::LIMITE - fixe)
        assert(N.longueur(N.composer(bloc: BLOC, existantes: juste)[:notes]) == N::LIMITE)
        error = rejects(/trop longues : 3901 unités UTF-16 pour 3900/) { N.composer(bloc: BLOC, existantes: "#{juste[1..]}\u{1F600}") }
        assert(!error.message.include?('aaaa'), 'notes are never echoed')
        avec_crlf = "#{'a' * (N::LIMITE - fixe - 3)}x\r\ny"
        assert(N.longueur(N.composer(bloc: BLOC, existantes: avec_crlf)[:notes]) == N::LIMITE)
        rejects(/trop longues/) { N.composer(bloc: BLOC, existantes: "#{ANCIENNES}\n#{'x' * N::LIMITE}") }
      },
      'ambiguous separators and a block repeated in previous notes stop the composition' => lambda {
        rejects(/2 lignes de séparation/) { N.composer(bloc: BLOC, existantes: "x\n#{SEP}\ny\n#{SEP}\n#{ANCIENNES}") }
        rejects(/apparaîtrait 2 fois/) { N.composer(bloc: BLOC, existantes: "Old head\n#{SEP}\n#{BLOC}\n#{ANCIENNES}") }
      },
      'the versioned blocks are validated: one per role, not empty, no address, no separator, room left' => lambda {
        rejects(/est vide/) { N.valider_bloc!(" \n") }
        rejects(/adresse e-mail/) { N.valider_bloc!("Use #{DEMO_NOM} to sign in.") }
        rejects(/ligne de séparation/) { N.valider_bloc!("Head\n#{SEP}\nTail") }
        rejects(/dépasse seul la marge/) { N.valider_bloc!('z' * (N::LIMITE - SEP.length - 1)) }
        rejects(/Un bloc par rôle attendu/) { N.valider_blocs!({ soignant: BLOC }) }
        rejects(/Un bloc par rôle attendu/) { notes(FakeNotesGateway.new, blocs: { soignant: BLOC, admin: BLOC }) }
      },
      'the repository blocks pass their own validation, name the right account and the exact payment circuit' => lambda {
        blocs = N.valider_blocs!(N::FICHIERS.transform_values { |f| File.read(File.join(ROOT, f), encoding: 'UTF-8') })
        blocs.each_value do |bloc|
          assert(bloc.start_with?('Jolene 2.0 is a native (Swift) rewrite of the app and replaces version 1.0.7.'))
          assert(bloc.include?('Profil > "Suppression de compte" > "Supprimer mon compte"'))
          assert(bloc.include?('Compte > Aide & légal > "Supprimer mon compte"'))
          assert(bloc.include?('facilities pay by SEPA direct debit collected by Jolene, which pays the professional by bank transfer, outside the app.'))
          assert(!bloc.include?('settled between'))
          # Candidature (fn_postuler_mission, CandidatureSection) : seul chemin atteignable par le compte de revue, salarié,
          # candidature envoyée puis non acceptable ; seules la carte d'identité et le RIB bloquent (RPPS vérifié, donc ni
          # diplôme ni RPPS exigés) ; écran des statuts : Profil › « Mon espace » › « Mes documents ».
          assert(bloc.include?('Applying needs validated documents (identity, bank details…); some are still under review on this demo account ' \
            '(Profil > Mon espace > "Mes documents"): an application is sent, but the facility cannot accept it until they are validated.'))
          assert(!bloc.match?(/diploma|RPPS|freelance|missing/), 'only what really blocks this account')
          assert(bloc.include?('Explorer (three demo assignments in Paris)'))
          assert(N.longueur(bloc) < 2500, "block too long: #{N.longueur(bloc)}")
        end
        assert(blocs[:soignant].include?('Healthcare professional account: the credentials in the "Sign-in required" fields.'))
        assert(blocs[:soignant].include?('Facility account: credentials in the previous notes below.'))
        assert(blocs[:etablissement].include?('Facility account: the credentials in the "Sign-in required" fields.'))
        assert(blocs[:etablissement].include?('Healthcare professional account: credentials in the previous notes below.'))
      },
      'demo account lock: true required, null named as unknown, false as unchecked, never echoing a value' => lambda {
        assert(N.exiger_compte_demo!(detail, '2.0.0') == true)
        rejects(/décoché \(demoAccountRequired faux\)/) { N.exiger_compte_demo!(detail(required: false), '2.0.0') }
        rejects(/inconnu \(demoAccountRequired null\)/) { N.exiger_compte_demo!(detail(required: nil), '2.0.0') }
        assert(N.exiger_compte_demo!(detail(required: nil), '2.0.0', null_admis: true) == true)
        rejects(/décoché/) { N.exiger_compte_demo!(detail(required: false), '2.0.0', null_admis: true) }
        rejects(/illisible \(demoAccountRequired\)/) { N.exiger_compte_demo!(detail(required: 'true'), '2.0.0') }
        rejects(/nom du compte vide/) { N.exiger_compte_demo!(detail(nom: '  '), '2.0.0') }
        rejects(/mot de passe vide/) { N.exiger_compte_demo!(detail(mdp: nil), '2.0.0') }
        rejects(/fiche absente/) { N.exiger_compte_demo!(nil, '2.0.0') }
        error = rejects(/Compte de démonstration incomplet.*APP_STORE\.md/) { N.exiger_compte_demo!(detail(required: false, nom: '', mdp: ''), '2.0.0') }
        assert(error.message.include?('nom du compte vide, mot de passe vide'))
      },
      'copy attributes: whole fiche when the target has none, demoAccountRequired written true, untransformed values' => lambda {
        [true, nil].each do |requis|
          attributs = N.attributs_de_copie(source: source_detail(required: requis), cible: nil, marketing: '2.0.0', source_version: '1.0.7')
          attendu = { 'demoAccountName' => SRC_NOM, 'demoAccountPassword' => SRC_MDP, 'demoAccountRequired' => true,
                      'contactFirstName' => 'Prenom-source', 'contactLastName' => 'Nom-source', 'contactPhone' => '+33100000001',
                      'contactEmail' => 'contact-source@example.test', 'notes' => ANCIENNES }
          assert(attributs == attendu && attributs.keys.sort == N::CHAMPS_COPIE.keys.sort)
        end
        vide = N.attributs_de_copie(source: source_detail(contact_phone: '', notes: nil), cible: nil, marketing: '2.0.0', source_version: '1.0.7')
        assert(!vide.key?('contactPhone') && !vide.key?('notes'), 'an empty source value is never written')
      },
      'copy attributes: credentials present in the target are never overwritten, other fields only where empty' => lambda {
        cible = detail(nom: '', mdp: '', notes: '', contact_email: '', contact_phone: nil)
        attributs = N.attributs_de_copie(source: source_detail, cible: cible, marketing: '2.0.0', source_version: '1.0.7')
        assert(attributs.keys.sort == %w[contactEmail contactPhone demoAccountName demoAccountPassword demoAccountRequired notes].sort)
        [detail, detail(required: nil), detail(required: false)].each do |avec_identifiants|
          assert(N.attributs_de_copie(source: source_detail, cible: avec_identifiants, marketing: '2.0.0', source_version: '1.0.7').nil?)
        end
        fusion = N.fusionner(cible, attributs)
        assert(fusion.id == 'd200' && fusion.contact_first_name == 'Prenom' && fusion.contact_email == 'contact-source@example.test')
        assert(N.compte_demo_complet?(fusion) && fusion.notes == ANCIENNES)
      },
      'copy attributes: a source without credentials, or with « Connexion requise » unchecked, is refused' => lambda {
        [source_detail(mdp: ''), source_detail(required: false), nil].each do |source|
          error = rejects(/version 2\.0\.0 \(fiche absente\) et dans la version distribuée 1\.0\.7 \(.+\) : rien n'est copié ni soumis/) do
            N.attributs_de_copie(source: source, cible: nil, marketing: '2.0.0', source_version: '1.0.7')
          end
          assert(error.message.include?('APP_STORE.md'))
        end
      },
      'copy source: the single distributed iOS version, older than the target' => lambda {
        assert(N.choisir_source([], '2.0.0').nil?)
        live = version('1.0.7', 'READY_FOR_DISTRIBUTION', 'v107')
        autres = [version('1.0.6', 'REPLACED_WITH_NEW_VERSION', 'v106'), live.dup.tap { |v| v.platform = 'TV_OS'; v.id = 'tv' }]
        assert(N.choisir_source(autres + [live], '2.0.0').id == 'v107')
        assert(N.choisir_source(autres, '2.0.0').nil?)
        rejects(/2 versions iOS distribuées/) { N.choisir_source([live, live.dup.tap { |v| v.id = 'v2' }], '2.0.0') }
        rejects(/n'est pas antérieure à 2\.0\.0/) { N.choisir_source([version('2.0.0', 'READY_FOR_DISTRIBUTION', 'v')], '2.0.0') }
        rejects(/n'est pas antérieure/) { N.choisir_source([version('2.1', 'READY_FOR_DISTRIBUTION', 'v')], '2.0.0') }
      },
      'production config read from the native app xcconfig, nothing else accepted' => lambda {
        config = C.lire_config!(File.read(File.join(ROOT, C::CONFIG), encoding: 'UTF-8'))
        assert(config[:url].match?(%r{\Ahttps://[a-z0-9]{20}\.supabase\.co\z}) && config[:cle].start_with?('sb_publishable_'))
        base = "JOLENE_ENVIRONMENT = production\nJOLENE_SUPABASE_URL = https:/$()/abcdefghijklmnopqrst.supabase.co\nJOLENE_SUPABASE_PUBLISHABLE_KEY = #{CLE}\n"
        assert(C.lire_config!(base) == { url: URL, cle: CLE })
        rejects(/illisible/) { C.lire_config!(base.sub('production', 'staging')) }
        rejects(/illisible/) { C.lire_config!(base.sub('https:/$()/', 'http:/$()/')) }
        # Une clé qui n'est pas publishable (fixture assemblée ici, comme dans ios-native-testflight.node.mjs).
        rejects(/illisible/) { C.lire_config!(base.sub(CLE, "sb_#{'secret'}_#{'x' * 24}")) }
        rejects(/JOLENE_SUPABASE_URL absent ou répété/) { C.lire_config!(base + "JOLENE_SUPABASE_URL = #{URL}\n") }
        rejects(/JOLENE_SUPABASE_PUBLISHABLE_KEY absent/) { C.lire_config!(base.lines.first(2).join) }
      },
      'demo sign-in like the native app: password grant, apikey, role by fn_get_my_role, session revoked' => lambda {
        transport = http
        assert(C.new(url: URL, cle: CLE, transport: transport).verifier!(nom: "  #{DEMO_NOM} ", mot_de_passe: DEMO_MDP) == :soignant)
        token, role, logout = transport.calls
        assert(transport.calls.length == 3)
        assert(token[:url] == "#{URL}/auth/v1/token?grant_type=password" && JSON.parse(token[:corps]) == { 'email' => DEMO_NOM, 'password' => DEMO_MDP })
        assert(token[:entetes]['apikey'] == CLE && !token[:entetes].key?('Authorization') && !token[:corps].include?('captcha'))
        assert(role[:url] == "#{URL}/rest/v1/rpc/fn_get_my_role" && role[:corps] == '{}')
        assert(logout[:url] == "#{URL}/auth/v1/logout?scope=local", 'only this session is revoked')
        [role, logout].each { |appel| assert(appel[:entetes]['Authorization'] == "Bearer #{JETON}" && appel[:entetes]['apikey'] == CLE) }
        etab = http(role: [200, { user_id: USER_ID, role: 'ADMIN_ETABLISSEMENT', etablissement_id: ETAB_ID }.to_json])
        assert(C.new(url: URL, cle: CLE, transport: etab).verifier!(nom: DEMO_NOM, mot_de_passe: DEMO_MDP) == :etablissement)
      },
      'demo sign-in refusals: other roles, HTTP 400, captcha, network, unreadable answers, logout not confirmed' => lambda {
        verifier = ->(transport) { C.new(url: URL, cle: CLE, transport: transport).verifier!(nom: DEMO_NOM, mot_de_passe: DEMO_MDP) }
        %w[ADMIN_PLATEFORME ADMIN_GROUPE INCONNU].each do |autre|
          transport = http(role: [200, { user_id: USER_ID, role: autre }.to_json])
          rejects(/compte de démo : connexion OK, rôle #{autre} : l'app ne sert pas ce compte/) { verifier.call(transport) }
          assert(transport.calls.last[:url].end_with?('/auth/v1/logout?scope=local'), 'logged out even when refused')
        end
        rejects(/rôle inattendu/) { verifier.call(http(role: [200, { role: "INJECT #{DEMO_NOM}" }.to_json])) }
        transport = http(token: [400, { error_code: 'invalid_credentials', msg: "Invalid login for #{DEMO_NOM}" }.to_json])
        rejects(/\Acompte de démo : connexion refusée \(HTTP 400\) ; rien n'est écrit ni soumis/) { verifier.call(transport) }
        assert(transport.calls.length == 1, 'no token, no role read, nothing to revoke')
        rejects(/connexion refusée, captcha exigé \(HTTP 400\)/) { verifier.call(http(token: [400, { error_code: 'captcha_failed', msg: 'captcha protection: request disallowed' }.to_json])) }
        rejects(/captcha exigé \(HTTP 400\)/) { verifier.call(http(token: [400, { msg: 'captcha verification process failed' }.to_json])) }
        rejects(/connexion refusée \(HTTP 429\)/) { verifier.call(http(token: [429, 'Too many requests'])) }
        rejects(/connexion impossible \(réseau : SocketError\)/) { verifier.call(http(token: SocketError.new("getaddrinfo #{URL}"))) }
        rejects(/réponse illisible \(HTTP 200\)/) { verifier.call(http(token: [200, '{"user":{}}'])) }
        transport = http(role: [401, '{"message":"JWT expired"}'])
        rejects(/rôle illisible \(HTTP 401\)/) { verifier.call(transport) }
        assert(transport.calls.last[:url].end_with?('/auth/v1/logout?scope=local'))
        rejects(/rôle illisible \(HTTP 200\)/) { verifier.call(http(role: [200, '[]'])) }
        rejects(/déconnexion non confirmée \(HTTP 500\)/) { verifier.call(http(logout: [500, ''])) }
        rejects(/déconnexion non confirmée \(réseau : Errno::ECONNRESET\)/) { verifier.call(http(logout: Errno::ECONNRESET.new)) }
        rejects(/identifiants absents/) { C.new(url: URL, cle: CLE, transport: http).verifier!(nom: ' ', mot_de_passe: DEMO_MDP) }
      },
      'existing complete version: pre-flight writes nothing, signs in once, then only the notes are written' => lambda {
        journal = []
        gateway = FakeNotesGateway.new
        avant = gateway.cible.to_h
        compte = StubCompte.new(gateway.events)
        notes = notes(gateway, journal: journal, compte: compte)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty?)
        assert(gateway.events == %i[edit_version read_detail sign_in] && compte.appels == [[DEMO_NOM, DEMO_MDP]])
        assert(journal.include?('compte de démo : connexion OK, rôle soignant'))
        assert(notes.appliquer! == :ajoute)
        assert(gateway.patches == [['d200', "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}"]] && gateway.copies.empty?)
        assert(gateway.cible.to_h.reject { |k, _| k == :notes } == avant.reject { |k, _| k == :notes }, 'only notes change')
        assert(!gateway.events.include?(:read_versions))
        rerun = notes(gateway, journal: journal)
        assert(rerun.verifier! == :pret && rerun.appliquer! == :inchange && gateway.patches.length == 1)
        journal_global.concat(journal)
      },
      'the verified role picks the block: a facility account gets the facility variant' => lambda {
        journal = []
        gateway = FakeNotesGateway.new
        notes = notes(gateway, journal: journal, compte: StubCompte.new(gateway.events, role: :etablissement))
        notes.verifier!
        assert(notes.appliquer! == :ajoute && gateway.patches == [['d200', "#{BLOC_ETAB}\n\n#{SEP}\n#{ANCIENNES}"]])
        assert(journal.include?('compte de démo : connexion OK, rôle établissement'))
        rerun = notes(gateway, compte: StubCompte.new(gateway.events, role: :soignant))
        rerun.verifier!
        assert(rerun.appliquer! == :remplace && gateway.patches.last[1] == "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}", 'role change replaces the block')
        journal_global.concat(journal)
      },
      'a refused sign-in stops the pre-flight: nothing written, review guards never reached' => lambda {
        events = []
        gateway = FakeNotesGateway.new(events: events)
        compte = StubCompte.new(events, erreur: "compte de démo : connexion refusée (HTTP 400) ; rien n'est écrit ni soumis")
        rejects(/connexion refusée \(HTTP 400\)/) { enchainer(notes(gateway, compte: compte), StubGuard.new(events), events) }
        assert(events == %i[edit_version read_detail sign_in] && gateway.copies.empty? && gateway.patches.empty?)
      },
      'sign-in through the real HTTP check inside the pre-flight, with simulated Supabase answers' => lambda {
        [[http, :ajoute], [http(token: [400, '{}']), /HTTP 400/], [http(role: [200, { role: 'ADMIN_PLATEFORME' }.to_json]), /ADMIN_PLATEFORME/],
         [http(token: [400, { error_code: 'captcha_failed' }.to_json]), /captcha/], [http(token: Errno::ENETUNREACH.new), /réseau/]].each do |transport, attendu|
          events = []
          gateway = FakeNotesGateway.new(events: events)
          notes = notes(gateway, compte: C.new(url: URL, cle: CLE, transport: transport))
          if attendu.is_a?(Regexp)
            rejects(attendu) { enchainer(notes, StubGuard.new(events), events) }
            assert((events & ECRITURES).empty? && !events.include?(:guard_prepare) && !events.include?(:submit))
          else
            assert(enchainer(notes, StubGuard.new(events), events) == :submitted && gateway.patches.length == 1)
          end
        end
      },
      'target fiche without credentials: pre-flight reads the source and signs in with it; the copy happens at the write step' => lambda {
        journal = []
        cible = detail(nom: '', mdp: '', notes: 'Notes 2.0 déjà saisies, sans adresse.', contact_first_name: 'Prenom-cible')
        gateway = FakeNotesGateway.new(detail: cible)
        compte = StubCompte.new(gateway.events)
        notes = notes(gateway, journal: journal, compte: compte)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty? && gateway.events.include?(:read_versions))
        assert(compte.appels == [[SRC_NOM, SRC_MDP]], 'the source credentials are the ones signed in')
        assert(notes.appliquer! == :ajoute)
        assert(gateway.copies.length == 1 && gateway.copies.first[0..1] == [:update, 'd200'])
        assert(gateway.copies.first[2] == { 'demoAccountName' => SRC_NOM, 'demoAccountPassword' => SRC_MDP, 'demoAccountRequired' => true })
        assert(gateway.cible.contact_first_name == 'Prenom-cible' && gateway.cible.demo_account_name == SRC_NOM)
        assert(gateway.patches.last[1] == "#{BLOC}\n\n#{SEP}\nNotes 2.0 déjà saisies, sans adresse.", 'existing target notes are kept')
        assert(gateway.events.index(:update_detail) < gateway.events.index(:patch_notes))
        assert(journal.any? { |m| m.include?('complétée depuis la version distribuée 1.0.7 (champs copiés : demoAccountName, demoAccountPassword, demoAccountRequired') })
        rerun = notes(gateway, journal: journal)
        assert(rerun.verifier! == :pret && rerun.appliquer! == :inchange && gateway.copies.length == 1, 'the copy happens once')
        journal_global.concat(journal)
      },
      'version without any fiche: the whole fiche is created from the source, then the block goes before the copied notes' => lambda {
        journal = []
        gateway = FakeNotesGateway.new(detail: nil, source_detail: source_detail(required: nil))
        notes = notes(gateway, journal: journal)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty?)
        assert(notes.appliquer! == :ajoute)
        assert(gateway.copies.length == 1 && gateway.copies.first[0..1] == [:create, 'v200'])
        assert(gateway.copies.first[2].keys.sort == N::CHAMPS_COPIE.keys.sort && gateway.copies.first[2]['demoAccountRequired'] == true)
        assert(gateway.patches == [['dNew', "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}"]])
        assert(journal.any? { |m| m.include?('créée depuis la version distribuée 1.0.7') })
        journal_global.concat(journal)
      },
      'unknown (null) demoAccountRequired with credentials: written true once after the sign-in, the only other write' => lambda {
        journal = []
        gateway = FakeNotesGateway.new(detail: detail(required: nil))
        notes = notes(gateway, journal: journal)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty?)
        assert(journal.any? { |m| m.include?('inconnu (null), il sera écrit à true') })
        assert(notes.appliquer! == :ajoute)
        assert(gateway.copies == [[:update, 'd200', { 'demoAccountRequired' => true }]] && gateway.cible.demo_account_required == true)
        assert(gateway.events.index(:sign_in) < gateway.events.index(:update_detail))
        assert(gateway.events.index(:update_detail) < gateway.events.index(:patch_notes))
        rerun = notes(gateway)
        rerun.verifier!
        assert(rerun.appliquer! == :inchange && gateway.copies.length == 1)
        journal_global.concat(journal)
      },
      'credentials present with « Connexion requise » unchecked: refused before the sign-in, never overwritten' => lambda {
        gateway = FakeNotesGateway.new(detail: detail(required: false))
        rejects(/décoché \(demoAccountRequired faux\)/) { notes(gateway).verifier! }
        assert(gateway.events == %i[edit_version read_detail] && gateway.copies.empty?)
      },
      'the fiche written and submitted carries the credentials signed in at pre-flight, and only those' => lambda {
        gateway = FakeNotesGateway.new
        notes = notes(gateway)
        notes.verifier!
        gateway.cible.demo_account_password = 'autre-mdp-fictif'
        error = rejects(/n'est pas celui connecté au pré-vol/) { notes.appliquer! }
        assert(!error.message.include?('autre-mdp-fictif') && (gateway.events & ECRITURES).empty?)
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.cible.demo_account_name = 'autre@example.test' }
        notes = notes(gateway)
        notes.verifier!
        rejects(/n'est pas celui connecté au pré-vol/) { notes.appliquer! }
      },
      'absent version: created once after the guards, Apple copy kept when complete, source credentials signed in' => lambda {
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events)
        gateway.detail_after_create = detail(nom: SRC_NOM, mdp: SRC_MDP)
        notes = notes(gateway, journal: journal_global)
        assert(notes.verifier! == :a_creer && gateway.created.empty? && (events & ECRITURES).empty?)
        assert(events == %i[edit_version read_versions read_detail sign_in])
        assert(notes.appliquer! == :ajoute && gateway.created == ['2.0.0'] && gateway.copies.empty?)
        assert(events.drop(4) == %i[edit_version create_version edit_version read_detail patch_notes read_detail])
        gateway = FakeNotesGateway.new(edit: nil, detail: nil)
        gateway.detail_after_create = detail
        notes = notes(gateway)
        notes.verifier!
        rejects(/n'est pas celui connecté au pré-vol/) { notes.appliquer! }
        assert(gateway.patches.empty?, 'an Apple copy with other credentials is never submitted')
      },
      'absent version created by Apple without credentials: the copy from the source completes it' => lambda {
        [nil, detail(nom: '', mdp: '')].each do |copie_apple|
          gateway = FakeNotesGateway.new(edit: nil, detail: nil)
          gateway.detail_after_create = copie_apple
          notes = notes(gateway)
          notes.verifier!
          assert(notes.appliquer! == :ajoute && gateway.copies.length == 1 && N.compte_demo_complet?(gateway.cible))
          assert(gateway.copies.first[0] == (copie_apple ? :update : :create))
        end
      },
      'no credentials anywhere, or no distributed version: refused at pre-flight, nothing copied, nothing created' => lambda {
        events = []
        gateway = FakeNotesGateway.new(detail: detail(nom: ''), source_detail: source_detail(mdp: ''), events: events)
        rejects(/et dans la version distribuée 1\.0\.7 \(mot de passe vide\)/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert(events == %i[edit_version read_detail read_versions read_detail] && gateway.copies.empty?)
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, source_detail: nil, events: events)
        rejects(/version distribuée 1\.0\.7 \(fiche absente\)/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert((events & ECRITURES).empty? && !events.include?(:guard_prepare) && !events.include?(:sign_in))
        gateway = FakeNotesGateway.new(detail: detail(nom: ''), source: nil)
        rejects(/aucune version distribuée d'où le copier/) { notes(gateway).verifier! }
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, source: nil, events: events)
        rejects(/aucune version distribuée d'où le copier/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert(!events.include?(:create_version) && !events.include?(:guard_prepare))
      },
      'relaunch during review, after approval or after release: no 1.0.7 fiche, no sign-in, the review guard concludes' => lambda {
        # Liste écrite ici, pas relue dans la constante : retirer ou ajouter un état de SOUMISES doit rougir ce test.
        soumises = %w[IN_REVIEW PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE WAITING_FOR_EXPORT_COMPLIANCE PROCESSING_FOR_DISTRIBUTION
                      READY_FOR_DISTRIBUTION ACCEPTED REPLACED_WITH_NEW_VERSION]
        assert(N::SOUMISES.sort == soumises.sort, 'exactly the eight states after a submission; WAITING_FOR_REVIEW is editable')
        soumises.each do |etat|
          events = []
          journal = []
          vente = etat == 'READY_FOR_DISTRIBUTION' || etat == 'REPLACED_WITH_NEW_VERSION'
          gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events,
            source: version('1.0.7', vente ? 'REPLACED_WITH_NEW_VERSION' : 'READY_FOR_DISTRIBUTION', 'v107'),
            autres: [version('2.0.0', etat, 'v200')])
          notes = notes(gateway, journal: journal)
          assert(enchainer(notes, StubGuard.new(events, result: :already_submitted), events) == :already_submitted, etat)
          assert(events == %i[edit_version read_versions guard_prepare], "#{etat} : no fiche read, no sign-in, nothing written")
          assert(journal == ["Version 2.0.0 déjà soumise (#{etat}) : aucune fiche à vérifier, la garde de la revue conclut."])
          rejects(/déjà soumise : rien à écrire/) { notes.appliquer! }
          journal_global.concat(journal)
        end
      },
      'relaunch with the real review guard: green on the same build for five states, red without any write for three' => lambda {
        verts = %w[IN_REVIEW PENDING_APPLE_RELEASE WAITING_FOR_EXPORT_COMPLIANCE PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION]
        rouges = {
          'PENDING_DEVELOPER_RELEASE' => /PENDING_DEVELOPER_RELEASE; automatic release needs separate action/,
          'ACCEPTED' => /Apple version is ACCEPTED; automatic replacement stopped/,
          'REPLACED_WITH_NEW_VERSION' => /already distributed or superseded/
        }
        (verts + rouges.keys).each do |etat|
          review = IosReviewSubmissionTest::FakeGateway.new
          vente = %w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].include?(etat)
          review.version_rows.first.app_version_state = 'REPLACED_WITH_NEW_VERSION' if vente
          review.version_rows[-1] = IosReviewSubmissionTest.version(etat, IosReviewSubmissionTest.build)
          review.submission_rows = []
          events = review.events
          gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events,
            source: version('1.0.5', vente ? 'REPLACED_WITH_NEW_VERSION' : 'READY_FOR_DISTRIBUTION', 'v105'),
            autres: [version('1.0.6', etat, 'v106')])
          notes = notes(gateway, marketing: '1.0.6')
          guard = IosReviewSubmissionTest.guard(review)
          if verts.include?(etat)
            assert(enchainer(notes, guard, events) == :already_submitted, "#{etat} : déjà soumis, au vert")
          else
            erreur = begin
              enchainer(notes, guard, events)
              nil
            rescue IosReviewSubmission::Failure => e
              e
            end
            assert(erreur&.message&.match?(rouges.fetch(etat)), "#{etat} : #{erreur&.message.inspect}")
          end
          assert(events.include?(:build_read) && events.include?(:read_versions), "#{etat} : pré-vol puis vraie garde")
          assert(!events.include?(:read_detail) && !events.include?(:sign_in), "#{etat} : ni fiche lue ni connexion")
          assert((events & ECRITURES).empty? && !events.include?(:cancel) && !events.include?(:submit), "#{etat} : rien d'écrit")
        end
      },
      'a configured version neither editable nor submitted, or present twice, stops the pre-flight before any read of 1.0.7' => lambda {
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events, autres: [version('2.0.0', 'READY_FOR_REVIEW', 'v200')])
        rejects(/est READY_FOR_REVIEW dans App Store Connect, ni modifiable ni soumise/) { notes(gateway).verifier! }
        assert(events == %i[edit_version read_versions])
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, autres: [version('2.0.0', 'IN_REVIEW', 'a'), version('2.0', 'IN_REVIEW', 'b')])
        rejects(/2 versions iOS 2\.0\.0/) { notes(gateway).verifier! }
        assert(N.etat_hors_edition([version('1.0.7', 'READY_FOR_DISTRIBUTION', 'v107')], '2.0.0').nil?)
        assert(N.etat_hors_edition([version('2.0', 'IN_REVIEW', 'x')], '2.0.0') == 'IN_REVIEW')
      },
      'an unreadable target fiche is never taken for an absent one: nothing is copied' => lambda {
        gateway = FakeNotesGateway.new
        gateway.illisibles << 'v200'
        rejects(/illisible/) { notes(gateway).verifier! }
        assert(gateway.copies.empty? && !gateway.events.include?(:read_versions) && !gateway.events.include?(:sign_in))
      },
      'the copied fiche is re-read: a mismatch, a vanished fiche or a non-boolean flag stops before the notes' => lambda {
        gateway = FakeNotesGateway.new(detail: detail(nom: ''))
        gateway.on_copy = ->(g) { g.cible.demo_account_password = 'autre-valeur-fictive' }
        notes = notes(gateway)
        notes.verifier!
        error = rejects(/relue différente de la copie \(demoAccountPassword\)/) { notes.appliquer! }
        assert(!error.message.include?('autre-valeur-fictive') && gateway.patches.empty?)
        gateway = FakeNotesGateway.new(detail: nil)
        gateway.on_copy = ->(g) { g.details['v200'] = nil }
        notes = notes(gateway)
        notes.verifier!
        rejects(/relue différente de la copie \(fiche absente\)/) { notes.appliquer! }
        assert(gateway.patches.empty?)
        gateway = FakeNotesGateway.new(detail: detail(mdp: ''))
        gateway.on_copy = ->(g) { g.cible.demo_account_required = 'true' }
        notes = notes(gateway)
        notes.verifier!
        rejects(/illisible \(demoAccountRequired\)/) { notes.appliquer! }
        assert(gateway.patches.empty?)
      },
      'another editable version is refused at pre-flight instead of being renamed by deliver' => lambda {
        %w[1.0.8 2.0.1].each do |autre|
          gateway = FakeNotesGateway.new(edit: version(autre, 'DEVELOPER_REJECTED'))
          rejects(/est "#{Regexp.escape(autre)}", pas 2\.0\.0 : deliver la renommerait/) { notes(gateway).verifier! }
          assert((gateway.events & ECRITURES).empty? && !gateway.events.include?(:sign_in))
        end
      },
      'a version that changes or vanishes between pre-flight and write stops everything' => lambda {
        gateway = FakeNotesGateway.new
        notes = notes(gateway)
        notes.verifier!
        gateway.edit = version('2.0.0', 'PREPARE_FOR_SUBMISSION', 'other')
        rejects(/a changé depuis le pré-vol/) { notes.appliquer! }
        gateway = FakeNotesGateway.new
        notes = notes(gateway)
        notes.verifier!
        gateway.edit = nil
        rejects(/n'est plus modifiable/) { notes.appliquer! }
        assert((gateway.events & ECRITURES).empty?)
        gateway = FakeNotesGateway.new(edit: nil, detail: nil)
        notes = notes(gateway)
        notes.verifier!
        gateway.edit = version
        rejects(/a changé depuis le pré-vol/) { notes.appliquer! }
        rejects(/sans pré-vol/) { notes(FakeNotesGateway.new).appliquer! }
      },
      'notes are re-read after the write: Apple normalisation passes, a mismatch or a reset demo flag fails' => lambda {
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.cible.notes = "#{g.cible.notes.gsub("\n", "\r\n")}\r\n" }
        notes = notes(gateway)
        notes.verifier!
        assert(notes.appliquer! == :ajoute)
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.cible.notes = g.cible.notes[0, 100] }
        notes = notes(gateway)
        notes.verifier!
        rejects(/relues différentes/) { notes.appliquer! }
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.cible.demo_account_required = false }
        notes = notes(gateway)
        notes.verifier!
        rejects(/demoAccountRequired faux/) { notes.appliquer! }
      },
      'previous notes without another account address: a warning at pre-flight (verifier mode) and at write, never a failure' => lambda {
        avertissement = ->(journal) { journal.count { |m| m == N::AVERTISSEMENT_NOTES } }
        ['Version 1.0.7, three roles.', "Sign in with #{DEMO_NOM}.", "Sign in with #{DEMO_NOM.upcase}."].each do |anciennes|
          journal = []
          gateway = FakeNotesGateway.new(detail: detail(notes: anciennes))
          notes = notes(gateway, journal: journal)
          notes.verifier!
          assert(avertissement.call(journal) == 1, 'shown by the pre-flight alone, hence in verifier mode')
          assert(notes.appliquer! == :ajoute && gateway.patches.length == 1 && avertissement.call(journal) == 2)
          journal_global.concat(journal)
        end
        assert(N.autre_adresse?(ANCIENNES, DEMO_NOM) && !N.autre_adresse?("#{DEMO_NOM} only", " #{DEMO_NOM.upcase} "))
        # Adresse du compte collée à de la ponctuation (revue de #1199, n4) : ce n'est pas une autre adresse.
        ["Login:#{DEMO_NOM}", "`#{DEMO_NOM}`", "«#{DEMO_NOM}»", "**#{DEMO_NOM}**", "mailto:#{DEMO_NOM}", "<#{DEMO_NOM}>",
         "(#{DEMO_NOM})", "\"#{DEMO_NOM}\"", "'#{DEMO_NOM}'", "#{DEMO_NOM}.", "#{DEMO_NOM},", "#{DEMO_NOM};", "[#{DEMO_NOM}]"].each do |collee|
          assert(!N.autre_adresse?("Compte : #{collee} / mdp", DEMO_NOM), "glued address counted as another one: #{collee.sub(DEMO_NOM, 'NOM')}")
        end
        ['`etab-revue@example.test`', 'Login:etab-revue@example.test', '«etab-revue@example.test»'].each do |autre|
          assert(N.autre_adresse?("Soignant : `#{DEMO_NOM}` ; établissement : #{autre}", DEMO_NOM))
        end
        journal = []
        gateway = FakeNotesGateway.new(detail: detail(notes: "Login: `#{DEMO_NOM}` / mdp-fictif"))
        notes = notes(gateway, journal: journal)
        notes.verifier!
        assert(avertissement.call(journal) == 1, 'warning shown when the only address is the demo one, in backticks')
        journal_global.concat(journal)
        journal = []
        gateway = FakeNotesGateway.new
        notes = notes(gateway, journal: journal)
        notes.verifier!
        notes.appliquer!
        assert(journal.none? { |m| m.start_with?('Avertissement') })
        journal_global.concat(journal)
      },
      'gateway: exact request shapes, data null read as absent, Apple error bodies hidden' => lambda {
        client = FakeClient.new
        app = FakeApp.new
        gateway = IosReviewSubmission::ReviewNotesGateway.new(client: client, app: app)
        gateway.update_notes('d200', 'texte')
        gateway.create_version('2.0.0')
        gateway.update_review_detail('d200', { 'demoAccountName' => SRC_NOM })
        gateway.create_review_detail('v200', { 'notes' => 'x' })
        assert(client.patches == [{ app_store_review_detail_id: 'd200', attributes: { notes: 'texte' } },
                                  { app_store_review_detail_id: 'd200', attributes: { 'demoAccountName' => SRC_NOM } }])
        assert(client.posts == [{ app_id: 'app6774672845', attributes: { versionString: '2.0.0', platform: 'IOS' } }])
        assert(client.detail_posts == [{ app_store_version_id: 'v200', attributes: { 'notes' => 'x' } }])
        assert(gateway.versions_ios.map(&:id) == ['v107'])
        assert(app.filters == [{ platform: 'IOS' }], 'every iOS version, every state')
        assert(gateway.review_detail('v200').demo_account_required == true)
        client.detail_body = { 'data' => nil, 'links' => {} }
        assert(gateway.review_detail('v200').nil?, 'data null means no fiche')
        client.detail_error = RuntimeError.new("body #{DEMO_NOM} #{DEMO_MDP}")
        rejects(/illisible \(RuntimeError\)/) { gateway.review_detail('v200') }
        rejects(/Apple app is missing/) { IosReviewSubmission::ReviewNotesGateway.new(client: client, app: nil) }
        failing = Object.new
        def failing.patch_app_store_review_detail(**) = raise(RuntimeError, 'body revue-source@example.test')
        def failing.post_app_store_review_detail(**) = raise(RuntimeError, 'body mdp-source-fictif')
        gateway = IosReviewSubmission::ReviewNotesGateway.new(client: failing, app: app)
        rejects(/Écriture de la fiche de vérification refusée par Apple \(RuntimeError\)/) { gateway.update_review_detail('d', {}) }
        rejects(/Création de la fiche de vérification refusée par Apple \(RuntimeError\)/) { gateway.create_review_detail('v', {}) }
        rejects(/Écriture des notes pour la revue refusée par Apple \(RuntimeError\)/) { gateway.update_notes('d', 'n') }
      },
      'pre-flight lane context: only the gardes job of the App Store workflow on main, in either mode' => lambda {
        contexte = {
          'GITHUB_ACTIONS' => 'true', 'GITHUB_REPOSITORY' => 'Gabpcd/JJJJJ', 'GITHUB_EVENT_NAME' => 'workflow_dispatch',
          'GITHUB_REF' => 'refs/heads/main', 'GITHUB_WORKFLOW_REF' => IosReviewSubmission::WORKFLOW_SOUMISSION
        }
        %w[verifier soumettre].each do |mode|
          assert(IosReviewSubmission.exiger_contexte_prevol!(env: contexte.merge('IOS_NATIVE_MODE' => mode)) == true)
        end
        rejects(/écart : IOS_NATIVE_MODE/) { IosReviewSubmission.exiger_contexte_prevol!(env: contexte) }
        rejects(/écart : GITHUB_ACTIONS/) { IosReviewSubmission.exiger_contexte_prevol!(env: { 'IOS_NATIVE_MODE' => 'verifier' }) }
        { 'GITHUB_REF' => 'refs/heads/autre', 'GITHUB_EVENT_NAME' => 'push',
          'GITHUB_WORKFLOW_REF' => 'Gabpcd/JJJJJ/.github/workflows/mobile-store-status.yml@refs/heads/main' }.each do |cle, valeur|
          rejects(/écart : #{cle}/) { IosReviewSubmission.exiger_contexte_prevol!(env: contexte.merge('IOS_NATIVE_MODE' => 'verifier', cle => valeur)) }
        end
      },
      'sequence: nominal order, already submitted no-op, absent build' => lambda {
        events = []
        result = enchainer(notes(FakeNotesGateway.new(events: events)), StubGuard.new(events), events)
        assert(result == :submitted)
        assert(events == %i[edit_version read_detail sign_in guard_prepare edit_version read_detail patch_notes read_detail submit])
        events = []
        gateway = FakeNotesGateway.new(edit: version('2.0.0', 'WAITING_FOR_REVIEW'), events: events)
        assert(enchainer(notes(gateway), StubGuard.new(events, result: :already_submitted), events) == :already_submitted)
        assert((events & ECRITURES).empty? && !events.include?(:submit))
        # WAITING_FOR_REVIEW est modifiable : fiche lue et compte connecté, avant qu'un relecteur n'ouvre la version.
        assert(events == %i[edit_version read_detail sign_in guard_prepare])
        events = []
        rejects(/build absent/) { enchainer(notes(FakeNotesGateway.new(events: events)), StubGuard.new(events, build_present: false), events) }
        assert(!events.include?(:submit) && (events & ECRITURES).empty?)
      },
      'sequence: copy, then notes, then submission' => lambda {
        events = []
        gateway = FakeNotesGateway.new(detail: detail(mdp: ''), events: events)
        assert(enchainer(notes(gateway), StubGuard.new(events), events) == :submitted)
        assert(events.index(:sign_in) < events.index(:guard_prepare) && events.index(:guard_prepare) < events.index(:update_detail))
        assert(events.index(:update_detail) < events.index(:patch_notes) && events.index(:patch_notes) < events.index(:submit))
      },
      'sequence with the real review guard: the lock fails before any cancellation of a waiting review' => lambda {
        review = IosReviewSubmissionTest::FakeGateway.new
        guard = IosReviewSubmissionTest.guard(review)
        events = []
        gateway = FakeNotesGateway.new(edit: version('1.0.6', 'WAITING_FOR_REVIEW', 'v106'), detail: detail(mdp: ''), events: events,
          source: version('1.0.5', 'READY_FOR_DISTRIBUTION', 'v105'), source_detail: source_detail(required: false))
        rejects(/mot de passe vide/) { enchainer(notes(gateway, marketing: '1.0.6'), guard, events) }
        assert(review.cancellations.empty? && review.version_rows.last.app_version_state == 'WAITING_FOR_REVIEW')
        assert(!events.include?(:submit) && (events & ECRITURES).empty?)
      },
      'sequence with the real review guard: a refused sign-in fails before any cancellation' => lambda {
        review = IosReviewSubmissionTest::FakeGateway.new
        guard = IosReviewSubmissionTest.guard(review)
        events = []
        gateway = FakeNotesGateway.new(edit: version('1.0.6', 'WAITING_FOR_REVIEW', 'v106'), events: events,
          source: version('1.0.5', 'READY_FOR_DISTRIBUTION', 'v105'))
        compte = C.new(url: URL, cle: CLE, transport: http(token: [400, '{}']))
        rejects(/connexion refusée \(HTTP 400\)/) { enchainer(notes(gateway, marketing: '1.0.6', compte: compte), guard, events) }
        assert(review.cancellations.empty? && (events & ECRITURES).empty?)
      },
      'sequence with the real review guard: cancellation, then copy and notes, then submission' => lambda {
        [detail, nil].each do |fiche|
          review = IosReviewSubmissionTest::FakeGateway.new
          guard = IosReviewSubmissionTest.guard(review)
          events = review.events
          gateway = FakeNotesGateway.new(edit: version('1.0.6', 'WAITING_FOR_REVIEW', 'v106'), detail: fiche, events: events,
            source: version('1.0.5', 'READY_FOR_DISTRIBUTION', 'v105'))
          gateway.on_edit = ->(g) { g.edit.app_version_state = review.version_rows.last.app_version_state }
          assert(enchainer(notes(gateway, marketing: '1.0.6'), guard, events) == :submitted)
          assert(review.cancellations == ['s106'] && events.index(:sign_in) < events.index(:cancel))
          assert(events.index(:cancel) < events.index(:patch_notes) && events.index(:patch_notes) < events.index(:submit))
          if fiche.nil?
            assert(events.index(:cancel) < events.index(:create_detail) && events.index(:create_detail) < events.index(:patch_notes))
          else
            assert(!events.include?(:create_detail) && !events.include?(:update_detail))
          end
        end
      },
      'no journal line ever carries an account value, a token, an id or the notes text' => lambda {
        assert(journal_global.length >= 10)
        journal_global.each do |message|
          (SECRETS + [BLOC, BLOC_ETAB, SEP, ANCIENNES]).each { |secret| assert(!message.include?(secret), "journal echoes: #{message}") }
        end
        lignes_compte = journal_global.grep(/\Acompte de démo :/)
        assert(lignes_compte.uniq.sort == ['compte de démo : connexion OK, rôle soignant', 'compte de démo : connexion OK, rôle établissement'].sort)
      }
    }
    cases.each { |name, test| test.call; puts "PASS: #{name}" }
    puts "#{cases.length} iOS review notes checks passed (fixtures only)."
  end
end

IosReviewNotesTest.run if $PROGRAM_NAME == __FILE__
