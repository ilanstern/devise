require 'devise/strategies/database_authenticatable'
require 'bcrypt'

module Devise
  # Digests the password using bcrypt.
  def self.bcrypt(klass, password)
    ::BCrypt::Password.create("#{password}#{klass.pepper}", cost: klass.stretches).to_s
  end

  module Models
    # Authenticatable Module, responsible for encrypting password and validating
    # authenticity of a user while signing in.
    #
    # == Options
    #
    # DatabaseAuthenticable adds the following options to devise_for:
    #
    #   * +pepper+: a random string used to provide a more secure hash. Use
    #     `rake secret` to generate new keys.
    #
    #   * +stretches+: the cost given to bcrypt.
    #
    # == Examples
    #
    #    User.find(1).valid_password?('password123')         # returns true/false
    #
    module DatabaseAuthenticatable
      extend ActiveSupport::Concern

      included do
        attr_reader :password, :current_password
        attr_accessor :password_confirmation
      end

      def self.required_fields(klass)
        [:encrypted_password] + klass.authentication_keys
      end

      # Generates password encryption based on the given value.
      def password=(new_password)
        @password = new_password
        self.encrypted_password = password_digest(@password) if @password.present?
      end

      # Verifies whether an password (ie from sign in) is the user password.
      def valid_password?(password)
        return false if encrypted_password.blank? 
        bcrypt   = ::BCrypt::Password.new(encrypted_password)
        password = ::BCrypt::Engine.hash_secret("#{password}#{self.class.pepper}", bcrypt.salt)
        Devise.secure_compare(password, encrypted_password)
      end

      # Set password and password confirmation to nil
      def clean_up_passwords
        self.password = self.password_confirmation = nil
      end

      # Update record attributes when :current_password matches, otherwise
      # returns error on :current_password.
      #
      # This method also rejects the password field if it is blank (allowing
      # users to change relevant information like the e-mail without changing
      # their password). In case the password field is rejected, the confirmation
      # is also rejected as long as it is also blank.
      def update_with_password(params, *options)
        current_password      = params.delete(:current_password)
        password_confirmation = params.delete(:password_confirmation)

        password              = params[:password]
        

        result = if !current_password.blank? and !password.blank? and !password_confirmation.blank? and is_password_new?(password) and valid_password?(current_password) and is_long_password?(password) and is_secure_password?(password) and password == password_confirmation
          update_attributes(params, *options)
        else
          self.assign_attributes(params, *options)
          self.valid?
          
          if current_password.blank?
            self.errors.add(:current_password, :blank)
          elsif !valid_password?(current_password)
            self.errors.add(:current_password, :invalid)
          else
            if password.blank?
              self.errors.add(:password, :blank)
            elsif !is_password_new?(password)
              errors.add(:password, "New password must be different from old one")
            else
              if !is_secure_password?(password)
                errors.add(:password, "Password must contain at least 1 lower case character, 1 upper case character and a number")
              end
              if !is_long_password?(password)
                errors.add(:password, "Password must be at least 10 characters long")
              end
            end
            if !password.blank? and password != password_confirmation
              self.errors.add(:password_confirmation, :invalid)
            end
          end

          false
        end
        clean_up_passwords
        result
      end

      def is_secure_password?(password)
        if password and !(/(?=.*\d)(?=.*[a-z])(?=.*[A-Z])/.match(password))
          return false
        end
        true
      end

      def is_long_password?(password)
        if password and password.length < 10
          return false
        end    
        true
      end

      def is_password_new?(password)
        !valid_password?(password)
      end

      # Updates record attributes without asking for the current password.
      # Never allows a change to the current password. If you are using this
      # method, you should probably override this method to protect other
      # attributes you would not like to be updated without a password.
      #
      # Example:
      #
      #   def update_without_password(params, *options)
      #     params.delete(:email)
      #     super(params)
      #   end
      #
      def update_without_password(params, *options)
        params.delete(:password)
        params.delete(:password_confirmation)

        result = update_attributes(params, *options)
        clean_up_passwords
        result
      end

      # Destroy record when :current_password matches, otherwise returns
      # error on :current_password. It also automatically rejects
      # :current_password if it is blank.
      def destroy_with_password(current_password)
        result = if valid_password?(current_password)
          destroy
        else
          self.valid?
          self.errors.add(:current_password, current_password.blank? ? :blank : :invalid)
          false
        end

        result
      end

      # A callback initiated after successfully authenticating. This can be
      # used to insert your own logic that is only run after the user successfully
      # authenticates.
      #
      # Example:
      #
      #   def after_database_authentication
      #     self.update_attribute(:invite_code, nil)
      #   end
      #
      def after_database_authentication
      end

      # A reliable way to expose the salt regardless of the implementation.
      def authenticatable_salt
        encrypted_password[0,29] if encrypted_password
      end

    protected

      # Digests the password using bcrypt. Custom encryption should override
      # this method to apply their own algorithm.
      #
      # See https://github.com/plataformatec/devise-encryptable for examples
      # of other encryption engines.
      def password_digest(password)
        Devise.bcrypt(self.class, password)
      end

      module ClassMethods
        Devise::Models.config(self, :pepper, :stretches)

        # We assume this method already gets the sanitized values from the
        # DatabaseAuthenticatable strategy. If you are using this method on
        # your own, be sure to sanitize the conditions hash to only include
        # the proper fields.
        def find_for_database_authentication(conditions)
          find_for_authentication(conditions)
        end
      end
    end
  end
end
