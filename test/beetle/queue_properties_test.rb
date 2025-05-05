require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RabbitMQApiConnectionTest < Minitest::Spec
    let(:server) { "example.com:5672" }
    let(:config) { Configuration.new }
    let(:server_connection_options) { {} }
    let(:queue_properties) { QueueProperties.new(config) }
    let(:request_uri) { URI("http://#{server}/api/test") }
    let(:request) { Net::HTTP::Get.new(request_uri) }

    before do
      config.logger = Logger.new("/dev/null")
      config.servers = server 
      config.server_connection_options = server_connection_options
    end

    describe "when no server_connection_options are set" do
      test "uses default credentials and derives correct api port" do
        stub = stub_request(:get, "http://example.com:15672/api/test")
                 .with(basic_auth: ['guest', 'guest'])
                 .to_return(status: 200)

        queue_properties.run_api_request(server, Net::HTTP::Get, "/api/test")

        assert_requested(stub)
      end
    end

    describe "when server_connection_options are set" do
      let(:server) { "other.example.com:5671" }
      let(:server_connection_options) { { "other.example.com:5671" => { user: "john", pass: "doe"} } }

      test "uses credentials from server_connection_options and derives correct api port" do
        stub = stub_request(:get, "http://other.example.com:15671/api/test")
                 .with(basic_auth: ['john', 'doe'])
                 .to_return(status: 200)

        queue_properties.run_api_request(server, Net::HTTP::Get, "/api/test")

        assert_requested(stub)
      end
    end

    describe "when server does not specify a port" do
      let(:server) { "noport.example.com" }

      test "derives correct api port" do
        stub = stub_request(:get, "http://noport.example.com:15672/api/test").to_return(status: 200)

        queue_properties.run_api_request(server, Net::HTTP::Get, "/api/test")

        assert_requested(stub)
      end
    end
  end

  class ApplyDefaultAttributesTest < Minitest::Test 
    def setup
      @server = "localhost:5672"
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @config.beetle_policy_default_attributes = { classic: { "max-length" => 8_000_000, "overflow" => "reject-publish" }, quorum: { } }
      @queue_properties = QueueProperties.new(@config)
    end

    test "applies default attributes to the queue" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub = stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "max-length" => 8_000_000,
                "overflow" => "reject-publish",
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @queue_properties.set_queue_policy!(@server, @queue_name, lazy: true)
      assert_requested(stub)
    end
  end

  class SetPolicyPriorityTest < Minitest::Test 
    def setup
      @server = "localhost:5672"
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @config.beetle_policy_priority = 2
      @queue_properties = QueueProperties.new(@config)
    end

    test "applies default attributes to the queue" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub = stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 2,
               "apply-to" => "queues",
               "definition" => {
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @queue_properties.set_queue_policy!(@server, @queue_name, lazy: true)
      assert_requested(stub)
    end
  end

  class SelectApplyToTest < Minitest::Test 
    def setup
      @server = "localhost:5672"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @queue_properties = QueueProperties.new(@config)
    end

    def generate_queue_name
      "TEST_QUEUE_NAME_#{rand(1000)}"
    end

    test "when queue type is nil, apply-to is `queues`" do
      queue_name = generate_queue_name

      stub_request(:get, "http://localhost:15672/api/policies/%2F/#{queue_name}_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub = stub_request(:put, "http://localhost:15672/api/policies/%2F/#{queue_name}_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^#{queue_name}$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @queue_properties.set_queue_policy!(@server, queue_name, lazy: true)
      assert_requested(stub)
    end

    test "when queue type is classic, apply-to is `queues`" do
      queue_name = generate_queue_name

      stub_request(:get, "http://localhost:15672/api/policies/%2F/#{queue_name}_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub = stub_request(:put, "http://localhost:15672/api/policies/%2F/#{queue_name}_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^#{queue_name}$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @queue_properties.set_queue_policy!(@server, queue_name, lazy: true, queue_type: :classic)
      assert_requested(stub)
    end

    test "when queue type is quorum, apply-to is `quorum_queues`" do
      queue_name = generate_queue_name

      stub_request(:get, "http://localhost:15672/api/policies/%2F/#{queue_name}_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub = stub_request(:put, "http://localhost:15672/api/policies/%2F/#{queue_name}_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^#{queue_name}$",
               "priority" => 1,
               "apply-to" => "quorum_queues",
               "definition" => {
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @queue_properties.set_queue_policy!(@server, queue_name, lazy: true, queue_type: :quorum)
      assert_requested(stub)
    end
     
  end

  class SetDeadLetterPolicyTest < Minitest::Test
    def setup
      @server = "localhost:5672"
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @queue_properties = QueueProperties.new(@config)
    end

    test "raises exception when queue name wasn't specified" do
      assert_raises ArgumentError do
        @queue_properties.set_queue_policy!(server: "localhost:5672", queue_name: "QUEUE_NAME")
      end
    end

    test "raises exception when no server was specified" do
      assert_raises ArgumentError do
        @queue_properties.set_queue_policy!("", @queue_name)
      end
    end

    test "update_queue_properties! calls set_queue_policy for both target queue and dead letter queue" do
      options = {
        :server => "server", :lazy => true, :dead_lettering => true,
        :queue_name => "QUEUE_NAME", :dead_letter_queue_name => "QUEUE_NAME_dead_letter",
        :message_ttl => 10000
      }

      policies = sequence('policies')
      @queue_properties.expects(:set_queue_policy!).in_sequence(policies).with("server", "QUEUE_NAME_dead_letter",
                                                       :lazy => true, :dead_lettering => true,
                                                       :routing_key => "QUEUE_NAME",
                                                       :message_ttl => 10000)
      @queue_properties.expects(:set_queue_policy!).in_sequence(policies).with("server", "QUEUE_NAME",
                                                       :lazy => true, :dead_lettering => true,
                                                       :routing_key => "QUEUE_NAME_dead_letter")
      @queue_properties.update_queue_properties!(options)
    end

    test "creates a policy by posting to the rabbitmq if dead lettering is enabled" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub = stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
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

      @queue_properties.set_queue_policy!(@server, @queue_name, :lazy => false, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")

      assert_requested(stub)
    end

    test "skips the PUT call to rabbitmq if the policy is already defined as desired" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200,
                   :body => {
                     "vhost" => "/",
                     "name" => "QUEUE_NAME_policy",
                     "pattern" => "^QUEUE_NAME$",
                     "priority" => 1,
                     "apply-to" => "queues",
                     "definition" => {
                       "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                       "dead-letter-exchange" => ""
                     }}.to_json)

      @queue_properties.set_queue_policy!(@server, @queue_name, :lazy => false, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "deletes policy if its definition corresponds to the broker default policy" do
      @config.broker_default_policy = { "queue-mode" => "lazy" }
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200,
                   :body => {
                     "vhost" => "/",
                     "name" => "QUEUE_NAME_policy",
                     "pattern" => "^QUEUE_NAME$",
                     "priority" => 1,
                     "apply-to" => "queues",
                     "definition" => {
                       "queue-mode" => "lazy",
                     }}.to_json)
      stub_request(:delete, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 204)

      @queue_properties.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => false, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "does nothing if its definition corresponds to the broker default policy and the policy does not exist on the server" do
      @config.broker_default_policy = { "queue-mode" => "lazy" }
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      @queue_properties.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => false, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "creates a policy by posting to the rabbitmq if lazy queues are enabled" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

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

      @queue_properties.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => false)
    end

    test "raises exception when policy couldn't successfully be created" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => [405])

      assert_raises QueueProperties::FailedRabbitRequest do
        @queue_properties.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => true)
      end
    end

    test "can optionally specify a message ttl" do
      stub_request(:get, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

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

      @queue_properties.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :message_ttl => 10000, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "properly encodes the vhost from the configuration" do
      stub_request(:get, "http://localhost:15672/api/policies/foo%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 404)

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

      @queue_properties.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "update_queue_properties! calls remove_obsolete_bindings if bindings are part of the options hash" do
      bindings = [{:exchange => "foo", :key => "a.b.c"}]
      options = {
        :server => "server", :lazy => true, :dead_lettering => true,
        :queue_name => "QUEUE_NAME", :dead_letter_queue_name => "QUEUE_NAME_dead_letter",
        :message_ttl => 10000,
        :bindings => bindings
      }
      @queue_properties.expects(:set_queue_policy!).twice
      @queue_properties.expects(:remove_obsolete_bindings).with("server", "QUEUE_NAME", bindings)
      @queue_properties.update_queue_properties!(options)
    end

    test "remove_obsolete_bindings removes an obsolete binding but does not remove the default binding" do
      bindings = [{:exchange => "foo", :key => "QUEUE_NAME"}, {:exchange => "foo", :key => "a.b.c"}]
      stub_request(:get, "http://localhost:15672/api/queues/%2F/QUEUE_NAME/bindings")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200,
                   :body =>[
                     {
                       "destination_type" => "queue",
                       "source" => "",
                       "routing_key" => "QUEUE_NAME",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "QUEUE_NAME",
                       "arguments" => {}
                     },
                     {
                       "destination_type" => "queue",
                       "source" => "foo",
                       "routing_key" => "QUEUE_NAME",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "QUEUE_NAME",
                       "arguments" => {}
                     },
                     {
                       "destination_type" => "queue",
                       "source" => "foo",
                       "routing_key" => "a.b.c",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "a.b.c",
                       "arguments" => {}
                     },
                     {
                       "destination_type" => "queue",
                       "source" => "foofoo",
                       "routing_key" => "x.y.z",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "x.y.z",
                       "arguments" => {}
                     }
                   ].to_json)

      stub_request(:delete, "http://localhost:15672/api/bindings/%2F/e/foofoo/q/QUEUE_NAME/x.y.z")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200)

      @queue_properties.remove_obsolete_bindings(@server, "QUEUE_NAME", bindings)
    end

    test "raises an error when bindings cannot be retrieved" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F/QUEUE_NAME/bindings")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 500)
      assert_raises(Beetle::QueueProperties::FailedRabbitRequest) { @queue_properties.remove_obsolete_bindings(@server, "QUEUE_NAME", []) }
    end

    test "raises an error when bindings cannot be deleted" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F/QUEUE_NAME/bindings")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200, :body => [
                     {
                       "destination_type" => "queue",
                       "source" => "foofoo",
                       "routing_key" => "x.y.z",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "x.y.z",
                       "arguments" => {}
                     }
                   ].to_json)
      stub_request(:delete, "http://localhost:15672/api/bindings/%2F/e/foofoo/q/QUEUE_NAME/x.y.z")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 500)

      assert_raises(Beetle::QueueProperties::FailedRabbitRequest) { @queue_properties.remove_obsolete_bindings(@server, "QUEUE_NAME", []) }
    end

  end
end
