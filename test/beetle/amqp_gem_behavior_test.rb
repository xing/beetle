require File.expand_path(File.dirname(__FILE__) + '/../test_helper')
require 'eventmachine'
require 'amqp'

class AMQPGemBehaviorTest < Test::Unit::TestCase
  test "subscribing twice to the same queue raises a RuntimeError" do
    begin
    @exception = nil
      EM.run do
        AMQP.start do |connection|
          begin
            EM::Timer.new(1){ AMQP.stop { EM.stop }}
            channel = AMQP::Channel.new(connection)
            channel.on_error { puts "woot"}
            exchange = channel.topic("beetle_tests")
            queue = AMQP::Queue.new(channel)
            queue.bind(exchange, :key => "#")
            queue.subscribe { }
            queue.subscribe { }
          end
        end
      end
    rescue Exception => @exception
    end
    puts @exception
    assert @exception
  end
end
