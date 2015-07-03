require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SetDeadLetterQueuesTest < MiniTest::Unit::TestCase
    test "creates a dead letter queue for each server" do
      servers = %w(a b)

      DeadLetterQueue.expects(:set_dead_letter_queue!).
        with("a", "QUEUE_NAME", :message_ttl => 10000)
      DeadLetterQueue.expects(:set_dead_letter_queue!).
        with("b", "QUEUE_NAME", :message_ttl => 10000)

      DeadLetterQueue.set_dead_letter_queues!(servers, "QUEUE_NAME", :message_ttl => 10000)
    end
  end

  class SetDeadLetterQueueTest < MiniTest::Unit::TestCase
    def setup
      @server = "localhost:15672"
      @queue_name = "QUEUE_NAME"
    end

    test "raises exception when queue name wasn't specified" do
      assert_raises ArgumentError do
        DeadLetterQueue.set_dead_letter_queue!(@server, "")
      end
    end

    test "raises exception when no server was specified" do
      assert_raises ArgumentError do
        DeadLetterQueue.set_dead_letter_queue!("", @queue_name)
      end
    end

    test "creates a policy by posting to the rabbitmq" do
      stub_request(:put, "http://guest:guest@localhost:15672/api/policies/%2F/QUEUE_NAME_policy").
        with(:body => {
        "pattern" => "^QUEUE_NAME$",
        "priority" => 1,
        "apply-to" => "queues",
        "definition" => {
          "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
          "dead-letter-exchange" => ""
        }}.to_json).
        to_return(:status => 204)

      DeadLetterQueue.set_dead_letter_queue!(@server, @queue_name)
    end

    test "raises exception when policy couldn't successfully be created" do
      stub_request(:put, "http://guest:guest@localhost:15672/api/policies/%2F/QUEUE_NAME_policy").
        to_return(:status => [405])

      assert_raises DeadLetterQueue::FailedRabbitRequest do
        DeadLetterQueue.set_dead_letter_queue!(@server, @queue_name)
      end
    end

    test "can optionally specify a message ttl" do
      stub_request(:put, "http://guest:guest@localhost:15672/api/policies/%2F/QUEUE_NAME_policy").
        with(:body => {
        "pattern" => "^QUEUE_NAME$",
        "priority" => 1,
        "apply-to" => "queues",
        "definition" => {
          "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
          "dead-letter-exchange" => "",
          "message-ttl" => 10000
        }}.to_json).
        to_return(:status => 204)

      DeadLetterQueue.set_dead_letter_queue!(@server, @queue_name, :message_ttl => 10000)
    end
  end
end
