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

  test "connect, server goes down, publish failure, server comes back up, publish succeeds" do
    config = Beetle.config.clone
    config.servers = "127.0.0.1:5674"
    client = Beetle::Client.new(config)
    client.register_message(:test_message)

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
    end

    # now we recover and we are fine again
    assert_nothing_raised do
      assert_equal 1, client.publish(:test_message, "test data")
    end
  end
end
