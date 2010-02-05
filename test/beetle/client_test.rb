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
  end
end
