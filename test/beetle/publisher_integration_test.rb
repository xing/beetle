require 'timeout'
require File.expand_path(File.dirname(__FILE__) + '/../test_helper')
require "toxiproxy"

Toxiproxy.host = "http://127.0.0.1:8474"
Toxiproxy.populate([
                     { name: "rabbitmq1", listen: "0.0.0.0:5674", upstream: "rabbitmq1:5672" },
                     { name: "rabbitmq2", listen: "0.0.0.0:5675", upstream: "rabbitmq2:5673" }
                   ])

class PublisherIntegrationTest < Minitest::Test
  def setup
    Toxiproxy[:rabbitmq1].enable
    Toxiproxy[:rabbitmq2].enable
  end

  def rabbit1
    Toxiproxy[:rabbitmq1]
  end

  def rabbit2
    Toxiproxy[:rabbitmq2]
  end

  def with_client(servers, &block)
    config = Beetle.config.clone
    config.servers = servers
    client = Beetle::Client.new(config)
    client.register_message(:test_message)
    block.call(client)
  ensure
    client.send(:publisher)&.stop
  end

  test "recreating bunnies does not leave threads behind" do
    with_client("127.0.0.1:5674") do |client|
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end

      # connected(1 heartbeat sender)
      rabbit1.down do
        sleep 0.5 # give bunny time to recognize the server is down
      end

      # bunny is now exception state, 1 hearbeat sender
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end

      rabbit1.down do
        sleep 0.5 # give bunny time to recognize the server is down
      end

      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end

      bunny_threads = Thread.list.select { |t| t.inspect.include?("lib/bunny") }
      assert 2, bunny_threads.size
    end
  end

  test "connect, server goes down, publish failure (twice), server comes back up, publish succeeds" do
    with_client("127.0.0.1:5674") do |client|
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end

      rabbit1.down do
        assert_nothing_raised do
          sleep 1 # give bunny time to recognize the server is down
        end

        assert client.send(:publisher).exceptions?

        assert_raises(Beetle::NoMessageSent) do
          client.publish(:test_message, "test data")
        end

        assert_raises(Beetle::NoMessageSent) do
          client.publish(:test_message, "test data")
        end
      end

      # now we recover and we are fine again
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end
    end
  end

  test "connect, server goes down, error is detected, server comes up, publish succeeds" do
    with_client("127.0.0.1:5674") do |client|
      # connect and send
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end

      rabbit1.down do
        sleep 1 # give bunny time to recognize the server is down
      end

      assert client.send(:publisher).exceptions?, "Publisher should have detected the server down"

      # server should be up again and we recover
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end
    end
  end

  # TODO: add tests for multiple servers

  test "server down, publish fails, server comes up, publish succeeds" do
    with_client("127.0.0.1:5674") do |client|
      rabbit1.down do
        assert_raises(Beetle::NoMessageSent) do
          client.publish(:test_message, "test data")
        end
      end

      # server should be up again and we recover
      assert_nothing_raised do
        client.publish(:test_message, "test data")
      end
    end
  end

  test "connect, timeout + empty response, publish succeeds again" do
    with_client("127.0.0.1:5674") do |client|
      # connect
      assert_nothing_raised do
        assert_equal 1, client.publish(:test_message, "test data")
      end

      refute client.send(:publisher).exceptions?
      # now publish with failure
      rabbit1.downstream(:timeout, timeout: 1).apply do
        sleep 0.5
        assert_raises(Beetle::NoMessageSent) do
          client.publish(:test_message, "test data")
        end
      end

      assert_nothing_raised do
        client.publish(:test_message, "test data")
      end
    end
  end
end
