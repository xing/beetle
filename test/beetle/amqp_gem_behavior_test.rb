require File.expand_path(File.dirname(__FILE__) + '/../test_helper')
require 'eventmachine'
require 'amqp'

class AMQPGemBehaviorTest < Minitest::Test
  test "subscribing twice to the same queue raises a RuntimeError which throws us out of the event loop" do
    begin
      exception = nil
      EM.run do
        AMQP.start(:host => ENV['RABBITMQ_HOST'] || '127.0.0.1', :logging => false) do |connection|
          EM::Timer.new(1){ connection.close { EM.stop }}
          channel = AMQP::Channel.new(connection)
          channel.on_error { puts "woot"}
          exchange = channel.topic("beetle_tests")
          queue = AMQP::Queue.new(channel)
          queue.bind(exchange, :key => "#")
          queue.subscribe { }
          queue.subscribe { }
        end
      end
    rescue AMQP::TCPConnectionFailed
      if ENV['TRAVIS']=='true'
        assert true
      else
        flunk "\nbroker not running.\nplease start it to test the behavior of subscribing to a queue twice."
      end
    rescue Exception => exception
      assert_kind_of RuntimeError, exception
    end
  end
end
