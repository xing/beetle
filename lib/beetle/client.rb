module Beetle
  class Client
    attr_reader :servers, :exchanges, :queues, :messages

    def initialize(options = {})
      @servers = ['localhost:5672']
      @exchanges = {}
      @queues = {}
      @messages = {}
      @options = options
      load_config(options[:config_file])
    end

    def register_exchange(name, opts={})
      raise ConfigurationError.new("exchange #{name} already configured") if exchanges.include?(name)
      exchanges[name] = opts.symbolize_keys
    end

    def register_queue(name, opts={})
      raise ConfigurationError.new("queue #{name} already configured") if queues.include?(name)
      opts = {:exchange => name}.merge!(opts.symbolize_keys)
      queues[name] = opts
      (exchanges[opts[:exchange]][:queues] ||= []) << name
    end

    def register_message(name, opts={})
      raise ConfigurationError.new("message #{name} already configured") if messages.include?(name)
      opts = {:queue => name}.merge!(opts.symbolize_keys)
      opts[:exchange] = queues[opts[:queue]][:exchange]
      messages[name] = opts
    end

    def register_handler(*args, &block)
      subscriber.register_handler(*args, &block)
    end

    def publish(message_name, data, opts={})
      publisher.publish(message_name, data, opts)
    end

    def listen
      subscriber.listen
    end

    def stop_listening
      subscriber.stop
    end

    def trace
      subscriber.trace = true
      register_handler(messages.keys, :ack => true, :key => '#') do |msg|
        puts "-----===== new message =====-----"
        puts "SERVER: #{msg.server}"
        puts "HEADER: #{msg.header.inspect}"
        puts "UUID: #{msg.uuid}" if msg.uuid
        puts "DATA: #{msg.data}"
      end
      subscriber.listen
    end

    def autoload(glob)
      b = binding
      Dir[glob].each do |f|
        eval(File.read(f), b, f)
      end
    end

    def logger
      @logger ||= Beetle.config.logger
    end

    private

    def load_config(file_name)
      config = Hash.new {|hash, key| hash[key] = {}}
      if glob = (file_name || Beetle.config.config_file)
        Dir[glob].each do |file|
          hash = YAML::load(ERB.new(IO.read(file)).result)
          hash.each do |key, value|
            config[key].merge! value
          end
        end
      end

      env = Beetle.config.environment

      config[env] ||= {}
      config[env]["hostname"] ||= "localhost:5672"
      config[env]["msg_id_store"] ||= {:host => "localhost", :db => 4}

      (config["exchanges"] || {}).each {|name, opts| register_exchange(name, opts)  }
      (config["queues"]    || {}).each {|name, opts| register_queue(name, opts)     }
      (config["messages"]  || {}).each {|name, opts| register_message(name, opts)   }

      @servers = config[env]["hostname"].split(/ *, */)
      Message.redis = Redis.new(config[env]["msg_id_store"].symbolize_keys)
    end

    def publisher
      @publisher ||= Publisher.new(self)
    end

    def subscriber
      @subscriber ||= Subscriber.new(self)
    end
  end
end
