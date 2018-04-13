# frozen_string_literal: true

class SubmitSavedClaimJob
  include Sidekiq::Worker

  sidekiq_options retry: false

  class CentralMailResponseError < StandardError
  end

  def perform(saved_claim_id)
    PensionBurial::TagSentry.tag_sentry
    @claim = SavedClaim.find(saved_claim_id)
    @pdf_path = process_record(@claim)

    @attachment_paths = @claim.persistent_attachments.map do |record|
      process_record(record)
    end

    response = PensionBurial::Service.new.upload(create_request_body)
    File.delete(@pdf_path)
    @attachment_paths.each { |p| File.delete(p) }

    if response.success?
      update_submission('success')
    else
      raise CentralMailResponseError
    end
  rescue StandardError
    update_submission('failed')
    raise
  end

  def create_request_body
    body = {
      'metadata' => generate_metadata.to_json
    }

    body['document'] = to_faraday_upload(@pdf_path)
    @attachment_paths.each_with_index do |file_path, i|
      j = i + 1
      body["attachment#{j}"] = to_faraday_upload(file_path)
    end

    body
  end

  def update_submission(state)
    @claim.central_mail_submission.update_attributes!(state: state)
  end

  def to_faraday_upload(file_path)
    Faraday::UploadIO.new(
      file_path,
      Mime[:pdf].to_s
    )
  end

  def process_record(record)
    pdf_path = record.to_pdf
    stamped_path1 = PensionBurial::DatestampPdf.new(pdf_path).run(text: 'VETS.GOV', x: 5, y: 5)
    PensionBurial::DatestampPdf.new(stamped_path1).run(
      text: 'FDC Reviewed - Vets.gov Submission',
      x: 429,
      y: 770,
      text_only: true
    )
  end

  def get_hash_and_pages(file_path)
    {
      hash: Digest::SHA256.file(file_path).hexdigest,
      pages: PDF::Reader.new(file_path).pages.size
    }
  end

  # rubocop:disable Metrics/MethodLength
  def generate_metadata
    form = @claim.parsed_form
    form_pdf_metadata = get_hash_and_pages(@pdf_path)
    number_attachments = @attachment_paths.size
    veteran_full_name = form['veteranFullName']
    address = form['claimantAddress'] || form['veteranAddress']
    receive_date = @claim.created_at.in_time_zone('Central Time (US & Canada)')

    # TODO: make sure required field validations match for us and central mail
    metadata = {
      'veteranFirstName' => veteran_full_name.try(:[], 'first'),
      'veteranLastName' => veteran_full_name.try(:[], 'last'),
      'fileNumber' => form['vaFileNumber'] || form['veteranSocialSecurityNumber'],
      'receiveDt' => receive_date.strftime('%Y-%m-%d %H:%M:%S'),
      'zipCode' => address.try(:[], 'postalCode'),
      'uuid' => @claim.guid,
      'source' => 'Vets.gov',
      'hashV' => form_pdf_metadata[:hash],
      'numberAttachments' => number_attachments,
      'docType' => @claim.form_id,
      'numberPages' => form_pdf_metadata[:pages]
    }

    @attachment_paths.each_with_index do |file_path, i|
      j = i + 1
      attachment_pdf_metadata = get_hash_and_pages(file_path)
      metadata["ahash#{j}"] = attachment_pdf_metadata[:hash]
      metadata["numberPages#{j}"] = attachment_pdf_metadata[:pages]
    end

    metadata
  end
  # rubocop:enable Metrics/MethodLength
end
