module Bandersnatch
  class Client
    attr_reader :amqp_config, :servers, :messages

    def initialize
      @servers = {}
      @messages = {}
      @amqp_config = {}
      load_config(nil) # JA MANN später!
    end

    def current_server
      @server
    end

    # TODO: refactoring helper code, will be replaced
    def publish(message_name, data, opts={})
      publisher.publish(message_name, data, opts={})
    end

    # TODO: refactoring helper code, will be replaced
    def subscribe(messages = nil)
      subscriber.subscribe(messages)
    end

    # TODO: refactoring helper code, will be replaced
    def trace
      subscriber.trace
    end

    # TODO: refactoring helper code, will be replaced
    def test
      publisher.test
    end

    def register_handler(messages, opts, &block)
      subscriber.register_handler(messages, opts, &block)
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

    private
    def load_config(file_name=nil)
      file_name ||= Bandersnatch.config.config_file
      @amqp_config = YAML::load(ERB.new(IO.read(file_name)).result)
      @servers = @amqp_config[RAILS_ENV]['hostname'].split(/ *, */)
      @messages = @amqp_config['messages']
    end

    def publisher
      @publisher ||= Publisher.new(self)
    end

    def subscriber
      @subscriber ||= Subscriber.new(self)
    end
  end
end