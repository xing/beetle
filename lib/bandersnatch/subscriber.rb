module Bandersnatch
  class Subscriber < Base
    def initialize
      # legacy, will get removed after refactoring
      super(:sub)
    end

    private
      def bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
        queue = mq.queue(queue_name, creation_keys)
        queue.bind(exchange(exchange_name), binding_keys)
        queue
      end

      def stop!
        @amqp_connections.each_value{|c| c.close}
        @amqp_connections = {}
        @mqs = {}
        EM.stop_event_loop
      end
  end
end