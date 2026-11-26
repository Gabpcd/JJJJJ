#!/usr/bin/env ruby
# Fixtures only: no Fastlane load, credentials, or network. Every account value below is fictitious.
require 'ostruct'
require_relative 'ios_review_notes'
require_relative 'ios_review_submission.test'

module IosReviewNotesTest
  ROOT = File.expand_path('..', __dir__)
  N = IosReviewSubmission::ReviewNotes
  SEP = N::SEPARATEUR
  BLOC = "Jolene 2.0 fixture block.\n\nSecond paragraph of the fixture block."
  DEMO_NOM = 'revue-soignant@example.test'
  DEMO_MDP = 'mdp-fictif'
  SRC_NOM = 'revue-source@example.test'
  SRC_MDP = 'mdp-source-fictif'
  SRC_CONTACT = { contact_first_name: 'Prenom-source', contact_last_name: 'Nom-source',
                  contact_phone: '+33100000001', contact_email: 'contact-source@example.test' }.freeze
  ETAB = 'etab-revue@example.test / mdp-etab-fictif'
  ANCIENNES = "Version 1.0.7. Compte établissement : #{ETAB}\nCompte administrateur : voir ci-dessus."
  SECRETS = [DEMO_NOM, DEMO_MDP, SRC_NOM, SRC_MDP, *SRC_CONTACT.values, 'contact@example.test', '+33100000000',
             'etab-revue@example.test', 'mdp-etab-fictif', 'Compte administrateur'].freeze

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
        source: IosReviewNotesTest.version('1.0.7', 'READY_FOR_DISTRIBUTION', 'v107'), source_detail: IosReviewNotesTest.source_detail)
      @edit, @events, @patches, @created, @copies, @edit_reads, @illisibles = edit, events, [], [], [], 0, []
      @details = {}
      @details[edit.id] = detail if edit
      @distribuees = source ? [source] : []
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
    def distributed_versions
      @events << :read_distributed
      @distribuees.map(&:dup)
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

  def self.notes(gateway, journal: [], marketing: '2.0.0', bloc: BLOC)
    N.new(gateway: gateway, marketing_version: marketing, bloc: bloc, journal: ->(message) { journal << message })
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
      'composition puts the block, a blank line and the separator before untouched previous notes' => lambda {
        result = N.composer(bloc: BLOC, existantes: ANCIENNES)
        assert(result[:statut] == :ajoute)
        assert(result[:notes] == "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}")
        assert(result[:anciennes_avec_email])
      },
      'composition is idempotent, including after Apple normalises line endings and trailing spaces' => lambda {
        premiere = N.composer(bloc: BLOC, existantes: ANCIENNES)[:notes]
        again = N.composer(bloc: BLOC, existantes: premiere)
        assert(again[:statut] == :inchange && again[:notes] == premiere)
        crlf = N.composer(bloc: "#{BLOC}\n", existantes: "  #{premiere.gsub("\n", "\r\n")}  \r\n")
        assert(crlf[:statut] == :inchange && crlf[:anciennes_avec_email])
      },
      'a block already at the head without separator is never doubled' => lambda {
        result = N.composer(bloc: BLOC, existantes: "#{BLOC}\n#{ANCIENNES}")
        assert(result[:statut] == :inchange && result[:notes].scan(BLOC).length == 1)
        assert(N.composer(bloc: BLOC, existantes: BLOC)[:statut] == :inchange)
      },
      'a previous version of the block at the head is replaced, previous notes kept once' => lambda {
        ancienne_version = "Jolene 2.0 draft block, older wording.\nWith a second line."
        result = N.composer(bloc: BLOC, existantes: "#{ancienne_version}\n\n#{SEP}\n#{ANCIENNES}")
        assert(result[:statut] == :remplace)
        assert(result[:notes] == "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}")
        assert(!result[:notes].include?('older wording') && result[:notes].scan(SEP).length == 1)
        assert(N.composer(bloc: BLOC, existantes: result[:notes])[:statut] == :inchange)
        plus_long = N.composer(bloc: BLOC, existantes: "#{BLOC}\nExtra sentence.\n\n#{SEP}\n#{ANCIENNES}")
        assert(plus_long[:statut] == :remplace && !plus_long[:notes].include?('Extra sentence'))
      },
      'empty previous notes give the block and the separator, without an address' => lambda {
        [nil, '', "  \n"].each do |vide|
          result = N.composer(bloc: BLOC, existantes: vide)
          assert(result[:statut] == :ajoute && result[:notes] == "#{BLOC}\n\n#{SEP}" && !result[:anciennes_avec_email])
          assert(N.composer(bloc: BLOC, existantes: result[:notes])[:statut] == :inchange)
        end
      },
      'the Apple limit of 4000 characters is enforced on the composed notes, without echoing them' => lambda {
        fixe = "#{BLOC}\n\n#{SEP}\n".length
        juste = 'a' * (N::LIMITE - fixe)
        assert(N.composer(bloc: BLOC, existantes: juste)[:notes].length == N::LIMITE)
        error = rejects(/trop longues : 4001 caractères pour 4000/) { N.composer(bloc: BLOC, existantes: "#{juste}b") }
        assert(!error.message.include?('aaaa'), 'notes are never echoed')
        rejects(/trop longues/) { N.composer(bloc: BLOC, existantes: "#{ANCIENNES}\n#{'x' * N::LIMITE}") }
      },
      'ambiguous separators and a block repeated in previous notes stop the composition' => lambda {
        rejects(/2 lignes de séparation/) { N.composer(bloc: BLOC, existantes: "x\n#{SEP}\ny\n#{SEP}\n#{ANCIENNES}") }
        rejects(/apparaîtrait 2 fois/) { N.composer(bloc: BLOC, existantes: "Old head\n#{SEP}\n#{BLOC}\n#{ANCIENNES}") }
      },
      'the versioned block is validated: not empty, no address, no separator, room left' => lambda {
        rejects(/est vide/) { N.valider_bloc!(" \n") }
        rejects(/adresse e-mail/) { N.valider_bloc!("Use #{DEMO_NOM} to sign in.") }
        rejects(/ligne de séparation/) { N.valider_bloc!("Head\n#{SEP}\nTail") }
        rejects(/dépasse seul la limite/) { N.valider_bloc!('z' * (N::LIMITE - SEP.length - 1)) }
      },
      'the repository block passes its own validation and leaves room for the previous notes' => lambda {
        bloc = N.valider_bloc!(File.read(File.join(ROOT, N::FICHIER), encoding: 'UTF-8'))
        assert(bloc.start_with?('Jolene 2.0 is a native (Swift) rewrite of the app and replaces version 1.0.7.'))
        assert(bloc.include?('Profil > "Suppression de compte" > "Supprimer mon compte"'))
        assert(bloc.include?('Compte > Aide & légal > "Supprimer mon compte"'))
        assert(bloc.length < 2500, "block too long: #{bloc.length}")
      },
      'demo account lock: required flag, name and password, never echoing a value' => lambda {
        assert(N.exiger_compte_demo!(detail, '2.0.0') == true)
        rejects(/demoAccountRequired faux/) { N.exiger_compte_demo!(detail(required: false), '2.0.0') }
        rejects(/demoAccountRequired faux/) { N.exiger_compte_demo!(detail(required: 'true'), '2.0.0') }
        rejects(/nom du compte vide/) { N.exiger_compte_demo!(detail(nom: '  '), '2.0.0') }
        rejects(/mot de passe vide/) { N.exiger_compte_demo!(detail(mdp: nil), '2.0.0') }
        rejects(/fiche absente/) { N.exiger_compte_demo!(nil, '2.0.0') }
        error = rejects(/Compte de démonstration incomplet.*APP_STORE\.md/) { N.exiger_compte_demo!(detail(required: false, nom: '', mdp: ''), '2.0.0') }
        assert(error.message.include?('nom du compte vide, mot de passe vide'))
      },
      'copy attributes: whole fiche when the target has none, untransformed source values' => lambda {
        attributs = N.attributs_de_copie(source: source_detail, cible: nil, marketing: '2.0.0', source_version: '1.0.7')
        attendu = { 'demoAccountName' => SRC_NOM, 'demoAccountPassword' => SRC_MDP, 'demoAccountRequired' => true,
                    'contactFirstName' => 'Prenom-source', 'contactLastName' => 'Nom-source', 'contactPhone' => '+33100000001',
                    'contactEmail' => 'contact-source@example.test', 'notes' => ANCIENNES }
        assert(attributs == attendu)
        assert(attributs.keys.sort == N::CHAMPS_COPIE.keys.sort, 'no attribute outside the copy list')
        vide = N.attributs_de_copie(source: source_detail(contact_phone: '', notes: nil), cible: nil, marketing: '2.0.0', source_version: '1.0.7')
        assert(!vide.key?('contactPhone') && !vide.key?('notes'), 'an empty source value is never written')
      },
      'copy attributes: demo account as a whole, other fields only where the target is empty, never over a complete target' => lambda {
        cible = detail(required: false, nom: 'nom-partiel-cible', mdp: '', notes: '', contact_email: '', contact_phone: nil)
        attributs = N.attributs_de_copie(source: source_detail, cible: cible, marketing: '2.0.0', source_version: '1.0.7')
        assert(attributs.keys.sort == %w[contactEmail contactPhone demoAccountName demoAccountPassword demoAccountRequired notes].sort)
        assert(attributs['demoAccountName'] == SRC_NOM, 'an incomplete demo account is replaced as a whole')
        assert(N.attributs_de_copie(source: source_detail, cible: detail, marketing: '2.0.0', source_version: '1.0.7').nil?)
        assert(N.attributs_de_copie(source: nil, cible: detail, marketing: '2.0.0', source_version: '1.0.7').nil?)
        fusion = N.fusionner(cible, attributs)
        assert(fusion.id == 'd200' && fusion.contact_first_name == 'Prenom' && fusion.contact_email == 'contact-source@example.test')
        assert(N.compte_demo_complet?(fusion) && fusion.notes == ANCIENNES)
      },
      'copy attributes: a source without a complete demo account is refused, naming both gaps without values' => lambda {
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
      'existing complete version: dry pre-flight, then only the notes field is written, once; the source is never read' => lambda {
        journal = []
        gateway = FakeNotesGateway.new
        avant = gateway.cible.to_h
        notes = notes(gateway, journal: journal)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty?)
        assert(notes.appliquer! == :ajoute)
        assert(gateway.patches == [['d200', "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}"]] && gateway.copies.empty?)
        assert(gateway.cible.to_h.reject { |k, _| k == :notes } == avant.reject { |k, _| k == :notes }, 'only notes change')
        assert(!gateway.events.include?(:read_distributed))
        rerun = notes(gateway, journal: journal)
        assert(rerun.verifier! == :pret && rerun.appliquer! == :inchange && gateway.patches.length == 1)
        journal_global.concat(journal)
      },
      'target fiche without demo account: pre-flight reads the source and writes nothing; the copy happens at the write step' => lambda {
        journal = []
        cible = detail(required: false, nom: '', mdp: '', notes: 'Notes 2.0 déjà saisies, sans adresse.', contact_first_name: 'Prenom-cible')
        gateway = FakeNotesGateway.new(detail: cible)
        notes = notes(gateway, journal: journal)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty? && gateway.events.include?(:read_distributed))
        assert(notes.appliquer! == :ajoute)
        assert(gateway.copies.length == 1 && gateway.copies.first[0..1] == [:update, 'd200'])
        assert(gateway.copies.first[2].keys.sort == %w[demoAccountName demoAccountPassword demoAccountRequired])
        assert(gateway.cible.contact_first_name == 'Prenom-cible' && gateway.cible.demo_account_name == SRC_NOM)
        assert(gateway.patches.last[1] == "#{BLOC}\n\n#{SEP}\nNotes 2.0 déjà saisies, sans adresse.", 'existing target notes are kept')
        ordre = gateway.events
        assert(ordre.index(:update_detail) < ordre.index(:patch_notes))
        assert(journal.any? { |m| m.include?('complétée depuis la version distribuée 1.0.7 (champs copiés : demoAccountName, demoAccountPassword, demoAccountRequired') })
        rerun = notes(gateway, journal: journal)
        assert(rerun.verifier! == :pret && rerun.appliquer! == :inchange && gateway.copies.length == 1, 'the copy happens once')
        journal_global.concat(journal)
      },
      'version without any fiche: the whole fiche is created from the source, then the block goes before the copied notes' => lambda {
        journal = []
        gateway = FakeNotesGateway.new(detail: nil)
        notes = notes(gateway, journal: journal)
        assert(notes.verifier! == :pret && (gateway.events & ECRITURES).empty?)
        assert(notes.appliquer! == :ajoute)
        assert(gateway.copies.length == 1 && gateway.copies.first[0..1] == [:create, 'v200'])
        assert(gateway.copies.first[2].keys.sort == N::CHAMPS_COPIE.keys.sort)
        assert(gateway.patches == [['dNew', "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}"]])
        assert(journal.any? { |m| m.include?('créée depuis la version distribuée 1.0.7') })
        journal_global.concat(journal)
      },
      'absent version: created once after the guards, Apple copy kept when complete, source used as forecast only' => lambda {
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events)
        gateway.detail_after_create = detail
        notes = notes(gateway, journal: journal_global)
        assert(notes.verifier! == :a_creer && gateway.created.empty? && (events & ECRITURES).empty?)
        assert(events == %i[edit_version read_distributed read_detail])
        assert(notes.appliquer! == :ajoute && gateway.created == ['2.0.0'] && gateway.copies.empty?)
        assert(events.drop(3) == %i[edit_version create_version edit_version read_detail patch_notes read_detail])
      },
      'absent version created by Apple without demo account: the copy from the source completes it' => lambda {
        [nil, detail(required: false, mdp: '')].each do |copie_apple|
          gateway = FakeNotesGateway.new(edit: nil, detail: nil)
          gateway.detail_after_create = copie_apple
          notes = notes(gateway)
          notes.verifier!
          assert(notes.appliquer! == :ajoute && gateway.copies.length == 1 && N.compte_demo_complet?(gateway.cible))
          assert(gateway.copies.first[0] == (copie_apple ? :update : :create))
        end
      },
      'no complete demo account anywhere: refused, nothing copied, nothing submitted' => lambda {
        events = []
        gateway = FakeNotesGateway.new(detail: detail(required: false), source_detail: source_detail(mdp: ''), events: events)
        rejects(/et dans la version distribuée 1\.0\.7 \(mot de passe vide\)/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert(events == %i[edit_version read_detail read_distributed read_detail] && gateway.copies.empty?)
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, source_detail: nil, events: events)
        rejects(/version distribuée 1\.0\.7 \(fiche absente\)/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert((events & ECRITURES).empty? && !events.include?(:guard_prepare), 'stopped before creating the version')
        gateway = FakeNotesGateway.new(detail: detail(nom: ''), source: nil)
        rejects(/aucune version distribuée d'où le copier/) { notes(gateway).verifier! }
      },
      'no distributed version and an Apple copy without demo account: the version is created, then the lock refuses' => lambda {
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, source: nil, events: events)
        gateway.detail_after_create = detail(nom: '')
        rejects(/nom du compte vide\) et aucune version distribuée/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert(events.include?(:create_version) && !events.include?(:submit) && gateway.copies.empty? && gateway.patches.empty?)
      },
      'an unreadable target fiche is never taken for an absent one: nothing is copied' => lambda {
        gateway = FakeNotesGateway.new
        gateway.illisibles << 'v200'
        rejects(/illisible/) { notes(gateway).verifier! }
        assert(gateway.copies.empty? && !gateway.events.include?(:read_distributed))
      },
      'the copied fiche is re-read: a mismatch or a vanished fiche stops before the notes' => lambda {
        gateway = FakeNotesGateway.new(detail: detail(required: false))
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
        # Same text once normalised, but not the boolean Apple must hold: the lock still refuses before the notes.
        gateway = FakeNotesGateway.new(detail: detail(required: false))
        gateway.on_copy = ->(g) { g.cible.demo_account_required = 'true' }
        notes = notes(gateway)
        notes.verifier!
        rejects(/demoAccountRequired faux/) { notes.appliquer! }
        assert(gateway.patches.empty?)
      },
      'another editable version is refused at pre-flight instead of being renamed by deliver' => lambda {
        %w[1.0.8 2.0.1].each do |autre|
          gateway = FakeNotesGateway.new(edit: version(autre, 'DEVELOPER_REJECTED'))
          rejects(/est "#{Regexp.escape(autre)}", pas 2\.0\.0 : deliver la renommerait/) { notes(gateway).verifier! }
          assert((gateway.events & ECRITURES).empty?)
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
      'previous notes without an address only log a warning' => lambda {
        journal = []
        gateway = FakeNotesGateway.new(detail: detail(notes: 'Version 1.0.7, three roles.'))
        notes = notes(gateway, journal: journal)
        notes.verifier!
        assert(notes.appliquer! == :ajoute && gateway.patches.length == 1)
        assert(journal.count { |m| m.start_with?('Avertissement : les notes de la version précédente ne contiennent aucune adresse e-mail') } == 1)
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
        assert(gateway.distributed_versions.map(&:id) == ['v107'])
        assert(app.filters == [{ appVersionState: 'READY_FOR_DISTRIBUTION', platform: 'IOS' }])
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
        rejects(/Copie de la fiche de vérification refusée par Apple \(RuntimeError\)/) { gateway.update_review_detail('d', {}) }
        rejects(/Création de la fiche de vérification refusée par Apple \(RuntimeError\)/) { gateway.create_review_detail('v', {}) }
        rejects(/Écriture des notes pour la revue refusée par Apple \(RuntimeError\)/) { gateway.update_notes('d', 'n') }
      },
      'sequence: nominal order, already submitted no-op, absent build' => lambda {
        events = []
        result = enchainer(notes(FakeNotesGateway.new(events: events)), StubGuard.new(events), events)
        assert(result == :submitted)
        assert(events == %i[edit_version read_detail guard_prepare edit_version read_detail patch_notes read_detail submit])
        events = []
        gateway = FakeNotesGateway.new(edit: version('2.0.0', 'WAITING_FOR_REVIEW'), events: events)
        assert(enchainer(notes(gateway), StubGuard.new(events, result: :already_submitted), events) == :already_submitted)
        assert((events & ECRITURES).empty? && !events.include?(:submit))
        events = []
        rejects(/build absent/) { enchainer(notes(FakeNotesGateway.new(events: events)), StubGuard.new(events, build_present: false), events) }
        assert(!events.include?(:submit) && (events & ECRITURES).empty?)
      },
      'sequence: copy, then notes, then submission' => lambda {
        events = []
        gateway = FakeNotesGateway.new(detail: detail(mdp: ''), events: events)
        assert(enchainer(notes(gateway), StubGuard.new(events), events) == :submitted)
        assert(events.index(:guard_prepare) < events.index(:update_detail))
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
      'sequence with the real review guard: cancellation, then copy and notes, then submission' => lambda {
        [detail, nil].each do |fiche|
          review = IosReviewSubmissionTest::FakeGateway.new
          guard = IosReviewSubmissionTest.guard(review)
          events = review.events
          gateway = FakeNotesGateway.new(edit: version('1.0.6', 'WAITING_FOR_REVIEW', 'v106'), detail: fiche, events: events,
            source: version('1.0.5', 'READY_FOR_DISTRIBUTION', 'v105'))
          gateway.on_edit = ->(g) { g.edit.app_version_state = review.version_rows.last.app_version_state }
          assert(enchainer(notes(gateway, marketing: '1.0.6'), guard, events) == :submitted)
          assert(review.cancellations == ['s106'])
          assert(events.index(:cancel) < events.index(:patch_notes) && events.index(:patch_notes) < events.index(:submit))
          if fiche.nil?
            assert(events.index(:cancel) < events.index(:create_detail) && events.index(:create_detail) < events.index(:patch_notes))
          else
            assert(!events.include?(:create_detail) && !events.include?(:update_detail))
          end
        end
      },
      'no journal line ever carries an account value or the notes text' => lambda {
        assert(journal_global.length >= 8)
        journal_global.each do |message|
          (SECRETS + [BLOC, SEP, ANCIENNES]).each { |secret| assert(!message.include?(secret), "journal echoes: #{message}") }
        end
      }
    }
    cases.each { |name, test| test.call; puts "PASS: #{name}" }
    puts "#{cases.length} iOS review notes checks passed (fixtures only)."
  end
end

IosReviewNotesTest.run if $PROGRAM_NAME == __FILE__
