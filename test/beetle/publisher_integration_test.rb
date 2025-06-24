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

  def teardown
    rabbit1.disable
    rabbit2.disable
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
    logbuffer = StringIO.new
    config.logger = Logger.new(logbuffer)
    client = Beetle::Client.new(config)
    client.register_message(:test_message)
    client.register_message(:redundant_message, redundant: true)
    block.call(client, logbuffer)
  ensure
    client.send(:publisher)&.stop
  end

  [:test_message, :redundant_message].each do |msg|
    test "[#{msg}] recreating bunnies does not leave threads behind" do
      with_client("127.0.0.1:5674") do |client|
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        # connected(1 heartbeat sender)
        rabbit1.down do
          wait_until { client.publisher_exceptions? }
        end

        # bunny is now exception state, 1 hearbeat sender
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        rabbit1.down do
          wait_until { client.publisher_exceptions? }
        end

        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        bunny_threads = Thread.list.select { |t| t.inspect.include?("lib/bunny") }
        assert 2, bunny_threads.size
      end
    end

    test "[multiserver][#{msg}] recreating bunnies does not leave threads behind" do
      with_client("127.0.0.1:5674, 127.0.0.1:5675") do |client|
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        # connected(1 heartbeat sender)
        rabbit1.down do
          rabbit2.down do
            wait_until { client.publisher_exceptions? }
          end
        end

        # bunny is now exception state, 1 hearbeat sender
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        rabbit1.down do
          rabbit2.down do
            wait_until { client.publisher_exceptions? }
          end
        end

        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        bunny_threads = Thread.list.select { |t| t.inspect.include?("lib/bunny") }
        assert 2, bunny_threads.size
      end
    end

    test "[#{msg}] server down, publish fails" do
      with_client("127.0.0.1:5674") do |client, logs|
        rabbit1.down do
          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end
        end

        refute client.send(:publisher).send(:bunny?) # no bunny active
        assert_match(/Beetle: publishing exception/, logs.string)
      end
    end

    test "[multiserver][#{msg}] server down, publish fails" do
      with_client("127.0.0.1:5674") do |client|
        rabbit1.down do
          rabbit2.down do
            assert_raises(Beetle::NoMessageSent) do
              client.publish(msg, "test data")
            end
          end
        end

        refute client.send(:publisher).send(:bunny?) # no bunny active
      end
    end

    test "[#{msg}] server resets, publish fails" do
      with_client("127.0.0.1:5674") do |client|
        rabbit1.downstream(:reset_peer, timeout: 0).apply do
          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end
        end

        refute client.send(:publisher).send(:bunny?) # no bunny active
      end
    end

    test "[multiserver][#{msg}] server resets, publish fails" do
      with_client("127.0.0.1:5674") do |client|
        rabbit1.downstream(:reset_peer, timeout: 0).apply do
          rabbit2.downstream(:reset_peer, timeout: 0).apply do
            assert_raises(Beetle::NoMessageSent) do
              client.publish(msg, "test data")
            end
          end
        end

        refute client.send(:publisher).send(:bunny?) # no bunny active
      end
    end

    test "[#{msg}] server timeout, publish fails" do
      with_client("127.0.0.1:5674") do |client|
        rabbit1.downstream(:timeout, timeout: 3).apply do
          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end
        end

        refute client.send(:publisher).send(:bunny?) # no bunny active
      end
    end

    test "[multiserver][#{msg}]  server timeout, publish fails" do
      with_client("127.0.0.1:5674") do |client|
        rabbit1.downstream(:timeout, timeout: 3).apply do
          rabbit2.downstream(:timeout, timeout: 3).apply do
            assert_raises(Beetle::NoMessageSent) do
              client.publish(msg, "test data")
            end
          end
        end

        refute client.send(:publisher).send(:bunny?) # no bunny active
      end
    end

    test "[#{msg}] connect, server goes down, publish failure (twice), server comes back up, publish succeeds" do
      with_client("127.0.0.1:5674") do |client, logs|
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        rabbit1.down do
          assert_nothing_raised do
            wait_until { client.publisher_exceptions? }
          end

          assert client.publisher_exceptions?

          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end

          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end
        end

        assert_match(/Beetle: message sent!/, logs.string)
        assert_match(/Beetle: closing connection from publisher to 127.0.0.1:5674 forcefully/, logs.string)
        assert_match(/Beetle: message could not be delivered/, logs.string)

        refute client.send(:publisher).send(:bunny?) # no bunny active

        # now we recover and we are fine again
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end
      end
    end

    test "[#{msg}] connect, server goes down, background error is detected, server comes up, publish succeeds (with new bunny)" do
      with_client("127.0.0.1:5674") do |client|
        # connect and send
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        rabbit1.down do
          wait_until { client.publisher_exceptions? }
        end

        assert client.publisher_exceptions?, "Publisher should have detected the server down"

        # server should be up again and we recover
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end
      end
    end

    test "[#{msg}] server down, publish fails, server comes up, publish succeeds" do
      with_client("127.0.0.1:5674") do |client|
        rabbit1.down do
          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end
        end

        # server should be up again and we recover
        assert_nothing_raised do
          client.publish(msg, "test data")
        end
      end
    end

    test "[#{msg}] connect, timeout + empty response, publish succeeds again" do
      with_client("127.0.0.1:5674") do |client|
        # connect
        assert_nothing_raised do
          assert_equal 1, client.publish(msg, "test data")
        end

        assert client.publisher_healthy?
        # now publish with failure
        rabbit1.downstream(:timeout, timeout: 1).apply do
          sleep 0.3
          assert_raises(Beetle::NoMessageSent) do
            client.publish(msg, "test data")
          end
        end

        assert_nothing_raised do
          client.publish(msg, "test data")
        end
      end
    end
  end
end
