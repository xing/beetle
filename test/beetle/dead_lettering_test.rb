require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SetDeadLetteringsTest < Minitest::Test
    def setup
      @config = Configuration.new
      @client = Client.new @config
      @dead_lettering = DeadLettering.new(@client)
      @config.dead_lettering_enabled = true
    end

    test "creates a dead letter queue for each server" do
      servers = %w(a b)

      @dead_lettering.expects(:set_queue_policy!).
        with("a", "QUEUE_NAME", :message_ttl => 10000)
      @dead_lettering.expects(:set_queue_policy!).
        with("b", "QUEUE_NAME", :message_ttl => 10000)

      @dead_lettering.set_queue_policies!(servers, "QUEUE_NAME", :message_ttl => 10000)
    end
  end

  class SetDeadLetterPolicyTest < Minitest::Test
    def setup
      @server = "localhost:15672"
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @client = Client.new @config
      @config.logger = Logger.new("/dev/null")
      @dead_lettering = DeadLettering.new(@client)
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

      @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => false, :dead_lettering => true)
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

      @dead_lettering.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :message_ttl => 10000)
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

      @dead_lettering.set_queue_policy!(@server, @queue_name, :dead_lettering => true)
    end
  end

  class BindDeadLetterQueuesTest < Minitest::Test
    def setup
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @client = Client.new @config
      @config.logger = Logger.new("/dev/null")
      @dead_lettering = DeadLettering.new(@client)
      @servers = ["localhost:55672"]
    end

    test "is does not call out to rabbit if neither dead lettering nor lazy queues are enabled" do
      @client.register_queue(@queue_name, :dead_lettering => false, :lazy => false)
      channel = stub('channel')
      @dead_lettering.expects(:run_rabbit_http_request).never
      @dead_lettering.bind_dead_letter_queues!(channel, @servers, @queue_name)
    end

    test "creates and connects the dead letter queue via policies when enabled" do
      @client.register_queue(@queue_name, :dead_lettering => true, :lazy => false)

      channel = stub('channel')

      channel.expects(:queue).with("#{@queue_name}_dead_letter", {})
      @dead_lettering.expects(:set_queue_policies!).with(@servers, @queue_name,  :dead_lettering => true, :lazy => false)
      @dead_lettering.expects(:set_queue_policies!).with(@servers, "#{@queue_name}_dead_letter",
        :routing_key => @queue_name,
        :message_ttl => 1000,
        :dead_lettering => true,
        :lazy => false
      )

      @dead_lettering.bind_dead_letter_queues!(channel, @servers, @queue_name)
    end
  end
end
