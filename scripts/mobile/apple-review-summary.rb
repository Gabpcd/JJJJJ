#!/usr/bin/env ruby
# Pure public-receipt projection. No provider client, credentials or mutations.
require 'json'

module AppleReviewSummary
  MAX_BYTES = 65_536
  STATUSES = %w[apple_complete review_required unavailable].map(&:freeze).freeze
  CODES = %w[recipient_unconfigured recipient_invalid encryption_failed endpoint_refused
             read_failed http_refused response_invalid pagination_refused pagination_loop
             pagination_limit duplicate_resource resource_limit inventory_changed budget_exceeded
             notes_review_required attachments_review_required opaque_account_reference
             required_account_missing account_requirement_unknown reference_limit auth_unavailable output_failed source_refused].map(&:freeze).freeze
  FALLBACK = "## Références Apple — lecture seule\n\nStatut : `unavailable`\n\nMotifs : `summary_invalid_or_missing`\n".freeze

  def self.render(bytes)
    return FALLBACK unless bytes.is_a?(String) && bytes.bytesize <= MAX_BYTES
    value = JSON.parse(bytes)
    return FALLBACK unless value.is_a?(Hash) && value['schema'].is_a?(Integer) && value['schema'] == 1
    status = STATUSES.find { |candidate| candidate == value['status'] }
    reasons = value['reasons']
    return FALLBACK unless status && reasons.is_a?(Array) && reasons.length <= CODES.length &&
      reasons.all? { |reason| reason.is_a?(String) && CODES.include?(reason) } && reasons.uniq.length == reasons.length &&
      value['confinementReady'] == false && value['appleComplete'] == (status == 'apple_complete') &&
      (status == 'apple_complete' ? reasons.empty? : !reasons.empty?)
    # Only constants cross the output boundary, never input values or other fields.
    selected = CODES.select { |code| reasons.include?(code) }.sort
    detail = selected.empty? ? 'aucun' : selected.map { |code| "`#{code}`" }.join(', ')
    "## Références Apple — lecture seule\n\nStatut : `#{status}`\n\nMotifs : #{detail}\n"
  rescue StandardError
    FALLBACK
  end

  def self.from_file(path)
    info = File.lstat(path)
    return FALLBACK unless info.file? && info.size <= MAX_BYTES
    render(File.binread(path, MAX_BYTES + 1))
  rescue StandardError
    FALLBACK
  end
end

if $PROGRAM_NAME == __FILE__
  puts(ARGV.length == 1 ? AppleReviewSummary.from_file(ARGV[0]) : AppleReviewSummary::FALLBACK)
  # This display step does not reinterpret the earlier collector's exit status.
  exit 0
end
