# encoding: utf-8

module AMQP

  # Manages the encoding of credentials for the EXTERNAL authentication
  # mechanism.
  class AuthMechanismAdapter::External < AuthMechanismAdapter

    auth_mechanism "EXTERNAL"

    # Encodes a username and password for the EXTERNAL mechanism. Since
    # authentication is handled by an encapsulating protocol like SSL or
    # UNIX domain sockets, EXTERNAL doesn't pass along any username or
    # password information at all and this method always returns the
    # empty string.
    #
    # @param [String] username The username to encode. This parameter is
    #   ignored.
    # @param [String] password The password to encode. This parameter is
    #   ignored.
    # @return [String] The username and password, encoded for the
    #   EXTERNAL mechanism. This is always the empty string.
    def encode_credentials(username, password)
      ""
    end
  end
end
