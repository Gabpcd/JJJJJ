#!/usr/bin/env ruby
# Fixtures only: no Fastlane load, credentials, or network.
require 'ostruct'
require_relative 'ios_review_submission'

module IosReviewSubmissionTest
  def self.assert(value, message = 'assertion failed')
    raise message unless value
  end

  def self.rejects(pattern, &block)
    error = begin
      block.call
      nil
    rescue IosReviewSubmission::Failure => failure
      failure
    end
    assert(error && error.message.match?(pattern), "Expected #{pattern}, got #{error&.message.inspect}")
  end

  def self.build(id = 'b24', number = '24', marketing = '1.0.6', platform = 'IOS', state = 'VALID')
    OpenStruct.new(id: id, version: number, app_version: marketing, platform: platform,
      pre_release_version: OpenStruct.new(version: marketing, platform: platform),
      processing_state: state, expired: false, uses_non_exempt_encryption: false)
  end

  def self.version(state = 'WAITING_FOR_REVIEW', linked = build('b23', '23'))
    OpenStruct.new(id: 'v106', version_string: '1.0.6', platform: 'IOS', app_version_state: state, build: linked)
  end

  def self.submission(state = 'WAITING_FOR_REVIEW')
    OpenStruct.new(id: 's106', platform: 'IOS', state: state, app_store_version_for_review: OpenStruct.new(id: 'v106'))
  end

  def self.item
    OpenStruct.new(id: 'i106', state: 'WAITING_FOR_REVIEW', app_store_version: OpenStruct.new(id: 'v106'))
  end

  class FakeGateway
    attr_accessor :build_rows, :version_rows, :submission_rows, :item_rows, :on_builds, :on_versions, :on_cancel
    attr_reader :cancellations, :events, :build_reads, :version_reads
    def initialize
      @build_rows = [IosReviewSubmissionTest.build]
      live = OpenStruct.new(id: 'v105', version_string: '1.0.5', platform: 'IOS', app_version_state: 'READY_FOR_DISTRIBUTION', build: IosReviewSubmissionTest.build('b22', '22', '1.0.5'))
      @version_rows = [live, IosReviewSubmissionTest.version]
      @submission_rows = [IosReviewSubmissionTest.submission]
      @item_rows = [IosReviewSubmissionTest.item]
      @cancellations, @events, @build_reads, @version_reads = [], [], 0, 0
      @on_cancel = lambda do
        @version_rows.last.app_version_state = 'DEVELOPER_REJECTED'
        @submission_rows.first.state = 'COMPLETE'
      end
    end
    def builds(_number)
      @events << :build_read
      @build_reads += 1
      @on_builds&.call(self)
      @build_rows.map(&:dup)
    end
    def versions
      @events << :version_read
      @version_reads += 1
      @on_versions&.call(self)
      @version_rows.map(&:dup)
    end
    def submissions
      @submission_rows.map(&:dup)
    end
    def items(_id)
      @item_rows.map(&:dup)
    end
    def cancel(id)
      @events << :cancel
      @cancellations << id
      @on_cancel&.call
    end
  end

  def self.guard(gateway, **options)
    now = 0
    IosReviewSubmission::Guard.new(gateway: gateway, marketing_version: '1.0.6', build_number: '24',
      timeout: 3, interval: 1, clock: -> { now }, sleeper: ->(seconds) { now += seconds }, **options)
  end

  class Page
    attr_reader :next_url, :calls
    def initialize(rows, link = nil, following = nil)
      @rows, @next_url, @following, @calls = rows, link, following, 0
    end
    def to_models = @rows
    def next_page
      @calls += 1
      raise @following if @following.is_a?(Exception)
      @following
    end
  end

  class PagedClient
    attr_accessor :build_page, :version_page, :submission_page, :item_page
    attr_reader :patches
    def initialize
      @patches = []
    end
    def get_builds(**) = build_page
    def get_app_store_versions(**) = version_page
    def get_review_submissions(**) = submission_page
    def get_review_submission_items(**) = item_page
    def patch_review_submission(**args)
      @patches << args
    end
  end

  def self.run
    cases = {
      'valid replacement cancels only exact waiting submission and preserves live version' => lambda {
        gateway = FakeGateway.new
        live = gateway.version_rows.first.to_h
        assert(guard(gateway).prepare! { raise 'must not upload existing build' } == :ready)
        assert(gateway.cancellations == ['s106'])
        assert(gateway.version_rows.first.to_h == live)
        assert(gateway.build_reads >= 3 && gateway.version_reads >= 3)
      },
      'pre-existing processing build is awaited before any cancellation' => lambda {
        gateway = FakeGateway.new
        gateway.build_rows.first.processing_state = 'PROCESSING'
        gateway.on_builds = ->(g) { g.build_rows.first.processing_state = 'VALID' if g.build_reads >= 4 }
        assert(guard(gateway).prepare! { raise 'duplicate upload' } == :ready)
        assert(gateway.events.take_while { |event| event != :cancel }.count(:build_read) >= 5)
      },
      'upload failure preserves old review and original linked build' => lambda {
        gateway = FakeGateway.new
        gateway.build_rows = []
        begin
          guard(gateway).prepare! { raise 'upload failed' }
        rescue RuntimeError => error
          assert(error.message == 'upload failed')
        end
        assert(gateway.cancellations.empty? && gateway.version_rows.last.build.id == 'b23')
      },
      'successful upload is watched without selecting an unrelated build' => lambda {
        gateway = FakeGateway.new
        gateway.build_rows = [build('other', '24', '1.0.5'), build('tv', '24', '1.0.6', 'TV_OS')]
        uploads = 0
        result = guard(gateway).prepare! { uploads += 1; gateway.build_rows << build }
        assert(result == :ready && uploads == 1)
      },
      'invalid failed unknown expired and missing export compliance builds preserve review' => lambda {
        %w[INVALID FAILED UNKNOWN].each do |state|
          gateway = FakeGateway.new; gateway.build_rows.first.processing_state = state
          rejects(/invalid, failed, or.*unknown/) { guard(gateway).prepare! {} }
          assert(gateway.cancellations.empty? && gateway.version_rows.last.build.id == 'b23')
        end
        gateway = FakeGateway.new; gateway.build_rows.first.expired = true
        rejects(/expired/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway = FakeGateway.new; gateway.build_rows.first.uses_non_exempt_encryption = nil
        rejects(/export compliance/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway = FakeGateway.new; gateway.build_rows.first.uses_non_exempt_encryption = true
        rejects(/export compliance/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
      },
      'processing timeout is bounded and preserves waiting review' => lambda {
        gateway = FakeGateway.new; gateway.build_rows.first.processing_state = 'PROCESSING'
        rejects(/Timed out.*valid Apple build/) { guard(gateway).prepare! {} }
        assert(gateway.cancellations.empty? && gateway.build_reads == 5)
      },
      'ambiguous candidate build fails without upload or cancellation' => lambda {
        gateway = FakeGateway.new; gateway.build_rows << build('collision')
        rejects(/Multiple Apple builds/) { guard(gateway).prepare! { raise 'must not upload' } }
        assert(gateway.cancellations.empty?)
      },
      'in-review pending release and unknown states never cancel' => lambda {
        %w[IN_REVIEW PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE PROCESSING_FOR_DISTRIBUTION UNKNOWN].each do |state|
          gateway = FakeGateway.new; gateway.version_rows.last.app_version_state = state
          rejects(/automatic replacement stopped/) { guard(gateway).prepare! {} }
          assert(gateway.cancellations.empty?)
        end
      },
      'unknown review state and multi-submission collision preserve review' => lambda {
        gateway = FakeGateway.new; gateway.submission_rows.first.state = 'UNKNOWN'
        rejects(/Unknown Apple/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway = FakeGateway.new; gateway.submission_rows << submission.tap { |s| s.id = 'sOther' }
        rejects(/exactly one/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
      },
      'additional item mismatched version and nonwaiting item preserve review' => lambda {
        gateway = FakeGateway.new; gateway.item_rows << OpenStruct.new(id: 'event', app_event: OpenStruct.new(id: 'e1'))
        rejects(/other or unknown items/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway = FakeGateway.new; gateway.item_rows.first.app_store_version.id = 'other'
        rejects(/other or unknown items/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway = FakeGateway.new; gateway.item_rows.first.state = 'IN_REVIEW'
        rejects(/no longer waiting/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
      },
      'fresh state change to in-review stops before cancellation' => lambda {
        gateway = FakeGateway.new
        gateway.on_versions = ->(g) { g.version_rows.last.app_version_state = 'IN_REVIEW' if g.version_reads >= 2 }
        rejects(/IN_REVIEW/) { guard(gateway).prepare! {} }
        assert(gateway.cancellations.empty?)
      },
      'fresh linked build change stops before cancellation' => lambda {
        gateway = FakeGateway.new
        gateway.on_versions = ->(g) { g.version_rows.last.build = build('b25', '25') if g.version_reads >= 2 }
        rejects(/Previous Apple version changed/) { guard(gateway).prepare! {} }
        assert(gateway.cancellations.empty?)
      },
      'new build becoming invalid on final read preserves previous review' => lambda {
        gateway = FakeGateway.new
        gateway.on_builds = ->(g) { g.build_rows.first.processing_state = 'INVALID' if g.build_reads >= 3 }
        rejects(/invalid, failed/) { guard(gateway).prepare! {} }
        assert(gateway.cancellations.empty? && gateway.version_rows.last.build.id == 'b23')
      },
      'cancellation API failure is surfaced without retry or build reassignment' => lambda {
        gateway = FakeGateway.new
        gateway.on_cancel = -> { raise IosReviewSubmission::Failure, 'fixture cancellation rejected' }
        rejects(/fixture cancellation rejected/) { guard(gateway).prepare! {} }
        assert(gateway.cancellations == ['s106'] && gateway.version_rows.last.build.id == 'b23')
        assert(gateway.version_rows.last.app_version_state == 'WAITING_FOR_REVIEW')
      },
      'CANCELING does not count as editable and times out without further mutations' => lambda {
        gateway = FakeGateway.new
        gateway.on_cancel = -> { gateway.submission_rows.first.state = 'CANCELING' }
        rejects(/Timed out.*cancellation/) { guard(gateway).prepare! {} }
        assert(gateway.cancellations == ['s106'] && gateway.version_rows.last.build.id == 'b23')
      },
      'retry during cancellation waits for developer rejected and completion without cancelling again' => lambda {
        gateway = FakeGateway.new; gateway.submission_rows.first.state = 'CANCELING'
        gateway.on_versions = lambda do |g|
          if g.version_reads >= 3
            g.version_rows.last.app_version_state = 'DEVELOPER_REJECTED'
            g.submission_rows.first.state = 'COMPLETE'
          end
        end
        assert(guard(gateway).prepare! {} == :ready && gateway.cancellations.empty?)
      },
      'retry after completed cancellation proceeds without a second withdrawal' => lambda {
        gateway = FakeGateway.new
        gateway.version_rows.last.app_version_state = 'DEVELOPER_REJECTED'; gateway.submission_rows.first.state = 'COMPLETE'
        assert(guard(gateway).prepare! {} == :ready && gateway.cancellations.empty?)
      },
      'exact already submitted build is an idempotent no-op in review and after distribution' => lambda {
        %w[WAITING_FOR_REVIEW IN_REVIEW READY_FOR_DISTRIBUTION].each do |state|
          gateway = FakeGateway.new; gateway.version_rows[-1] = version(state, build)
          assert(guard(gateway).prepare! { raise 'must not upload' } == :already_submitted)
          assert(gateway.cancellations.empty?)
        end
        gateway = FakeGateway.new; gateway.version_rows[-1] = version('PENDING_DEVELOPER_RELEASE', build)
        rejects(/separate action/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
      },
      'distributed marketing version and downgrade never replace live build' => lambda {
        gateway = FakeGateway.new; gateway.version_rows.last.app_version_state = 'READY_FOR_DISTRIBUTION'
        rejects(/already distributed/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway = FakeGateway.new; gateway.version_rows.last.build = build('b25', '25')
        rejects(/must be newer/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
      },
      'new marketing version can replace older waiting version after its cancellation' => lambda {
        gateway = FakeGateway.new; gateway.build_rows = [build('b24', '24', '1.0.7')]
        assert(guard(gateway, marketing_version: '1.0.7').prepare! {} == :ready)
        assert(gateway.cancellations == ['s106'])
      },
      'populated draft is preserved while an empty draft is reusable' => lambda {
        gateway = FakeGateway.new; gateway.version_rows.last.app_version_state = 'DEVELOPER_REJECTED'
        gateway.submission_rows.first.state = 'READY_FOR_REVIEW'
        rejects(/active or populated/) { guard(gateway).prepare! {} }; assert(gateway.cancellations.empty?)
        gateway.item_rows = []
        assert(guard(gateway).prepare! {} == :ready)
      },
      'gateway follows all pages for builds versions submissions and review items' => lambda {
        client = PagedClient.new
        second = Page.new([OpenStruct.new(id: 'second')])
        first = Page.new([OpenStruct.new(id: 'first')], 'https://api.appstoreconnect.apple.com/v1/builds?cursor=2', second)
        client.build_page = client.version_page = client.submission_page = client.item_page = first
        gateway = IosReviewSubmission::Gateway.new(client: client, app_id: 'app')
        [gateway.builds('24'), gateway.versions, gateway.submissions, gateway.items('s')].each do |rows|
          assert(rows.map(&:id) == %w[first second])
        end
        assert(first.calls == 4 && client.patches.empty?)
      },
      'pagination collision loop unsafe URL and later-page error all abort' => lambda {
        client = PagedClient.new; gateway = IosReviewSubmission::Gateway.new(client: client, app_id: 'app')
        client.build_page = Page.new([OpenStruct.new(id: 'same')], 'https://api.appstoreconnect.apple.com/v1/builds?cursor=2', Page.new([OpenStruct.new(id: 'same')]))
        rejects(/duplicate IDs/) { gateway.builds('24') }
        looping = Page.new([], 'https://api.appstoreconnect.apple.com/v1/builds?cursor=2')
        looping.instance_variable_set(:@following, looping); client.build_page = looping
        rejects(/pagination loop/) { gateway.builds('24') }
        client.build_page = Page.new([], 'https://evil.example/v1/builds')
        rejects(/URL refused/) { gateway.builds('24') }
        client.item_page = Page.new([item], 'https://api.appstoreconnect.apple.com/v1/reviewSubmissions/s/items?cursor=2', IosReviewSubmission::Failure.new('fixture page failure'))
        rejects(/fixture page failure/) { gateway.items('s') }
        assert(client.patches.empty?)
      },
      'second-page review item prevents cancellation of the original waiting build' => lambda {
        client = PagedClient.new
        client.build_page = Page.new([build])
        old = version
        client.version_page = Page.new([old])
        client.submission_page = Page.new([submission])
        client.item_page = Page.new([item], 'https://api.appstoreconnect.apple.com/v1/reviewSubmissions/s106/items?cursor=2',
          Page.new([OpenStruct.new(id: 'event', app_event: OpenStruct.new(id: 'e1'))]))
        gateway = IosReviewSubmission::Gateway.new(client: client, app_id: 'app')
        rejects(/other or unknown items/) { guard(gateway).prepare! {} }
        assert(client.patches.empty? && old.build.id == 'b23' && old.app_version_state == 'WAITING_FOR_REVIEW')
      }
    }
    cases.each { |name, test| test.call; puts "PASS: #{name}" }
    puts "#{cases.length} iOS review checks passed (fixtures only)."
  end
end

IosReviewSubmissionTest.run if $PROGRAM_NAME == __FILE__
