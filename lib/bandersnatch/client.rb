module Bandersnatch
  class Client
    attr_reader :amqp_config, :servers, :messages

    def initialize(options = {})
      @servers = []
      @messages = {}
      @options = options
      load_config(options[:config_file])
      Message.redis = Redis.new(@amqp_config[Bandersnatch.config.environment]["msg_id_store"].symbolize_keys)
    end

    def current_server
      @server
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

    def register_handler(messages, opts, &block)
      subscriber.register_handler(messages, opts, &block)
    end

    def test
      error "testing only allowed in development environment" unless Bandersnatch.config.environment == "development"
      trap("INT") { exit(1) }
      while true
        publisher.publish "redundant", "hello, I'm redundant!"
        sleep 1
      end
    end

    def trace
      subscriber.trace = true
      register_handler("redundant", :queue => "additional_queue", :ack => true, :key => '#') {|msg| puts "------===== Additional Handler =====-----" }
      register_handler(@messages.keys, :ack => true, :key => '#') do |msg|
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
      @logger ||= Bandersnatch.config.logger
    end

    private

    def load_config(file_name)
      @amqp_config = Hash.new {|hash, key| hash[key] = {}}
      glob = file_name || Bandersnatch.config.config_file
      Dir[glob].each do |file|
        hash = YAML::load(ERB.new(IO.read(file)).result)
        hash.each do |key, value|
          @amqp_config[key].merge! value
        end
      end
      @messages = @amqp_config["messages"]
      @servers = @amqp_config[Bandersnatch.config.environment]['hostname'].split(/ *, */)
    end

    def publisher
      @publisher ||= Publisher.new(self)
    end

    def subscriber
      @subscriber ||= Subscriber.new(self)
    end
  end
end
