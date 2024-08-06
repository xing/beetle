# frozen_string_literal: true

require 'amq/settings'

module Beetle
  # A connection string is a normalized AMQP URI that can be used to connect to an AMQP server.
  # It provides access to the individual components of the URI (host, port, vhost, user, pass, ssl).
  # It's a value object that bases its equality and hash on the URI string.
  class ConnectionString
    include Comparable
    attr_reader :settings

    def initialize(connection_string)
      case connection_string
      when ConnectionString
        @settings = connection_string.settings.dup
      else
        @settings = connection_string.to_s.start_with?("amqp://", "amqps://") ?
                      AMQ::Settings.configure(connection_string.to_s) :
                      AMQ::Settings.configure("amqp://#{connection_string}")
      end

      raise ArgumentError, "invalid connection string: #{connection_string.inspect}" if @settings.nil?

      settings.freeze

      @amqp_uri = "#{scheme}://#{user}:#{pass}@#{host}:#{port}#{vhost}"
    end

    delegate :to_str, :<=>, :==, :hash, to: :@amqp_uri

    def to_s(with_credentials: false)
      with_credentials ? @amqp_uri : amqp_uri_without_credentials
    end

    def host
      @settings[:host]
    end

    def port
      @settings[:port]
    end

    def vhost
      @settings[:vhost]
    end

    def ssl
      @settings[:ssl]
    end

    def user
      @settings[:user]
    end

    def pass
      @settings[:pass]
    end

    def scheme
      @settings[:ssl].present? ? "amqps" : "amqp"
    end

    def legacy_servername
      "#{host}:#{port}"
    end

    def eql?(other)
      self == other
    end

    private

    def amqp_uri_without_credentials
      "#{scheme}://#{user}:****@#{host}:#{port}#{vhost}"
    end
  end
end
