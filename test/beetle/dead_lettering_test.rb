require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SetDeadLetterPolicyTest < Minitest::Test
    def setup
      @server = "localhost:15672"
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @dead_lettering = DeadLettering.new(@config)
    end

    test "raises exception when queue name wasn't specified" do
      assert_raises ArgumentError do
        @dead_lettering.set_queue_policy!(@server, "")
      end
    end

    test "raises exception when no server was specified" do
      assert_raises ArgumentError do
        @dead_lettering.set_queue_policy!("", @queue_name)
      end
    end

    test "set_queue_policies! calls set_queue_policy for both target queue and dead letter queue" do
      options = {
        :server => "server", :lazy => true, :dead_lettering => true,
        :queue_name => "QUEUE_NAME", :dead_letter_queue_name => "QUEUE_NAME_dead_letter",
        :message_ttl => 10000
      }
      @dead_lettering.expects(:set_queue_policy!).with("server", "QUEUE_NAME",
                                                       :lazy => true, :dead_lettering => true,
                                                       :routing_key => "QUEUE_NAME_dead_letter")
      @dead_lettering.expects(:set_queue_policy!).with("server", "QUEUE_NAME_dead_letter",
                                                       :lazy => true, :dead_lettering => true,
                                                       :routing_key => "QUEUE_NAME",
                                                       :message_ttl => 10000)
      @dead_lettering.set_queue_policies!(options)
    end

    test "creates a policy by posting to the rabbitmq if dead lettering is enabled" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                 "dead-letter-exchange" => ""
               }}.to_json)
        .to_return(:status => 204)

      @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => false, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "creates a policy by posting to the rabbitmq if lazy queues are enabled" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => false)
    end

    test "raises exception when policy couldn't successfully be created" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => [405])

      assert_raises DeadLettering::FailedRabbitRequest do
        @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => true)
      end
    end

    test "can optionally specify a message ttl" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
                "pattern" => "^QUEUE_NAME$",
                "priority" => 1,
                "apply-to" => "queues",
                "definition" => {
                  "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                  "dead-letter-exchange" => "",
                  "message-ttl" => 10000
                }}.to_json)
        .to_return(:status => 204)

      @dead_lettering.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :message_ttl => 10000, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "properly encodes the vhost from the configuration" do
      stub_request(:put, "http://localhost:15672/api/policies/foo%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                 "dead-letter-exchange" => ""
               }}.to_json)
        .to_return(:status => 204)

      @config.vhost = "foo/"

      @dead_lettering.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")
    end
  end
end
