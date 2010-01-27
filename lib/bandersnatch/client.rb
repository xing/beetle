module Bandersnatch
  class Client
    def initialize
      # TODO: refactoring helper code, will be replaced
      @publisher = Publisher.new(:pub)
      @subscriber = Subscriber.new(:sub)
    end

    # TODO: refactoring helper code, will be replaced
    def publish(message_name, data, opts={})
      @publisher.publish(message_name, data, opts={})
    end

    # TODO: refactoring helper code, will be replaced
    def subscribe(messages = nil)
      @subscribe.subscribe(messages)
    end

    # TODO: refactoring helper code, will be replaced
    def trace
      @subscriber.trace
    end

    # TODO: refactoring helper code, will be replaced
    def test
      @publisher.test
    end
  end
end