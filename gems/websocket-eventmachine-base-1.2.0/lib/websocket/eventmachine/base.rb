require 'websocket'
require 'eventmachine'

module WebSocket

  # Duplicate EventMachine constant with silenced warnings.
  begin
    old_verbose, $VERBOSE = $VERBOSE, nil
    EventMachine = ::EventMachine.dup
  ensure
    $VERBOSE = old_verbose
  end

  module EventMachine

    # WebSocket Base for Client and Server (using EventMachine)
    class Base < Connection

      ###########
      ### API ###
      ###########

      # Called when connection is opened.
      # No parameters are passed to block
      def onopen(&blk);     @onopen = blk;    end

      # Called when connection is closed.
      # Two parameters are passed to block:
      #   code - status code
      #   reason - optional reason for closure
      def onclose(&blk);    @onclose = blk;   end

      # Called when error occurs.
      # One parameter passed to block:
      #   error - string with error message
      def onerror(&blk);    @onerror = blk;   end

      # Called when message is received.
      # Two parameters passed to block:
      #   message - string with received message
      #   type - type of message. Valid values are :text and :binary
      def onmessage(&blk);  @onmessage = blk; end

      # Called when ping message is received
      # One parameter passed to block:
      #   message - string with ping message
      def onping(&blk);     @onping = blk;    end

      # Called when pond message is received
      # One parameter passed to block:
      #   message - string with pong message
      def onpong(&blk);     @onpong = blk;    end

      # Send data
      # @param data [String] Data to send
      # @param args [Hash] Arguments for send
      # @option args [String] :type Type of frame to send - available types are "text", "binary", "ping", "pong" and "close"
      # @option args [Integer] :code Code for close frame
      # @return [Boolean] true if data was send, otherwise call on_error if needed
      def send(data, args = {})
        type = args[:type] || :text
        return if @state == :closed || (@state == :closing && type != :close)
        unless type == :plain
          frame = outgoing_frame.new(:version => @handshake.version, :data => data, :type => type.to_s, :code => args[:code])
          if !frame.supported?
            trigger_onerror("Frame type '#{type}' is not supported in protocol version #{@handshake.version}")
            return false
          elsif !frame.require_sending?
            return false
          end
          data = frame.to_s
        end
        debug "Sending raw: ", data
        send_data(data)
        true
      end

      # Close connection
      # @return [Boolean] true if connection is closed immediately, false if waiting for other side to close connection
      def close(code = 1000, data = nil)
        if @state == :open
          @state = :closing
          return false if send(data, :type => :close, :code => code)
        else
          send(data, :type => :close) if @state == :closing
          @state = :closed
        end
        close_connection_after_writing
        true
      end

      # Send ping message
      # @return [Boolean] false if protocol version is not supporting ping requests
      def ping(data = '')
        send(data, :type => :ping)
      end

      # Send pong message
      # @return [Boolean] false if protocol version is not supporting pong requests
      def pong(data = '')
        send(data, :type => :pong)
      end

      ############################
      ### EventMachine methods ###
      ############################

      # Eventmachine internal
      # @private
      def receive_data(data)
        debug "Received raw: ", data
        case @state
        when :connecting then handle_connecting(data)
        when :open then handle_open(data)
        when :closing then handle_closing(data)
        end
      end

      # Eventmachine internal
      # @private
      def unbind
        unless @state == :closed
          @state = :closed
          close
          trigger_onclose(1002, '') unless @state == :connecting
        end
      end

      #######################
      ### Private methods ###
      #######################

      private

      def trigger_onopen(handshake)
        @onopen.call(handshake) if @onopen
      end

      def trigger_onmessage(data, type)
        @onmessage.call(data, type) if @onmessage
      end

      def trigger_onclose(code, reason)
        @onclose.call(code, reason) if @onclose
      end

      ['onerror', 'onping', 'onpong'].each do |m|
        define_method "trigger_#{m}" do |data|
          callback = instance_variable_get("@#{m}")
          callback.call(data) if callback
        end
      end

      def handle_connecting(data)
        @handshake << data
        return unless @handshake.finished?
        if @handshake.valid?
          send(@handshake.to_s, :type => :plain) if @handshake.should_respond?
          @frame = incoming_frame.new(:version => @handshake.version)
          @state = :open
          trigger_onopen(@handshake)
          handle_open(@handshake.leftovers) if @handshake.leftovers
        else
          trigger_onerror(@handshake.error.to_s)
          close
        end
      end

      def handle_open(data)
        @frame << data
        while frame = @frame.next
          if @state == :open
            case frame.type
            when :close
              @state = :closing
              close
              trigger_onclose(frame.code, frame.data)
            when :ping
              pong(frame.to_s)
              trigger_onping(frame.to_s)
            when :pong
              trigger_onpong(frame.to_s)
            when :text
              trigger_onmessage(frame.to_s, :text)
            when :binary
              trigger_onmessage(frame.to_s, :binary)
            end
          else
            break
          end
        end
        handle_error(@frame.error) if @frame.error?
      end

      def handle_error(error)
        error_code = case error
          when :invalid_payload_encoding then 1007
          else 1002
        end
        trigger_onerror(error.to_s)
        close(error_code)
        unbind
      end

      def handle_closing(data)
        unless @state == :closed
          @state = :closed
          close
          trigger_onclose(1000, '')
        end
      end

      def debug(description, data)
        return unless @debug
        puts(description + data.bytes.to_a.collect{|b| '\x' + b.to_s(16).rjust(2, '0')}.join) unless @state == :connecting
      end

    end
  end
end
