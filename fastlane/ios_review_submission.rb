# Keep App Review cancellation separate from deliver: deliver checks/changes the
# marketing version before reject_if_possible, and does not wait out CANCELING.
require 'uri'
require 'rubygems/version'

module IosReviewSubmission
  class Failure < StandardError; end

  # Use the current reviewSubmissions API and read every page, including items:
  # the items embedded in a submission response can be truncated.
  class Gateway
    def initialize(client:, app_id:)
      @client, @app_id = client, app_id
      raise Failure, 'Apple app is missing' if app_id.to_s.empty?
    end

    def builds(number)
      collect(@client.get_builds(filter: { app: @app_id, version: number }, includes: 'preReleaseVersion'))
    end

    def versions
      collect(@client.get_app_store_versions(app_id: @app_id, filter: { platform: 'IOS' }, includes: 'build'))
    end

    def submissions
      collect(@client.get_review_submissions(app_id: @app_id, filter: { platform: 'IOS' }, includes: 'appStoreVersionForReview'))
    end

    def items(id)
      collect(@client.get_review_submission_items(review_submission_id: id,
        includes: 'appStoreVersion,appStoreVersionExperiment,appCustomProductPageVersion,appEvent'))
    end

    def cancel(id)
      @client.patch_review_submission(review_submission_id: id, attributes: { canceled: true })
    end

    private

    def collect(page)
      rows, seen = [], []
      loop do
        raise Failure, 'Apple collection is missing' unless page
        rows.concat(page.to_models)
        link = page.next_url
        break if link.nil?
        uri = URI.parse(link)
        unless uri.scheme == 'https' && uri.host == 'api.appstoreconnect.apple.com' &&
            uri.userinfo.nil? && uri.port == 443 && uri.path.start_with?('/v1/')
          raise Failure, 'Apple pagination URL refused'
        end
        raise Failure, 'Apple pagination loop or page limit reached' if seen.include?(link) || seen.length >= 100
        seen << link
        page = page.next_page
      end
      ids = rows.map(&:id)
      raise Failure, 'Apple collection contains missing or duplicate IDs' if ids.any? { |id| id.to_s.empty? } || ids.uniq.length != ids.length
      rows
    rescue URI::InvalidURIError
      raise Failure, 'Apple pagination URL refused'
    end
  end

  class Guard
    EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
    SUBMITTED = %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE WAITING_FOR_EXPORT_COMPLIANCE PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION].freeze
    HISTORICAL = %w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].freeze
    KNOWN_VERSIONS = (EDITABLE + SUBMITTED + %w[READY_FOR_REVIEW ACCEPTED] + HISTORICAL).uniq.freeze
    KNOWN_SUBMISSIONS = %w[WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES READY_FOR_REVIEW CANCELING COMPLETE].freeze

    def initialize(gateway:, marketing_version:, build_number:, timeout: 1800, interval: 15,
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
      @gateway, @marketing, @number = gateway, marketing_version.to_s, build_number.to_s
      @timeout, @interval, @clock, @sleeper = timeout, interval, clock, sleeper
      unless @marketing.match?(/\A\d+(?:\.\d+){0,2}\z/) && @number.match?(/\A\d+\z/) && timeout.positive? && interval.positive?
        raise Failure, 'Invalid iOS release configuration'
      end
    end

    # The upload block runs only when the exact build is absent. Processing is
    # checked on every run, including a retry that finds an already uploaded IPA.
    def prepare!
      yield if find_build.nil?
      @build = wait_for('valid Apple build') { valid_build }
      versions, submissions = snapshot
      return :already_submitted if already_submitted?(versions)
      version = replacement_version(versions)
      if submissions.one? && submissions.first.state == 'CANCELING'
        exact_submission!(submissions.first, version)
        wait_for_cancellation(version, submissions.first.id)
      elsif version && state(version) == 'WAITING_FOR_REVIEW'
        submission = waiting_submission!(version, submissions)
        # Re-read all guards immediately before the only destructive operation.
        candidate = valid_build
        raise Failure, 'New Apple build changed before cancellation' unless candidate && candidate.id == @build.id
        fresh_versions, fresh_submissions = snapshot
        fresh_version = replacement_version(fresh_versions)
        unless same_version?(version, fresh_version)
          raise Failure, 'Previous Apple version changed; review was preserved'
        end
        fresh_submission = waiting_submission!(fresh_version, fresh_submissions)
        raise Failure, 'Apple submission changed; review was preserved' unless fresh_submission.id == submission.id
        @gateway.cancel(submission.id)
        wait_for_cancellation(version, submission.id)
      else
        require_editable!(version)
        require_no_active_submission!(submissions)
      end
      :ready
    end

    private

    def find_build
      builds = @gateway.builds(@number)
      matches = builds.select do |build|
        raise Failure, 'Apple build is missing its pre-release version' unless build.pre_release_version
        build.version == @number && build.app_version == @marketing && build.platform == 'IOS'
      end
      raise Failure, 'Multiple Apple builds match this release' if matches.length > 1
      matches.first
    end

    def valid_build
      build = find_build
      return nil unless build
      case build.processing_state
      when 'PROCESSING' then return nil
      when 'VALID'
        raise Failure, 'Apple build is expired or expiration is unknown' unless build.expired == false
        # Jolene declares no non-exempt encryption. A true/unknown value needs
        # a separate export-compliance workflow before cancelling existing review.
        unless build.uses_non_exempt_encryption == false
          raise Failure, 'Apple export compliance requires separate verification before replacing review'
        end
        build
      else
        raise Failure, 'Apple build is invalid, failed, or has an unknown processing state; review was preserved'
      end
    end

    def state(version)
      version.app_version_state
    end

    def snapshot
      versions = @gateway.versions
      submissions = @gateway.submissions
      unless versions.all? { |v| v.platform == 'IOS' && KNOWN_VERSIONS.include?(state(v)) } &&
          submissions.all? { |s| s.platform == 'IOS' && KNOWN_SUBMISSIONS.include?(s.state) }
        raise Failure, 'Unknown Apple version or review state; automatic replacement stopped'
      end
      if versions.map(&:version_string).uniq.length != versions.length
        raise Failure, 'Multiple Apple versions share a marketing version'
      end
      [versions, submissions.reject { |s| s.state == 'COMPLETE' }]
    end

    def already_submitted?(versions)
      exact = versions.find { |v| v.version_string == @marketing && v.build&.id == @build.id }
      if exact && state(exact) == 'PENDING_DEVELOPER_RELEASE'
        raise Failure, 'Apple version is PENDING_DEVELOPER_RELEASE; automatic release needs separate action and review was preserved'
      end
      versions.any? { |v| v.version_string == @marketing && v.build&.id == @build.id && SUBMITTED.include?(state(v)) }
    end

    def replacement_version(versions)
      versions.each do |version|
        next unless HISTORICAL.include?(state(version))
        if Gem::Version.new(@marketing) <= Gem::Version.new(version.version_string)
          raise Failure, 'Marketing version is already distributed or superseded; create a newer version'
        end
      end
      candidates = versions.reject { |v| HISTORICAL.include?(state(v)) }
      raise Failure, 'Multiple active Apple versions; automatic replacement stopped' if candidates.length > 1
      version = candidates.first
      if version && !EDITABLE.include?(state(version)) && state(version) != 'WAITING_FOR_REVIEW'
        raise Failure, "Apple version is #{state(version)}; automatic replacement stopped and review preserved"
      end
      if version && Gem::Version.new(@marketing) < Gem::Version.new(version.version_string)
        raise Failure, 'Refusing to replace a newer Apple marketing version'
      end
      version
    end

    def waiting_submission!(version, submissions)
      unless submissions.one? && submissions.first.state == 'WAITING_FOR_REVIEW'
        raise Failure, 'Expected exactly one waiting Apple submission; review was preserved'
      end
      raise Failure, 'Previous Apple build is missing; review was preserved' unless version.build&.id
      unless version.build.version.to_s.match?(/\A\d+\z/)
        raise Failure, 'Previous Apple build number is unknown; review was preserved'
      end
      if version.version_string == @marketing && version.build.version.to_i >= @number.to_i
        raise Failure, 'Replacement Apple build must be newer than the waiting build'
      end
      exact_submission!(submissions.first, version)
      submissions.first
    end

    def exact_submission!(submission, version)
      unless version && submission.app_store_version_for_review&.id == version.id
        raise Failure, 'Apple submission does not match the exact version; review was preserved'
      end
      items = @gateway.items(submission.id)
      item = items.first
      unless items.one? && item.app_store_version&.id == version.id &&
          item.app_store_version_experiment.nil? && item.app_store_product_page_version.nil? && item.app_event.nil?
        raise Failure, 'Apple submission contains other or unknown items; review was preserved'
      end
      if submission.state == 'WAITING_FOR_REVIEW' && item.state != 'WAITING_FOR_REVIEW'
        raise Failure, 'Apple review item is no longer waiting; review was preserved'
      end
    end

    def same_version?(before, after)
      after && [before.id, before.version_string, state(before), before.build&.id] ==
        [after.id, after.version_string, state(after), after.build&.id]
    end

    def require_editable!(version)
      return if version.nil? || EDITABLE.include?(state(version))
      raise Failure, 'Apple version is not editable; automatic submission stopped'
    end

    def require_no_active_submission!(submissions)
      # deliver can reuse an empty draft, but must never overwrite a populated one.
      return if submissions.empty?
      if submissions.one? && submissions.first.state == 'READY_FOR_REVIEW' && @gateway.items(submissions.first.id).empty?
        return
      end
      raise Failure, 'Apple has an active or populated submission; automatic submission stopped'
    end

    def wait_for_cancellation(previous, submission_id)
      wait_for('Apple review cancellation') do
        versions, submissions = snapshot
        version = versions.find { |v| v.id == previous.id }
        unless version && version.version_string == previous.version_string &&
            (version.build.nil? || version.build.id == previous.build&.id)
          raise Failure, 'Apple version changed during cancellation; automatic submission stopped'
        end
        unless %w[WAITING_FOR_REVIEW DEVELOPER_REJECTED].include?(state(version))
          raise Failure, 'Apple version left the expected cancellation states; automatic submission stopped'
        end
        if submissions.any? { |s| s.id != submission_id || !%w[WAITING_FOR_REVIEW CANCELING].include?(s.state) }
          raise Failure, 'Apple review changed during cancellation; automatic submission stopped'
        end
        state(version) == 'DEVELOPER_REJECTED' && submissions.empty?
      end
    end

    def wait_for(description)
      deadline = @clock.call + @timeout
      loop do
        result = yield
        return result if result
        remaining = deadline - @clock.call
        raise Failure, "Timed out waiting for #{description}; no further Apple changes were made" unless remaining.positive?
        @sleeper.call([@interval, remaining].min)
      end
    end
  end
end
