# frozen_string_literal: true

require 'saml/auth_fail_handler'
require 'sentry_logging'

class SSOService
  include SentryLogging
  include ActiveModel::Validations
  attr_reader :auth_error_code
  DEFAULT_ERROR_MESSAGE = 'Default generic identity provider error'
  AUTH_ERRORS = { 'Subject did not consent to attribute release' => '001',
                  'Current time is on or after NotOnOrAfter condition' => '002',
                  'Current time is earlier than NotBefore condition' => '003',
                  # 004, 005 and 006 are user persistence errors
                  DEFAULT_ERROR_MESSAGE => '007' }.freeze

  def initialize(response)
    raise 'SAML Response is not a OneLogin::RubySaml::Response' unless response.is_a?(OneLogin::RubySaml::Response)
    @saml_response = response

    if saml_response.is_valid?(true)
      @saml_attributes = SAML::User.new(@saml_response)
      @existing_user = User.find(saml_attributes.user_attributes.uuid)
      @new_user_identity = UserIdentity.new(saml_attributes.to_hash)
      @new_user = init_new_user(new_user_identity, existing_user, saml_attributes.changing_multifactor?)
      @new_session = Session.new(uuid: new_user.uuid)
    end
  end

  attr_reader :new_session, :new_user, :new_user_identity, :saml_attributes, :saml_response, :existing_user,
              :failure_instrumentation_tag

  validate :composite_validations

  def persist_authentication!
    if new_login?
      # FIXME: possibly revisit this. Is there a possibility that different sign-in contexts could get
      # merged? MHV LOA1 -> IDME LOA3 is ok, DS Logon LOA1 -> IDME LOA3 is ok, everything else is not.
      # because user, session, user_identity all have the same TTL, this is probably not a problem.
      mergable_identity_attributes.each do |attribute|
        new_user_identity.send(attribute + '=', existing_user.identity.send(attribute))
      end
      existing_user.destroy
    end

    if valid?
      new_session.save && new_user.save && new_user_identity.save
    else
      handle_error_reporting_and_instrumentation
    end
  end

  def mergable_identity_attributes
    # We don't want to persist the mhv_account_type because then we would have to change it when we
    # upgrade the account to 'Premium' and we want to keep UserIdentity pristine, based on the current
    # signed in session.
    # TODO: Do we want to pull in DS Logon attributes here as well??
    %w[mhv_correlation_id mhv_icn dslogon_edipi]
  end

  def new_login?
    existing_user.present?
  end

  def real_authn_context
    REXML::XPath.first(saml_response.decrypted_document, '//saml:AuthnContextClassRef')&.text
  end

  private

  def init_new_user(user_identity, existing_user = nil, multifactor_change = false)
    new_user = User.new(user_identity.attributes)
    if multifactor_change
      new_user.mhv_last_signed_in = existing_user.last_signed_in
      new_user.last_signed_in = existing_user.last_signed_in
    else
      new_user.last_signed_in = Time.current.utc
    end
    new_user
  end

  def composite_validations
    if saml_response.is_valid?
      errors.add(:new_session, :invalid) unless new_session.valid?
      errors.add(:new_user, :invalid) unless new_user.valid?
      errors.add(:new_user_identity, :invalid) unless new_user_identity.valid?
    else
      saml_response.errors.each do |error|
        errors.add(:base, error)
      end
    end
  end

  def handle_error_reporting_and_instrumentation
    if errors.keys.include?(:base)
      invalid_saml_response_handler
    else
      invalid_persistence_handler
    end
  end

  def invalid_persistence_handler
    return if new_session.valid? && new_user.valid? && new_user_identity.valid?
    @failure_instrumentation_tag = 'error:validations_failed'
    log_message_to_sentry('Login Fail! on User/Session Validation', :error, error_context)
  end

  # TODO: Eventually some of this needs to just be instrumentation and not a custom sentry error
  def invalid_saml_response_handler
    return if saml_response.is_valid?
    fail_handler = SAML::AuthFailHandler.new(saml_response)
    @auth_error_code = AUTH_ERRORS[DEFAULT_ERROR_MESSAGE]
    if fail_handler.errors?
      @auth_error_code = AUTH_ERRORS[fail_handler.context[:saml_response][:status_message]]
      @failure_instrumentation_tag = "error:#{fail_handler.error}"
      log_message_to_sentry(fail_handler.message, fail_handler.level, fail_handler.context)
    else
      @failure_instrumentation_tag = 'error:unknown'
      log_message_to_sentry('Unknown SAML Login Error', :error, error_context)
    end
  end

  def error_context
    {
      uuid: new_user.uuid,
      user:   {
        valid: new_user&.valid?,
        errors: new_user&.errors&.full_messages
      },
      session:   {
        valid: new_session&.valid?,
        errors: new_session&.errors&.full_messages
      }
    }
  end
end
