require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SetDeadLetteringsTest < Minitest::Test
    def setup
      @dead_lettering = DeadLettering.new(Configuration.new)
    end

    test "creates a dead letter queue for each server" do
      servers = %w(a b)

      @dead_lettering.expects(:set_dead_letter_policy!).
        with("a", "QUEUE_NAME", :message_ttl => 10000)
      @dead_lettering.expects(:set_dead_letter_policy!).
        with("b", "QUEUE_NAME", :message_ttl => 10000)

      @dead_lettering.set_dead_letter_policies!(servers, "QUEUE_NAME", :message_ttl => 10000)
    end
  end

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
        @dead_lettering.set_dead_letter_policy!(@server, "")
      end
    end

    test "raises exception when no server was specified" do
      assert_raises ArgumentError do
        @dead_lettering.set_dead_letter_policy!("", @queue_name)
      end
    end

    test "creates a policy by posting to the rabbitmq" do
      stub_request(:put, "http://#{@server}/api/policies/%2F/QUEUE_NAME_policy")
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

      @dead_lettering.set_dead_letter_policy!(@server, @queue_name)
    end

    test "raises exception when policy couldn't successfully be created" do
      stub_request(:put, "http://#{@server}/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => [405])

      assert_raises DeadLettering::FailedRabbitRequest do
        @dead_lettering.set_dead_letter_policy!(@server, @queue_name)
      end
    end

    test "can optionally specify a message ttl" do
      stub_request(:put, "http://#{@server}/api/policies/%2F/QUEUE_NAME_policy")
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

      @dead_lettering.set_dead_letter_policy!(@server, @queue_name, :message_ttl => 10000)
    end

    test "properly encodes the vhost from the configuration" do
      stub_request(:put, "http://#{@server}/api/policies/foo%2F/QUEUE_NAME_policy")
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

      @dead_lettering.set_dead_letter_policy!(@server, @queue_name)
    end
  end

  class BindDeadLetterQueuesTest < Minitest::Test
    def setup
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @dead_lettering = DeadLettering.new(@config)
      @servers = ["#{ENV['RABBITMQ_HOST'] || 'localhost'}:55672"]
    end

    test "is turned off by default" do
      channel = stub('channel')
      @dead_lettering.expects(:set_dead_letter_policies!).never
      @dead_lettering.bind_dead_letter_queues!(channel, @servers, @queue_name)
    end

    test "creates and connects the dead letter queue via policies when enabled" do
      @config.dead_lettering_enabled = true

      channel = stub('channel')

      channel.expects(:queue).with("#{@queue_name}_dead_letter", {})
      @dead_lettering.expects(:set_dead_letter_policies!).with(@servers, @queue_name)
      @dead_lettering.expects(:set_dead_letter_policies!).with(@servers, "#{@queue_name}_dead_letter",
        :routing_key => @queue_name,
        :message_ttl => 1000
      )

      @dead_lettering.bind_dead_letter_queues!(channel, @servers, @queue_name)
    end
  end
end
