require File.expand_path(File.dirname(__FILE__) + '/test_helper')


module Bandersnatch
  class SubscriberQueueManagementTest < Test::Unit::TestCase
    def setup
      @sub = Subscriber.new
    end

    test "initially there should be no queues for the current server" do
      assert_equal({}, @sub.queues)
      assert !@sub.queues["some_queue"]
    end

    test "binding a queue should create it using the config and bind it to the exchange with the name specified" do
      @sub.register_queue("some_queue", "durable" => true, "exchange" => "some_exchange", "key" => "haha.#")
      @sub.expects(:exchange).with("some_exchange").returns(:the_exchange)
      q = mock("queue")
      q.expects(:bind).with(:the_exchange, {:key => "haha.#"})
      m = mock("MQ")
      m.expects(:queue).with("some_queue", :durable => true).returns(q)
      @sub.expects(:mq).returns(m)

      @sub.bind_queue("some_queue")
      assert_equal q, @sub.queues["some_queue"]
    end
  end
end