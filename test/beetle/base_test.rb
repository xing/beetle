require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class BaseTest < Minitest::Test
    test "initially we should have no exchanges" do
      @bs = Base.new(Client.new)
      assert_equal({}, @bs.instance_variable_get("@exchanges"))
    end

    test "initially we should have no queues" do
      @bs = Base.new(Client.new)
      assert_equal({}, @bs.instance_variable_get("@queues"))
    end

    test "the error method should raise a beetle error" do
      @bs = Base.new(Client.new)
      assert_raises(Error){ @bs.send(:error, "ha") }
    end
  end

  class BaseServerManagementTest < Minitest::Test
    def setup
      @client = Client.new
      @bs = Base.new(@client)
    end

    test "server should be initialized" do
      assert @bs.server
    end

    test "current_host should return the hostname of the current server" do
      @bs.server = "localhost:123"
      assert_equal "localhost", @bs.send(:current_host)
    end

    test "current_port should return the port of the current server as an integer" do
      @bs.server = "localhost:123"
      assert_equal 123, @bs.send(:current_port)
    end

    test "current_port should return the default rabbit port if server string does not contain a port" do
      @bs.server = "localhost"
      assert_equal 5672, @bs.send(:current_port)
    end

    test "set_current_server shoud set the current server" do
      @bs.send(:set_current_server, "xxx:123")
      assert_equal "xxx:123", @bs.server
    end

    test "server_from_settings should create a valid server string from an AMQP settings hash" do
      assert_equal "goofy:123", @bs.send(:server_from_settings, {:host => "goofy", :port => 123})
    end
  end

  class BindDeadLetterQueuesTest < Minitest::Test
    def setup
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @client = Client.new @config
      @bs = Base.new(@client)
      @config.logger = Logger.new("/dev/null")
    end

    test "it does not call out to rabbit if neither dead lettering nor lazy queues are enabled" do
      @client.register_queue(@queue_name, :dead_lettering => false, :lazy => false)
      channel = stub('channel')
      expected_options = {
        :queue_name => "QUEUE_NAME",
        :bindings=>[{:exchange=>"QUEUE_NAME", :key=>"QUEUE_NAME"}],
        :dead_letter_queue_name=>"QUEUE_NAME_dead_letter",
        :message_ttl => 1000,
        :dead_lettering => false,
        :lazy => false
      }
      assert_equal expected_options, @bs.__send__(:bind_dead_letter_queue!, channel, @queue_name)
    end

    test "creates and connects the dead letter queue via policies when enabled" do
      @client.register_queue(@queue_name, :dead_lettering => true, :lazy => true)

      channel = stub('channel')
      channel.expects(:queue).with("#{@queue_name}_dead_letter", {})

      expected_options = {
        :queue_name => "QUEUE_NAME",
        :bindings=>[{:exchange=>"QUEUE_NAME", :key=>"QUEUE_NAME"}],
        :dead_letter_queue_name=>"QUEUE_NAME_dead_letter",
        :message_ttl => 1000,
        :dead_lettering => true,
        :lazy => true
      }
      assert_equal expected_options, @bs.__send__(:bind_dead_letter_queue!, channel, @queue_name)
    end

    test "publish_policy_options declares the beetle policy updates queue and publishes the options" do
      options = { queue_name: @queue_name, :lazy => true, :dead_lettering => true }
      @bs.logger.stubs(:debug)
      @bs.expects(:queue).with(@client.config.beetle_policy_updates_queue_name)
      exchange = mock("exchange")
      exchange.expects(:publish)
      @bs.expects(:exchange).with(@client.config.beetle_policy_exchange_name).returns(exchange)
      @bs.__send__(:publish_policy_options, options)
    end

    test "publish_policy_options calls the RabbitMQ API if asked to do so" do
      options = { queue_name: @queue_name, :lazy => true, :dead_lettering => true }
      @bs.logger.stubs(:debug)
      @client.config.expects(:update_queue_properties_synchronously).returns(true)
      @client.expects(:update_queue_properties!).with(options.merge(:server => "localhost:5672", queue_type: nil))
      @bs.__send__(:publish_policy_options, options)
    end

  end
end
