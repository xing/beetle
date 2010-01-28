require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Bandersnatch
  class ClientTest < Test::Unit::TestCase
    test "instanciating a client should not instanciate the subscriber/publisher" do
      Publisher.expects(:new).never
      Subscriber.expects(:new).never
      Client.new
    end

    test "should instanciate a subscriber when used for subscribing" do
      Subscriber.expects(:new).returns(stub_everything("subscriber"))
      Client.new.subscribe(:foo_bar)
    end

    test "should instanciate a subscriber when used for publishing" do
      Publisher.expects(:new).returns(stub_everything("subscriber"))
      Client.new.publish(:foo_bar, "payload")
    end
  end

  class HandlersTest < Test::Unit::TestCase
    def setup
      @client = Client.new
    end

    test "initially we should have no handlers" do
      assert_equal({}, @client.instance_variable_get("@handlers"))
    end

    test "registering a handler for a message should store it in the configuration with symbolized option keys" do
      opts = {"ack" => true}
      @client.register_handler("some_message", opts){ |*args| 42 }
      opts, block = @client.instance_variable_get("@handlers")["some_message"].first
      assert_equal({:ack => true}, opts)
      assert_equal 42, block.call
    end

    test "should allow registration of multiple handlers for a message" do
      opts = {}
      @client.register_handler("a message", { :queue => "queue_1" } ) { |*args| "handler 1" }
      @client.register_handler("a message", { :queue => "queue_2" }) { |*args| "handler 2" }
      handlers = @client.instance_variable_get("@handlers")["a message"]
      handler1, handler2 = handlers
      assert_equal 2, handlers.size
      assert_equal "queue_1", handler1[0][:queue]
      assert_equal "handler 1", handler1[1].call
      assert_equal "queue_2", handler2[0][:queue]
      assert_equal "handler 2", handler2[1].call
    end
  end
end