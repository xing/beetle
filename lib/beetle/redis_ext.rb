class Redis
  def self.from_server_string(server_string)
    host, port = server_string.split(':')
    new(:host => host, :port => port)
  end
end

class Redis::Client
  attr_reader :host, :port

  def available?
    info rescue false
  end
  
  def master?
    info["role"] == "master"
  end
  
  def slave?
    info["role"] == "slave"
  end
  
  def master!
    slaveof("no one")
  end
  
  def slave_of!(host, port)
    slaveof("#{host} #{port}")
  end
end
