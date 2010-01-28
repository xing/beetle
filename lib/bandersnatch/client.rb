module Bandersnatch
  class Client
    # TODO: refactoring helper code, will be replaced
    def publish(message_name, data, opts={})
      publisher.publish(message_name, data, opts={})
    end

    # TODO: refactoring helper code, will be replaced
    def subscribe(messages = nil)
      subscribe.subscribe(messages)
    end

    # TODO: refactoring helper code, will be replaced
    def trace
      subscriber.trace
    end

    # TODO: refactoring helper code, will be replaced
    def test
      publisher.test
    end

    private
      def publisher
        @publisher ||= Publisher.new
      end

      def subscriber
        @subscriber ||= Subscriber.new
      end
  end
end