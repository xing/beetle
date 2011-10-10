require File.expand_path(File.dirname(__FILE__) + '/../test_helper')
require 'eventmachine'
require 'amqp'

class AMQPGemBehaviorTest < Test::Unit::TestCase
  test "subscribing twice to the same queue raises a RuntimeError which throws us out of the event loop" do
    begin
      @exception = nil
      EM.run do
        AMQP.start do |connection|
          begin
            EM::Timer.new(1){ connection.close { EM.stop }}
            channel = AMQP::Channel.new(connection)
            channel.on_error { puts "woot"}
            exchange = channel.topic("beetle_tests")
            queue = AMQP::Queue.new(channel)
            queue.bind(exchange, :key => "#")
            queue.subscribe { }
            queue.subscribe { }
          rescue
            # we never get here, because the subscription is deferred
            # the only known way to avoid this is to use the block version of AMQP::Queue.new
          end
        end
      end
    rescue Exception => @exception
    end
    assert @exception
  end
end
