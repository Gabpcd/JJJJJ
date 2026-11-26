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
  ETAB = 'etab-revue@example.test / mdp-etab-fictif'
  ANCIENNES = "Version 1.0.7. Compte établissement : #{ETAB}\nCompte administrateur : voir ci-dessus."
  SECRETS = [DEMO_NOM, DEMO_MDP, 'etab-revue@example.test', 'mdp-etab-fictif', 'Compte administrateur'].freeze

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

  def self.detail(notes: ANCIENNES, required: true, nom: DEMO_NOM, mdp: DEMO_MDP)
    OpenStruct.new(id: 'd200', notes: notes, demo_account_required: required, demo_account_name: nom,
      demo_account_password: mdp, contact_email: 'contact@example.test', contact_phone: '+33100000000')
  end

  def self.version(chaine = '2.0.0', state = 'PREPARE_FOR_SUBMISSION', id = 'v200')
    OpenStruct.new(id: id, version_string: chaine, platform: 'IOS', app_version_state: state)
  end

  class FakeNotesGateway
    attr_accessor :edit, :detail, :on_patch, :on_edit, :detail_after_create
    attr_reader :events, :patches, :created, :edit_reads
    def initialize(edit: IosReviewNotesTest.version, detail: IosReviewNotesTest.detail, events: [])
      @edit, @detail, @events, @patches, @created, @edit_reads = edit, detail, events, [], [], 0
    end
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
      @detail = @detail_after_create if @detail_after_create
    end
    def review_detail(_version_id)
      @events << :read_detail
      raise IosReviewSubmission::Failure, 'Fiche absente ou illisible (fixture)' if @detail.nil?
      @detail.dup
    end
    def update_notes(id, notes)
      @events << :patch_notes
      @patches << [id, notes]
      @detail.notes = notes
      @on_patch&.call(self)
    end
  end

  def self.notes(gateway, journal: [], marketing: '2.0.0', bloc: BLOC)
    N.new(gateway: gateway, marketing_version: marketing, bloc: bloc, journal: ->(message) { journal << message })
  end

  # Client Spaceship simulé : vérifie la forme exacte des requêtes de ReviewNotesGateway.
  class FakeClient
    attr_reader :posts, :patches
    attr_accessor :detail_error
    def initialize
      @posts, @patches = [], []
    end
    def post_app_store_version(**args) = @posts << args
    def patch_app_store_review_detail(**args) = @patches << args
    def get_app_store_review_detail(**)
      raise detail_error if detail_error
      OpenStruct.new(to_models: [IosReviewNotesTest.detail])
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
        stockees = "#{ancienne_version}\n\n#{SEP}\n#{ANCIENNES}"
        result = N.composer(bloc: BLOC, existantes: stockees)
        assert(result[:statut] == :remplace)
        assert(result[:notes] == "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}")
        assert(!result[:notes].include?('older wording') && result[:notes].scan(SEP).length == 1)
        assert(N.composer(bloc: BLOC, existantes: result[:notes])[:statut] == :inchange)
        # A longer previous block that starts with the current one is still replaced, not kept.
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
      'existing editable version: dry pre-flight, then only the notes field is written, once' => lambda {
        journal = []
        gateway = FakeNotesGateway.new
        avant = gateway.detail.to_h
        notes = notes(gateway, journal: journal)
        assert(notes.verifier! == :pret && gateway.patches.empty? && gateway.created.empty?)
        assert(notes.appliquer! == :ajoute)
        assert(gateway.patches == [['d200', "#{BLOC}\n\n#{SEP}\n#{ANCIENNES}"]])
        apres = gateway.detail.to_h
        assert(apres.reject { |k, _| k == :notes } == avant.reject { |k, _| k == :notes }, 'only notes change')
        rerun = notes(gateway, journal: journal)
        assert(rerun.verifier! == :pret && rerun.appliquer! == :inchange && gateway.patches.length == 1)
        journal_global.concat(journal)
      },
      'absent version: nothing is created at pre-flight, then it is created once before the notes' => lambda {
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events)
        gateway.detail_after_create = detail
        notes = notes(gateway, journal: journal_global)
        assert(notes.verifier! == :a_creer && gateway.created.empty? && events == [:edit_version])
        assert(notes.appliquer! == :ajoute && gateway.created == ['2.0.0'])
        assert(events == %i[edit_version edit_version create_version edit_version read_detail patch_notes read_detail])
      },
      'created version without a complete demo account fails before any notes write' => lambda {
        [detail(required: false), detail(mdp: ''), nil].each do |copie|
          gateway = FakeNotesGateway.new(edit: nil, detail: nil)
          gateway.detail_after_create = copie
          notes = notes(gateway)
          notes.verifier!
          rejects(/Compte de démonstration incomplet|absente ou illisible/) { notes.appliquer! }
          assert(gateway.patches.empty?)
        end
      },
      'another editable version is refused at pre-flight instead of being renamed by deliver' => lambda {
        %w[1.0.8 2.0.1].each do |autre|
          gateway = FakeNotesGateway.new(edit: version(autre, 'DEVELOPER_REJECTED'))
          rejects(/est "#{Regexp.escape(autre)}", pas 2\.0\.0 : deliver la renommerait/) { notes(gateway).verifier! }
          assert(gateway.patches.empty? && gateway.created.empty?)
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
        assert(gateway.created.empty? && gateway.patches.empty?)
        gateway = FakeNotesGateway.new(edit: nil, detail: nil)
        notes = notes(gateway)
        notes.verifier!
        gateway.edit = version
        rejects(/a changé depuis le pré-vol/) { notes.appliquer! }
        rejects(/sans pré-vol/) { notes(FakeNotesGateway.new).appliquer! }
      },
      'notes are re-read after the write: Apple normalisation passes, a mismatch or a reset demo flag fails' => lambda {
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.detail.notes = "#{g.detail.notes.gsub("\n", "\r\n")}\r\n" }
        notes = notes(gateway)
        notes.verifier!
        assert(notes.appliquer! == :ajoute)
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.detail.notes = g.detail.notes[0, 100] }
        notes = notes(gateway)
        notes.verifier!
        rejects(/relues différentes/) { notes.appliquer! }
        gateway = FakeNotesGateway.new
        gateway.on_patch = ->(g) { g.detail.demo_account_required = false }
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
      'gateway sends only the notes attribute, creates the version like ensure_version!, hides Apple error bodies' => lambda {
        client = FakeClient.new
        app = OpenStruct.new(id: 'app6774672845')
        gateway = IosReviewSubmission::ReviewNotesGateway.new(client: client, app: app)
        gateway.update_notes('d200', 'texte')
        gateway.create_version('2.0.0')
        assert(client.patches == [{ app_store_review_detail_id: 'd200', attributes: { notes: 'texte' } }])
        assert(client.posts == [{ app_id: 'app6774672845', attributes: { versionString: '2.0.0', platform: 'IOS' } }])
        assert(gateway.review_detail('v200').demo_account_required == true)
        client.detail_error = RuntimeError.new("body #{DEMO_NOM} #{DEMO_MDP}")
        rejects(/absente ou illisible \(RuntimeError\)/) { gateway.review_detail('v200') }
        rejects(/Apple app is missing/) { IosReviewSubmission::ReviewNotesGateway.new(client: client, app: nil) }
      },
      'sequence: a lock failure at pre-flight reaches neither the review guards nor the submission' => lambda {
        events = []
        gateway = FakeNotesGateway.new(detail: detail(required: false), events: events)
        rejects(/demoAccountRequired faux/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert(events == %i[edit_version read_detail] && gateway.patches.empty?)
      },
      'sequence: a lock failure after creating the version submits nothing' => lambda {
        events = []
        gateway = FakeNotesGateway.new(edit: nil, detail: nil, events: events)
        gateway.detail_after_create = detail(nom: '')
        rejects(/nom du compte vide/) { enchainer(notes(gateway), StubGuard.new(events), events) }
        assert(!events.include?(:submit) && !events.include?(:patch_notes) && events.include?(:guard_prepare))
      },
      'sequence: nominal order, already submitted no-op, absent build' => lambda {
        events = []
        result = enchainer(notes(FakeNotesGateway.new(events: events)), StubGuard.new(events), events)
        assert(result == :submitted)
        assert(events == %i[edit_version read_detail guard_prepare edit_version read_detail patch_notes read_detail submit])
        events = []
        gateway = FakeNotesGateway.new(edit: version('2.0.0', 'WAITING_FOR_REVIEW'), events: events)
        assert(enchainer(notes(gateway), StubGuard.new(events, result: :already_submitted), events) == :already_submitted)
        assert(!events.include?(:patch_notes) && !events.include?(:submit))
        events = []
        rejects(/build absent/) { enchainer(notes(FakeNotesGateway.new(events: events)), StubGuard.new(events, build_present: false), events) }
        assert(!events.include?(:submit) && !events.include?(:patch_notes))
      },
      'sequence with the real review guard: the lock fails before any cancellation of a waiting review' => lambda {
        review = IosReviewSubmissionTest::FakeGateway.new
        guard = IosReviewSubmissionTest.guard(review)
        events = []
        gateway = FakeNotesGateway.new(edit: version('1.0.6', 'WAITING_FOR_REVIEW', 'v106'), detail: detail(mdp: ''), events: events)
        rejects(/mot de passe vide/) { enchainer(notes(gateway, marketing: '1.0.6'), guard, events) }
        assert(review.cancellations.empty? && review.version_rows.last.app_version_state == 'WAITING_FOR_REVIEW')
        assert(!events.include?(:submit) && gateway.patches.empty?)
      },
      'sequence with the real review guard: cancellation, then notes, then submission' => lambda {
        review = IosReviewSubmissionTest::FakeGateway.new
        guard = IosReviewSubmissionTest.guard(review)
        events = review.events
        gateway = FakeNotesGateway.new(edit: version('1.0.6', 'WAITING_FOR_REVIEW', 'v106'), events: events)
        gateway.on_edit = ->(g) { g.edit.app_version_state = review.version_rows.last.app_version_state }
        assert(enchainer(notes(gateway, marketing: '1.0.6'), guard, events) == :submitted)
        assert(review.cancellations == ['s106'])
        assert(events.index(:cancel) < events.index(:patch_notes) && events.index(:patch_notes) < events.index(:submit))
      },
      'no journal line ever carries an account value or the notes text' => lambda {
        assert(!journal_global.empty?)
        journal_global.each do |message|
          (SECRETS + [BLOC, SEP]).each { |secret| assert(!message.include?(secret), "journal echoes: #{message}") }
        end
      }
    }
    cases.each { |name, test| test.call; puts "PASS: #{name}" }
    puts "#{cases.length} iOS review notes checks passed (fixtures only)."
  end
end

IosReviewNotesTest.run if $PROGRAM_NAME == __FILE__
