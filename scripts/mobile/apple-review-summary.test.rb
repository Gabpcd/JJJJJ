#!/usr/bin/env ruby
# Stdlib-only synthetic fixtures. No provider, credential or encryption operation.
require_relative 'apple-review-summary'
require_relative 'apple-review-reference'
require 'tmpdir'
require 'open3'
require 'rbconfig'

module AppleReviewSummaryTest
  S = AppleReviewSummary
  CANARY = 'PRIVATE_NOTE_REFERENCE_TOKEN_CIPHERTEXT_0ccbefca'.freeze
  def self.assert(value)
    raise 'APPLE_SUMMARY_FIXTURE_FAILED' unless value
  end
  def self.fixture(status = 'review_required', reasons = %w[account_requirement_unknown notes_review_required])
    { 'schema' => 1, 'status' => status, 'appleComplete' => status == 'apple_complete',
      'confinementReady' => false, 'reasons' => reasons }
  end
  def self.render(value)
    S.render(JSON.generate(value))
  end
  def self.run
    cases = {
      'same closed code alphabet as the producer' => lambda {
        assert(S::CODES.sort == AppleReviewReference::CODES.sort)
      },
      'all three valid statuses preserve their actual qualification' => lambda {
        [['apple_complete', []], ['review_required', ['account_requirement_unknown']],
         ['unavailable', ['auth_unavailable']]].each do |status, reasons|
          output = render(fixture(status, reasons))
          assert(output != S::FALLBACK && output.include?("Statut : `#{status}`"))
          reasons.each { |reason| assert(output.include?("`#{reason}`")) }
        end
      },
      'every fixed producer reason is rendered without expansion' => lambda {
        S::CODES.each { |code| assert(render(fixture('unavailable', [code])).include?("`#{code}`")) }
      },
      'only status and reasons survive nested private fields' => lambda {
        value = fixture.merge('notes' => CANARY, 'references' => [CANARY], 'ciphertextSha256' => CANARY,
          'sourceSha' => CANARY, 'checkedAt' => CANARY, 'diagnostic' => { 'endpoint' => CANARY },
          'nested' => { 'anything' => [CANARY] })
        assert(render(value) == render(fixture))
        assert(!render(value).include?(CANARY))
      },
      'unknown status reasons and forged markdown fail closed' => lambda {
        [fixture.merge('status' => CANARY), fixture.merge('status' => "apple_complete\n#{CANARY}"),
         fixture('review_required', [CANARY]), fixture('review_required', ["notes_review_required`\n#{CANARY}"]),
         fixture('review_required', [{ 'notes' => CANARY }])].each do |value|
          assert(render(value) == S::FALLBACK && !render(value).include?(CANARY))
        end
      },
      'wrong shapes duplicates types and contradictory qualification fail closed' => lambda {
        invalid = [nil, [], {}, fixture.merge('schema' => 1.0), fixture.merge('schema' => '1'),
          fixture.merge('appleComplete' => true), fixture.merge('appleComplete' => nil),
          fixture.merge('confinementReady' => true), fixture.merge('confinementReady' => nil),
          fixture('apple_complete', ['notes_review_required']), fixture('review_required', []),
          fixture('unavailable', []), fixture.merge('reasons' => nil),
          fixture('review_required', ['notes_review_required'] * 2),
          fixture('unavailable', ['read_failed'] * (S::CODES.length + 1))]
        invalid.each { |value| assert(render(value) == S::FALLBACK) }
      },
      'malformed oversized and invalid UTF8 are never echoed' => lambda {
        [CANARY, '{' + CANARY, ' ' * (S::MAX_BYTES + 1), "{\xff}".b].each do |bytes|
          assert(S.render(bytes) == S::FALLBACK)
        end
      },
      'input boundary has exact byte limit' => lambda {
        raw = JSON.generate(fixture)
        assert(S.render(raw + ' ' * (S::MAX_BYTES - raw.bytesize)) == render(fixture))
        assert(S.render(raw + ' ' * (S::MAX_BYTES + 1 - raw.bytesize)) == S::FALLBACK)
      },
      'CLI is nonfailing and has empty stderr for refused missing and invalid receipts' => lambda {
        Dir.mktmpdir('apple-summary-synthetic-') do |dir|
          path = File.join(dir, CANARY)
          [JSON.generate(fixture), CANARY, 'x' * (S::MAX_BYTES + 1), nil].each do |bytes|
            bytes ? File.binwrite(path, bytes) : File.delete(path)
            out, err, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'apple-review-summary.rb'), path)
            assert(status.success? && err.empty? && !out.include?(CANARY))
            assert(out == (bytes == JSON.generate(fixture) ? render(fixture) : S::FALLBACK))
          end
        end
      },
      'symlink and directory inputs are never read' => lambda {
        Dir.mktmpdir('apple-summary-synthetic-') do |dir|
          path = File.join(dir, 'receipt.json')
          File.binwrite(path, JSON.generate(fixture))
          link = File.join(dir, 'link.json')
          File.symlink(path, link)
          assert(S.from_file(link) == S::FALLBACK && S.from_file(dir) == S::FALLBACK)
        end
      },
      'workflow keeps reader failure and always attaches the bounded projection' => lambda {
        path = File.expand_path('../../.github/workflows/mobile-store-status.yml', __dir__)
        flow = File.read(path)
        assert(flow.start_with?("name: Mobile store status (read only)\nrun-name: ${{ inputs.apple_canonical_reference && "))
        assert(flow.include?('bundle exec ruby scripts/mobile/apple-review-summary.test.rb'))
        summary = flow.split('      - name: Attach sanitized summary', 2).last.split('      - uses:', 2).first
        assert(summary.include?('if: always()') && summary.include?('apple-review-summary.rb'))
        assert(summary.include?('elif [ -f "$RUNNER_TEMP/mobile-store-status/store-status.md" ]; then'))
        assert(!flow.include?('continue-on-error') && !flow.include?('|| true'))
        assert(flow.include?('run: bundle exec ruby scripts/mobile/apple-review-reference.rb "$RUNNER_TEMP/apple-canonical-reference"'))
      }
    }
    cases.each_with_index { |(_, test), index| test.call; puts "PASS apple summary fixture #{index + 1}" }
    puts "#{cases.length} pure Apple summary checks passed; no provider operation."
  end
end
AppleReviewSummaryTest.run if $PROGRAM_NAME == __FILE__
