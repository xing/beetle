require 'websocket-eventmachine-base'
require 'uri'

module WebSocket
  module EventMachine

    # WebSocket Client (using EventMachine)
    # @example
    #   ws = WebSocket::EventMachine::Client.connect(:host => "0.0.0.0", :port => 8080)
    #   ws.onmessage { |msg| ws.send "Pong: #{msg}" }
    #   ws.send "data"
    class Client < Base

      ###########
      ### API ###
      ###########

      # Connect to websocket server
      # @param args [Hash] The request arguments
      # @option args [String] :host The host IP/DNS name
      # @option args [Integer] :port The port to connect too(default = 80)
      # @option args [String] :uri Full URI for server(optional - use instead of host/port combination)
      # @option args [Integer] :version Version of protocol to use(default = 13)
      # @option args [Hash] :headers HTTP headers to use in the handshake
      # @option args [Boolean] :ssl Force SSL/TLS connection
      # @option args [Hash] :tls TLS options hash to be passed to EM start_tls
      def self.connect(args = {})
        host = nil
        port = nil
        if args[:uri]
          uri = URI.parse(args[:uri])
          host = uri.host
          port = uri.port
          args[:ssl] = true if uri.scheme == 'wss'
        end
        host = args[:host] if args[:host]
        port = args[:port] if args[:port]
        if args[:ssl]
          args[:tls] ||= {}
          args[:tls][:sni_hostname] ||= host
          port ||= 443
        else
          port ||= 80
        end

        ::EventMachine.connect host, port, self, args
      end
      
      # Make a websocket connection to a UNIX-domain socket.
      # @param socketname [String] Unix domain socket (local fully-qualified path)
      # @param args [Hash] Arguments for connection
      # @option args [Integer] :version Version of protocol to use(default = 13)
      # @option args [Hash] :headers HTTP headers to use in the handshake
      def self.connect_unix_domain(socketname, args = {})
        fail ArgumentError, 'invalid socket' unless File.socket?(socketname)
        args[:host] ||= 'localhost'
        ::EventMachine.connect_unix_domain socketname, self, args
      end

      # Initialize connection
      # @param args [Hash] Arguments for connection
      # @option args [String] :host The host IP/DNS name
      # @option args [Integer] :port The port to connect too(default = 80)
      # @option args [Integer] :version Version of protocol to use(default = 13)
      # @option args [Hash] :headers HTTP headers to use in the handshake
      # @option args [Boolean] :ssl Force SSL/TLS connection
      def initialize(args)
        @args = args
      end

      ############################
      ### EventMachine methods ###
      ############################

      # Called after initialize of connection, but before connecting to server
      # Eventmachine internal
      # @private
      def post_init
        @state = :connecting
        @handshake = ::WebSocket::Handshake::Client.new(@args)
      end

      # Called by EventMachine after connecting.
      # Sends handshake to server or starts SSL/TLS
      # Eventmachine internal
      # @private
      def connection_completed
        if @args[:ssl]
          start_tls @args[:tls]
        else
          send(@handshake.to_s, :type => :plain)
        end
      end

      # Called by EventMachine after SSL/TLS handshake.
      # Sends websocket handshake
      # Eventmachine internal
      # @private
      def ssl_handshake_completed
        send(@handshake.to_s, :type => :plain)
      end

      private

      def incoming_frame
        ::WebSocket::Frame::Incoming::Client
      end

      def outgoing_frame
        ::WebSocket::Frame::Outgoing::Client
      end

      public

      #########################
      ### Inherited methods ###
      #########################

      # Called when connection is opened.
      # No parameters are passed to block
      def onopen(&blk); super; end

      # Called when connection is closed.
      # No parameters are passed to block
      def onclose(&blk); super; end

      # Called when error occurs.
      # One parameter passed to block:
      #   error - string with error message
      def onerror(&blk); super; end

      # Called when message is received.
      # Two parameters passed to block:
      #   message - string with received message
      #   type - type of message. Valid values are :text and :binary
      def onmessage(&blk); super; end

      # Called when ping message is received
      # One parameter passed to block:
      #   message - string with ping message
      def onping(&blk); super; end

      # Called when pong message is received
      # One parameter passed to block:
      #   message - string with pong message
      def onpong(&blk); super; end

      # Send data
      # @param data [String] Data to send
      # @param args [Hash] Arguments for send
      # @option args [String] :type Type of frame to send - available types are "text", "binary", "ping", "pong" and "close"
      # @option args [Integer] :code Code for close frame
      # @return [Boolean] true if data was send, otherwise call on_error if needed
      def send(data, args = {}); super; end

      # Close connection
      # @return [Boolean] true if connection is closed immediately, false if waiting for other side to close connection
      def close(code = 1000, data = nil); super; end

      # Send ping message
      # @return [Boolean] false if protocol version is not supporting ping requests
      def ping(data = ''); super; end

      # Send pong message
      # @return [Boolean] false if protocol version is not supporting pong requests
      def pong(data = ''); super; end

    end
  end
end
