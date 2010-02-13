module Beetle
  class Client
    attr_reader :servers

    def initialize(options = {})
      @servers = ['localhost:5672']
      @options = options
      @queue_names_for_exchange = {}
      load_config(options[:config_file])
    end

    def register_exchange(name, opts={})
      raise ConfigurationError.new("exchange #{name} already configured") if exchanges.include?(name)
      exchanges[name] = opts.symbolize_keys
    end

    def exchanges
      @amqp_config["exchanges"]
    end

    def register_queue(name, opts={})
      raise ConfigurationError.new("queue #{name} already configured") if queues.include?(name)
      queues[name] = opts.symbolize_keys
    end

    def queues
      @amqp_config["queues"]
    end

    def register_message(name, opts={})
      raise ConfigurationError.new("message #{name} already configured") if messages.include?(name)
      messages[name] = opts.symbolize_keys
    end

    def messages
      @amqp_config["messages"]
    end

    def queues_for_exchange(exchange_name)
      @queue_names_for_exchange[exchange_name] ||=
        queues.select { |queue, config| config[:exchange] == exchange_name || (config[:exchange].blank? && queue == exchange_name) }.map(&:first)
    end

    def queue_for_message(message_name)
      ((m = messages[message_name]) && m[:queue]) || message_name
    end

    def exchange_for_queue(queue_name)
      ((q = queues[queue_name]) && q[:exchange]) || queue_name
    end

    def exchange_for_message(message_name)
      exchange_for_queue(queue_for_message(message_name))
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
      @amqp_config = Hash.new {|hash, key| hash[key] = {}}
      if glob = (file_name || Beetle.config.config_file)
        Dir[glob].each do |file|
          hash = YAML::load(ERB.new(IO.read(file)).result)
          hash.each do |key, value|
            @amqp_config[key].merge! value
          end
        end
      end
      @amqp_config["exchanges"] ||= {}
      @amqp_config["messages"] ||= {}
      @amqp_config["queues"] ||= {}
      env = Beetle.config.environment
      @amqp_config[env] ||= {}
      @amqp_config[env]["hostname"] ||= "localhost:5672"
      @amqp_config[env]["msg_id_store"] ||= {:host => "localhost", :db => 4}

      @servers = @amqp_config[env]["hostname"].split(/ *, */)
      Message.redis = Redis.new(@amqp_config[env]["msg_id_store"].symbolize_keys)
    end

    def publisher
      @publisher ||= Publisher.new(self)
    end

    def subscriber
      @subscriber ||= Subscriber.new(self)
    end
  end
end
