# Redis convenience and compatibility layer
class Redis #:nodoc:
  def self.from_server_string(server_string, options = {})
    host, port = server_string.split(':')
    options = {:host => host, :port => port}.update(options)
    options.delete(:logger) if Redis::VERSION >= "5.0"
    new(options)
  end

  # Redis 2 removed some useful methods. add them back.
  def host; @client.host; end
  def port; @client.port; end
  def server; "#{host}:#{port}"; end

  def master!
    slaveof("no", "one")
  end

  def slave_of!(host, port)
    slaveof(host, port)
  end

  def info_with_rescue
    info
  rescue Exception
    {}
  end

  def available?
    info_with_rescue != {}
  end

  def role
    info_with_rescue["role"] || "unknown"
  end

  def master?
    role == "master"
  end

  def slave?
    role == "slave"
  end

  def slave_of?(host, port)
    info = info_with_rescue
    info["role"] == "slave" && info["master_host"] == host && info["master_port"] == port.to_s
  end

  if Redis::VERSION < "3.0"

    # compatibility layer for redis 2.2.2
    # remove this once all our apps have upgraded to 3.x

    # Redis 2 tries to establish a connection on inspect. this is evil!
    def inspect
      super
    end

    # redis 2.2.2 shutdown implementation does not disconnect from the redis server.
    # this leaves the connection in an inconsistent state and causes the next command to silently fail.
    # this in turn breaks our cucumber test scenarios.
    # fix this here, until a new version is released which fixes the problem.

    alias_method :broken_shutdown, :shutdown

    # Synchronously save the dataset to disk and then shut down the server.
    def shutdown
      synchronize do
        begin
          @client.call [:shutdown]
        rescue Errno::ECONNREFUSED
        ensure
          @client.disconnect
        end
      end
    end

    def msetnx(*values)
      super != 0
    end

  elsif Redis::VERSION >= "5.0.0"

    # redis 5.0.0 has a shutdown method which raises if a connection to the redis server
    # cannot be established.
    module SaneShutdown
      def shutdown
        super
      rescue RedisClient::CannotConnectError
        nil
      end
    end
    prepend SaneShutdown

  elsif Redis::VERSION >= "4.0.0"

    # redis 4.0.0 has a shutdown method which raises if a connection to the redis server
    # cannot be established.
    module SaneShutdown
      def shutdown
        super
      rescue CannotConnectError
        nil
      end
    end
    prepend SaneShutdown

  end
end
