# frozen_string_literal: true
class EVSSClaim::DocumentUpload
  include Sidekiq::Worker

  def perform(auth_headers, user_uuid, document_hash)
    document = EVSSClaimDocument.new document_hash
    client = EVSS::DocumentsService.new(auth_headers)
    uploader = EVSSClaimDocumentUploader.new(user_uuid, document.tracked_item_id)
    uploader.retrieve_from_store!(document.file_name)
    file_body = uploader.read
    client.upload(file_body, document)
    Rails.logger.info("File uploaded to EVSS: #{document_hash.inspect}")
    uploader.remove!
  end
end
