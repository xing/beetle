require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class ClientDefaultsTest < Test::Unit::TestCase
    def setup
      @client = Client.new
    end

    test "should have a default server even without a config file" do
      assert_equal ["localhost:5672"], @client.servers
    end

    test "should have no exchanges" do
      assert @client.exchanges.empty?
    end

    test "should have no queues" do
      assert @client.queues.empty?
    end
    test "should have no messages" do
      assert @client.messages.empty?
    end
  end

  class ClientConfigFileLoadingTest < Test::Unit::TestCase
    def setup
      @client = Client.new(:config_file =>  File.expand_path(File.dirname(__FILE__) + '/../beetle.yml'))
    end

    test "loading test config file should specify server localhost::5672" do
      assert_equal ["localhost:5672"], @client.servers
    end

    test "loading test config should specify test and deadletter messages" do
      assert @client.messages.include? "deadletter"
      assert @client.messages.include? "test"
    end
  end

  class RegistrationTest < Test::Unit::TestCase
    def setup
      @client = Client.new
    end

    test "registering an exchange should store it in the configuration with symbolized option keys and force a topic queue and durability" do
      opts = {"durable" => false, "type" => "fanout"}
      @client.register_exchange("some_exchange", opts)
      assert_equal({:durable => true, :type => :topic}, @client.exchanges["some_exchange"])
    end

    test "registering an exchange should raise a configuration error if it is already configured" do
      @client.register_exchange("some_exchange")
      assert_raises(ConfigurationError){ @client.register_exchange("some_exchange") }
    end

    test "registering a queue should automatically register the corresponding exchange if it doesn't exist yet" do
      @client.register_queue("some_queue", "durable" => false, "exchange" => "some_exchange")
      assert @client.exchanges.include?("some_exchange")
    end

    test "registering a queue should store it in the configuration with symbolized option keys and force durable=true and passive=false" do
      @client.register_queue("some_queue", "durable" => false, "exchange" => "some_exchange")
      assert_equal({:durable => true, :passive => false, :exchange => "some_exchange"}, @client.queues["some_queue"])
    end

    test "registering a queue should add the queue to the list of queues of the queue's exchange" do
      @client.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange")
      assert_equal ["some_queue"], @client.exchanges["some_exchange"][:queues]
    end

    test "registering two queues should add both queues to the list of queues of the queue's exchange" do
      @client.register_queue("queue1", :exchange => "some_exchange")
      @client.register_queue("queue2", :exchange => "some_exchange")
      assert_equal ["queue1","queue2"], @client.exchanges["some_exchange"][:queues]
    end

    test "registering a queue should raise a configuration error if it is already configured" do
      @client.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange")
      assert_raises(ConfigurationError){ @client.register_queue("some_queue") }
    end

    test "registering a message should store it in the configuration with symbolized option keys" do
      opts = {"persistent" => true, "queue" => "some_queue"}
      @client.register_queue("some_queue", "exchange" => "some_exchange")
      @client.register_message("some_message", opts)
      assert_equal({:persistent => true, :queue => "some_queue", :exchange => "some_exchange"}, @client.messages["some_message"])
    end

    test "registering a message should raise a configuration error if it is already configured" do
      opts = {"persistent" => true, "queue" => "some_queue"}
      @client.register_queue("some_queue", "exchange" => "some_exchange")
      @client.register_message("some_message", opts)
      assert_raises(ConfigurationError){ @client.register_message("some_message", opts) }
    end

  end

  class ClientTest < Test::Unit::TestCase
    test "instanciating a client should not instanciate the subscriber/publisher" do
      Publisher.expects(:new).never
      Subscriber.expects(:new).never
      Client.new
    end

    test "should instanciate a subscriber when used for subscribing" do
      Subscriber.expects(:new).returns(stub_everything("subscriber"))
      Client.new.register_handler(:superman, {}, &lambda{})
    end

    test "should instanciate a subscriber when used for publishing" do
      Publisher.expects(:new).returns(stub_everything("subscriber"))
      Client.new.publish(:foo_bar, "payload")
    end

    test "should delegate publishing to the publisher instance" do
      client = Client.new
      args = ["deadletter", "x", {:a => 1}]
      client.send(:publisher).expects(:publish).with(*args)
      client.publish(*args)
    end

    test "should delegate listening to the subscriber instance" do
      client = Client.new
      client.send(:subscriber).expects(:listen)
      client.listen
    end

    test "should delegate stop_listening to the subscriber instance" do
      client = Client.new
      client.send(:subscriber).expects(:stop!)
      client.stop_listening
    end

    test "should delegate handler registration to the subscriber instance" do
      client = Client.new
      client.send(:subscriber).expects(:register_handler)
      client.register_handler("huhu")
    end

    test "should use the configured logger" do
      client = Client.new
      Beetle.config.expects(:logger)
      client.logger
    end

    test "autoload should expand the glob argument and evaluate each file in the client instance" do
      client = Client.new
      File.expects(:read).returns("1+1")
      client.expects(:eval).with("1+1",anything,anything)
      client.autoload("#{File.dirname(__FILE__)}/../../**/client_test.rb")
    end

    test "tracing should put the the subscriber into trace mode and register a handler to each message" do
      client = Client.new
      sub = client.send(:subscriber)
      sub.expects(:trace=).with(true)
      sub.expects(:register_handler).with(client.messages.keys, :ack => true, :key => '#').yields(stub_everything("message"))
      sub.expects(:listen)
      client.stubs(:puts)
      client.trace
    end

  end
end
