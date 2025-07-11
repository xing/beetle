module Beetle
  # A BunnySession that contains extensions that help us to cleanly start and stop connections
  class BunnySession < Bunny::Session
    class ShutdownError < StandardError; end

    def start_safely
      # Hard cap the connection beyond the socket timeout
      # This is applied to all connections for consistency but we have only seen it being required for TLS connections.
      #
      # For TLS connections we have two phases
      # 1. The socket connect
      # 2. The TLS negotiation
      #
      # While the socket connect timeout takes effect on the initial socket connection,
      # it does not take effect on the TLS negotiation.
      #
      # This means that if the TLS negotiation takes longer than the connect timeout,
      # the connection will hang long (10 seconds in our observations).
      #
      # We add a small buffer to the connect timeout to avoid a race with the socket timeout.
      Timeout.timeout(transport.connect_timeout + 0.2) do
        start
      end
    rescue StandardError => e
      _log_errors_only do
        stop_safely
      end

      raise e
    end

    # Stops the bunny session and makes sure that all resources are cleaned up properly,
    # even if the session is in some incomplete state.
    #
    # Bunny in principle does all of these steps on close, but onfortunately it will
    # stop cleaning up after the first error occurs in the sequence of things that need to be done.
    # This has the potential to leave threads running, connections open, etc.
    # That's why we're doing it manually here.
    def stop_safely
      logger.debug "Beetle: closing connection from bunny session"

      @status_mutex.synchronize { @status = :closing }

      stopped_threads = _stop_background_threads!
      stopped_network = _stop_network_connection!

      if stopped_threads && stopped_network
        @status_mutex.synchronize do
          @status = :closed
          @manually_closed = true
        end

        return
      end

      raise ShutdownError, "Failed to stop session cleanly. stopped_threads: #{stopped_threads}, stopped_network: #{stopped_network}"
    end

    def _heartbeat_sender_alive?
      @heartbeat_sender&.instance_variable_get(:@thread)&.alive? || false
    end

    def _reader_loop_alive?
      reader_loop&.instance_variable_get(:@thread)&.alive? || false
    end

    private

    def _log_errors_only
      yield if block_given?
    rescue StandardError => e
      logger.error "Beetle: error during operation: #{e.message}"
    end

    def _stop_background_threads!
      stopped_heartbeat = false
      stopped_reader = false

      begin
        maybe_shutdown_heartbeat_sender
        stopped_heartbeat = true
      rescue StandardError => e
        logger.warn "Beetle: error shutting down heartbeat sender: #{e}"
      end

      begin
        reader_loop&.kill
        stopped_reader = true
      rescue StandardError => e
        logger.warn "Beetle: error shutting down reader loop: #{e}"
      end

      stopped_heartbeat && stopped_reader
    end

    def _stop_network_connection!
      stopped_connection = false
      stopped_socket = false

      begin
        close_connection(false)
        stopped_connection = true
      rescue StandardError => e
        logger.warn "Beetle: error closing connection to server: #{e}"
      end

      begin
        maybe_close_transport
        stopped_socket = true
      rescue StandardError => e
        logger.warn "Beetle: error closing transport to server: #{e}"
      end

      stopped_connection && stopped_socket
    end
  end
end
