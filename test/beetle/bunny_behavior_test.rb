require 'timeout'
require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class BunnyBehaviorTest < Minitest::Test

  test "publishing fixnums and hashes works in amqp headers" do
    client = Beetle::Client.new
    client.register_queue(:test)
    client.register_message(:test)
    # purge the test queue
    client.purge(:test)
    # empty the dedup store
    client.deduplication_store.flushdb
    # register our handler to the message, check out the message.rb for more stuff you can get from the message object
    message = nil
    client.register_handler(:test) {|msg| message = msg; client.stop_listening }
    # publish our message (NOTE: empty message bodies don't work, most likely due to bugs in bunny/amqp)
    published = client.publish(:test, 'bam', headers: { foo: 1, table: {bar: "baz"}})
    # start listening
    client.listen
    client.stop_publishing
    assert_equal 1, published
    assert_equal "bam", message.data
    headers = message.header.attributes[:headers]
    assert_equal 1, headers["foo"]
    assert_equal({"bar" => "baz"}, headers["table"])
  end

  test "publishing redundantly does not leave the garbage in dedup store" do
    Beetle.config.servers = "localhost:5672,localhost:5673"
    client = Beetle::Client.new
    client.register_queue(:test_garbage)
    client.register_message(:test_garbage)
    # purge the test queue
    client.purge(:test_garbage)
    # empty the dedup store
    client.deduplication_store.flushdb

    handler = TestHandler.new(2, client = client)
    client.register_handler(:test_garbage, handler)
    published = client.publish(:test_garbage, 'bam', :redundant =>true)
    listen(client)
    client.stop_publishing

    messages_processed = handler.messages_processed
    assert_equal 1, messages_processed.length
    message = messages_processed.first
    assert_equal 2, published
    assert_equal "bam", message.data
    Beetle::DeduplicationStore::KEY_SUFFIXES.each do |suffix|
      assert_equal false, client.deduplication_store.exists(message.msg_id, suffix)
    end
  end

  test "process redundant message once" do
    Beetle.config.servers = "localhost:5672,localhost:5673"
    client = Beetle::Client.new
    client.register_queue(:test_processing)
    client.register_message(:test_processing)
    # purge the test queue
    client.purge(:test_processing)
    # empty the dedup store
    client.deduplication_store.flushdb

    handler = TestHandler.new(2, client = client)
    client.register_handler(:test_processing, handler)
    published = client.publish(:test_processing, 'bam', :redundant =>true)
    listen(client)
    client.stop_publishing

    messages_processed = handler.messages_processed
    assert_equal 1, messages_processed.length
    message = messages_processed.first
    assert_equal 2, published
    assert_equal "bam", message.data
    assert_equal 2, handler.post_process_invocations
    assert_equal 2, handler.pre_process_invocations
  end

  test "publishing redundantly to a single broker does not leave the garbage in dedup store and fallback to simple sending" do
    Beetle.config.servers = "localhost:5672"
    client = Beetle::Client.new
    client.register_queue(:test_single)
    client.register_message(:test_single)
    # purge the test queue
    client.purge(:test_single)
    # empty the dedup store
    client.deduplication_store.flushdb

    message = nil
    client.register_handler(:test_single) {|msg| message = msg; client.stop_listening }

    published = client.publish(:test_single, 'bam', :redundant =>true)
    listen(client)
    client.stop_publishing

    assert_equal 1, published
    assert_equal "bam", message.data
    Beetle::DeduplicationStore::KEY_SUFFIXES.map do |suffix|
      assert_equal false, client.deduplication_store.exists(message.msg_id, suffix)
    end
  end

  test "publishing with confirms works as expected" do
    Beetle.config.servers = "localhost:5672"
    client = Beetle::Client.new
    client.register_queue(:test_publisher_confirms)
    client.register_message(:test_publisher_confirms, :publisher_confirms => true)
    # purge the test queue
    client.purge(:test_publisher_confirms)

    message = nil
    client.register_handler(:test_publisher_confirms) {|msg| message = msg; client.stop_listening }

    published = client.publish(:test_publisher_confirms, 'bam')
    listen(client)
    client.stop_publishing

    assert_equal 1, published
    assert_equal "bam", message.data
  end

  test "auto-recovery sleep is disabled" do
    Beetle.config.servers = "localhost:5672"
    client = Beetle::Client.new
    client.register_message(:test_network)

    bunny = client.send(:publisher).send(:bunny)
    transport = bunny.transport

    def transport.closed?
      true
    end

    def transport.open?
      false
    end

    begin
      Timeout.timeout(1) do
        transport.send_frame(AMQ::Protocol::Channel::Open.encode(1, AMQ::Protocol::EMPTY_STRING))
      end
    rescue Timeout::Error
      assert false, "Transport should not timeout when auto-recovery sleep is disabled"
    end
  end

  def listen(client, timeout = 1)
    Timeout.timeout(timeout) do
      client.listen
    end
  rescue Timeout::Error
    puts "Client listen timed out after #{timeout} seconds"
    nil
  end

  class TestHandler < Beetle::Handler

    attr_reader :messages_processed, :pre_process_invocations, :post_process_invocations

    def initialize(stop_listening_after_n_post_processes, client)
      super()
      @stop_listening_after_n_post_processes = stop_listening_after_n_post_processes
      @client = client
      @post_process_invocations = 0
      @pre_process_invocations = 0
      @messages_processed = []
    end

    def pre_process(_message)
      @pre_process_invocations += 1
    end

    def process
      @messages_processed << message
    end

    def post_process
      @post_process_invocations += 1
      return unless @post_process_invocations >= @stop_listening_after_n_post_processes
      @client.stop_listening
    end

  end

end
