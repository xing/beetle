require File.expand_path(File.dirname(__FILE__) + '/../test_helper')
require 'eventmachine'
require 'amqp'

class AMQPGemBehaviorTest < Minitest::Test
  test "subscribing twice to the same queue raises a RuntimeError which throws us out of the event loop" do
    begin
      exception = nil
      EM.run do
        AMQP.start(logging: false, host: ENV['RABBITMQ_SERVERS'] || 'localhost') do |connection|
          EM::Timer.new(1){ connection.close { EM.stop }}
          channel = AMQP::Channel.new(connection)
          channel.on_error { puts "woot"}
          exchange = channel.topic("beetle_tests", :durable => false, :auto_delete => true)
          queue = AMQP::Queue.new(channel, :durable => false, :auto_delete => true)
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
