module Bandersnatch
  class Client
    attr_reader :handlers

    def initialize
      @handlers = {}
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
      Array(messages).each do |message|
        (@handlers[message] ||= []) << [opts.symbolize_keys, block]
      end
    end

    private
      def publisher
        @publisher ||= Publisher.new(self)
      end

      def subscriber
        @subscriber ||= Subscriber.new(self)
      end
  end
end