# Redis convenience and compatibility layer
class Redis #:nodoc:
  def self.from_server_string(server_string)
    host, port = server_string.split(':')
    new(:host => host, :port => port)
  end

  module RoleSupport
    def available?
      info rescue false
    end

    def role
      info["role"] rescue ""
    end

    def master?
      role == "master"
    end

    def slave?
      role == "slave"
    end

    def slave_of?(master_host, master_port)
      return false unless slave?
      info["master_host"] == master_host && info["master_port"] == master_port.to_s
    end
  end

end

if Redis::VERSION >= "2.0.1"

  class Redis #:nodoc:
    # Redis 2 removed some useful methods. add them back.
    def host; @client.host; end
    def port; @client.port; end
    def server; "#{host}:#{port}"; end

    include Redis::RoleSupport

    def master!
      slaveof("no", "one")
    end

    def slave_of!(host, port)
      slaveof(host, port)
    end
  end

elsif Redis::VERSION >= "1.0.7" && Redis::VERSION < "2.0.0"

  class Redis::Client #:nodoc:
    attr_reader :host, :port

    include Redis::RoleSupport

    def master!
      slaveof("no one")
    end

    def slave_of!(host, port)
      slaveof("#{host} #{port}")
    end
  end

else

  raise "Your redis-rb version is not supported!"

end
