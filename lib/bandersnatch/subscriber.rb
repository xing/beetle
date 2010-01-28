module Bandersnatch
  class Subscriber < Base
    def initialize
      # legacy, will get removed after refactoring
      super(:sub)
    end

    private
      def create_exchange!(name, opts)
        mq.__send__(opts[:type], name, opts.slice(*EXCHANGE_CREATION_KEYS))
      end

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

      def new_amqp_connection
        AMQP.connect(:host => current_host, :port => current_port)
      end

      def amqp_connection
        @amqp_connections[@server] ||= new_amqp_connection
      end
  end
end