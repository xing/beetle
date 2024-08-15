# encoding: utf-8

require "cgi"
require "uri"

module AMQ
  class URI
    # @private
    AMQP_DEFAULT_PORTS = {
      "amqp" => 5672,
      "amqps" => 5671
    }.freeze

    private_constant :AMQP_DEFAULT_PORTS

    DEFAULTS = {
      heartbeat: nil,
      connection_timeout: nil,
      channel_max: nil,
      auth_mechanism: [],
      verify: false,
      fail_if_no_peer_cert: false,
      cacertfile: nil,
      certfile: nil,
      keyfile: nil
    }.freeze

    def self.parse(connection_string)
      uri = ::URI.parse(connection_string)
      raise ArgumentError.new("Connection URI must use amqp or amqps schema (example: amqp://bus.megacorp.internal:5766), learn more at http://bit.ly/ks8MXK") unless %w{amqp amqps}.include?(uri.scheme)

      opts = DEFAULTS.dup

      opts[:scheme] = uri.scheme
      opts[:user]   = ::CGI::unescape(uri.user) if uri.user
      opts[:pass]   = ::CGI::unescape(uri.password) if uri.password
      opts[:host]   = uri.host if uri.host
      opts[:port]   = uri.port || AMQP_DEFAULT_PORTS[uri.scheme]
      opts[:ssl]    = uri.scheme.to_s.downcase =~ /amqps/i # TODO: rename to tls
      if uri.path =~ %r{^/(.*)}
        raise ArgumentError.new("#{uri} has multiple-segment path; please percent-encode any slashes in the vhost name (e.g. /production => %2Fproduction). Learn more at http://bit.ly/amqp-gem-and-connection-uris") if $1.index('/')
        opts[:vhost] = ::CGI::unescape($1)
      end

      if uri.query
        query_params = CGI::parse(uri.query)

        normalized_query_params = Hash[query_params.map { |param, value| [param, value.one? ? value.first : value] }]

        opts[:heartbeat] = normalized_query_params["heartbeat"].to_i
        opts[:connection_timeout] = normalized_query_params["connection_timeout"].to_i
        opts[:channel_max] = normalized_query_params["channel_max"].to_i
        opts[:auth_mechanism] = normalized_query_params["auth_mechanism"]

        %w(cacertfile certfile keyfile).each do |tls_option|
          if normalized_query_params[tls_option] && uri.scheme == "amqp"
            raise ArgumentError.new("The option '#{tls_option}' can only be used in URIs that use amqps schema")
          else
            opts[tls_option.to_sym] = normalized_query_params[tls_option]
          end
        end

        %w(verify fail_if_no_peer_cert).each do |tls_option|
          if normalized_query_params[tls_option] && uri.scheme == "amqp"
            raise ArgumentError.new("The option '#{tls_option}' can only be used in URIs that use amqps schema")
          else
            opts[tls_option.to_sym] = as_boolean(normalized_query_params[tls_option])
          end
        end
      end

      opts
    end

    def self.parse_amqp_url(s)
      parse(s)
    end

    #
    # Implementation
    #

    # Normalizes values returned by CGI.parse.
    # @private
    def self.as_boolean(val)
      case val
      when true    then true
      when false   then false
      when 1       then true
      when 0       then false
      when "true"  then true
      when "false" then false
      else
        !!val
      end
    end

    private_class_method :as_boolean
  end
end
