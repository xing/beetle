# encoding: utf-8

require "amq/protocol/client"
require "amq/uri"

module AMQ
    module Settings

      # @private
      AMQPS = "amqps".freeze

      # Default connection settings used by AMQ clients
      #
      # @see AMQ::Client::Settings.configure
      def self.default
        @default ||= {
          # TCP/IP connection parameters
          host: "127.0.0.1",
          port: AMQ::Protocol::DEFAULT_PORT,
          auth_mechanism: [],

          # authentication parameters
          user: "guest",
          pass: "guest",
          vhost: "/",

          # client connection parameters
          frame_max: (128 * 1024),
          heartbeat: nil,
          connection_timeout: nil,
          channel_max: nil,

          # ssl parameters
          ssl: false,
          verify: false,
          fail_if_no_peer_cert: false,
          cacertfile: nil,
          certfile: nil,
          keyfile: nil
        }
      end

      # Merges given configuration parameters with defaults and returns
      # the result.
      #
      # @param [Hash] Configuration parameters to use.
      #
      # @option settings [String] :host ("127.0.0.1") Hostname AMQ broker runs on.
      # @option settings [String] :port (5672) Port AMQ broker listens on.
      # @option settings [String] :vhost ("/") Virtual host to use.
      # @option settings [String] :user ("guest") Username to use for authentication.
      # @option settings [String] :pass ("guest") Password to use for authentication.
      # @option settings [String] :ssl (false) Should be use TLS (SSL) for connection?
      # @option settings [Fixnum] :frame_max (131072) Maximum frame size to use. If broker cannot support frames this large, broker's maximum value will be used instead.
      # @option settings [Integer] :heartbeat (nil) Heartbeat timeout value in seconds to negotiate with the server.
      # @option settings [Integer] :connection_timeout (nil) Time in milliseconds to wait while establishing a TCP connection to the server before giving up.
      # @option settings [Fixnum] :channel_max (nil) Maximum number of channels to permit on this connection.
      # @option settings [Array] :auth_mechanism ([]) SASL authentication mechanisms to consider when negotiating a mechanism with the server. This parameter can be specified multiple times to specify multiple mechanisms, e.g. `?auth_mechanism=plain&auth_mechanism=amqplain`.
      # @option settings [Boolean] :verify (false) Controls peer verification mode.
      # @option settings [Boolean] :fail_if_no_peer_cert (false) When set to true, TLS connection will be rejected if client fails to provide a certificate.
      # @option settings [String] :cacertfile (nil) Certificate Authority (CA) certificate file path.
      # @option settings [String] :certfile (nil) Server certificate file path.
      # @option settings [String] :keyfile (nil) Server private key file path.
      #
      # @option settings [String] :broker (nil) Broker name (use if you intend to use broker-specific features).
      #
      # @return [Hash] Merged configuration parameters.
      def self.configure(settings = nil)
        case settings
        when Hash then
          if username = (settings.delete(:username) || settings.delete(:user))
            settings[:user] ||= username
          end

          if password = (settings.delete(:password) || settings.delete(:pass))
            settings[:pass] ||= password
          end


          self.default.merge(settings)
        when String then
          settings = self.parse_amqp_url(settings)
          self.default.merge(settings)
        when NilClass then
          self.default
        end
      end

      # Parses AMQP connection URI and returns its components as a hash.
      #
      # h2. vhost naming schemes
      #
      # It is convenient to be able to specify the AMQP connection
      # parameters as a URI string, and various "amqp" URI schemes
      # exist.  Unfortunately, there is no standard for these URIs, so
      # while the schemes share the basic idea, they differ in some
      # details.  This implementation aims to encourage URIs that work
      # as widely as possible.
      #
      # The URI scheme should be "amqp", or "amqps" if SSL is required.
      #
      # The host, port, username and password are represented in the
      # authority component of the URI in the same way as in http URIs.
      #
      # The vhost is obtained from the first segment of the path, with the
      # leading slash removed.  The path should contain only a single
      # segment (i.e, the only slash in it should be the leading one).
      # If the vhost is to include slashes or other reserved URI
      # characters, these should be percent-escaped.
      #
      # @example How vhost is parsed
      #
      #   AMQ::Settings.parse_amqp_url("amqp://dev.rabbitmq.com")            # => vhost is nil, so default (/) will be used
      #   AMQ::Settings.parse_amqp_url("amqp://dev.rabbitmq.com/")           # => vhost is an empty string
      #   AMQ::Settings.parse_amqp_url("amqp://dev.rabbitmq.com/%2Fvault")   # => vhost is /vault
      #   AMQ::Settings.parse_amqp_url("amqp://dev.rabbitmq.com/production") # => vhost is production
      #   AMQ::Settings.parse_amqp_url("amqp://dev.rabbitmq.com/a.b.c")      # => vhost is a.b.c
      #   AMQ::Settings.parse_amqp_url("amqp://dev.rabbitmq.com/foo/bar")    # => ArgumentError
      #
      #
      # @param [String] connection_string AMQP connection URI, à la JDBC connection string. For example: amqp://bus.megacorp.internal:5877.
      # @return [Hash] Connection parameters (:username, :password, :vhost, :host, :port, :ssl)
      #
      # @raise [ArgumentError] When connection URI schema is not amqp or amqps, or the path contains multiple segments
      #
      # @api public
      def self.parse_amqp_url(connection_string)
        AMQ::URI.parse(connection_string)
      end
    end
end
