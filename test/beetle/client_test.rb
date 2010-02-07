require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class AMQPConfigTest < Test::Unit::TestCase
    def setup
      @client = Client.new
    end

    test "should load default config file" do
      assert_not_nil @client.amqp_config
    end

    test "loading default config file should specify server localhost::5672" do
      assert_equal ["localhost:5672"], @client.servers
    end

    test "default config should specify test and deadletter messages" do
      assert @client.messages.include? "deadletter"
      assert @client.messages.include? "test"
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
