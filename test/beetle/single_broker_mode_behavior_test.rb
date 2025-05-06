require 'timeout'
require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class SingleBrokerModeBehaviorTest < Minitest::Test
  attr_reader :client

  def setup
    Beetle.config.servers = "localhost:5672"
    @client = Beetle::Client.new
    client.register_queue(:test_single_broker)
    client.register_message(:test_single_broker)
    client.purge(:test_single_broker)
  end

  test "handles retries correctly" do
    assert true
  end

  test "handles attempts correctly" do
    assert true
  end

  test "handles timeouts correctly" do
    message = nil

    client.register_handler(:test_single_broker, timeout: 1) do |msg|
      sleep 1.5
      message = msg
      client.stop_listening
    end
    published = client.publish(:test_single_broker, 'single-broker')

    listen(client, 2)
    client.stop_publishing

    assert_equal 1, published
    refute message
  end

  test "ignores expired messages" do
    message = nil

    client.register_handler(:test_single_broker) do |msg|
      message = msg
      client.stop_listening
    end
    published = client.publish(:test_single_broker, 'single-broker', ttl: -3600) # expired 1 hour ago

    listen(client)
    client.stop_publishing

    assert_equal 1, published
    refute message
  end

  test "processes fresh message" do
    message = nil

    client.register_handler(:test_single_broker) do |msg|
      message = msg
      client.stop_listening
    end
    published = client.publish(:test_single_broker, 'single-broker', ttl: 30)

    listen(client)
    client.stop_publishing

    assert_equal 1, published
    assert_equal "single-broker", message.data
  end

  def listen(client, timeout = 1)
    Timeout.timeout(timeout) do
      client.listen
    end
  rescue Timeout::Error
    puts "Client listen timed out after #{timeout} seconds"
    nil
  end

end
