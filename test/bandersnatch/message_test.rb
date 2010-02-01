require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Bandersnatch
  class EncodingTest < Test::Unit::TestCase
    test "a message should encode/decode the message format version correctly" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("server", header, body)
      assert_equal Message::FORMAT_VERSION, m.format_version
    end

    test "a message with uuid should have a uuid and the uuid flag set" do
      body = Message.encode("12345", :with_uuid => true)
      header = mock("header")
      m = Message.new("server", header, body)
      assert m.has_uuid?
      assert_equal(Message::FLAG_UUID, m.flags & Message::FLAG_UUID)
    end

    test "a message without uuid should have a nil uuid and the uuid flag not set" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("server", header, body)
      assert !m.has_uuid?
      assert_equal(0, m.flags & Message::FLAG_UUID)
    end

    test "encoding a message should set an expiration date" do
      Message.expects(:ttl_to_expiration_time).with(17).returns(42)
      body = Message.encode("12345", :ttl => 17)
      header = mock("header")
      m = Message.new("server", header, body)
      assert_equal 42, m.expires_at
    end

    test "encoding a message should set the default expiration date if noe is provided in the call to encode" do
      Message.expects(:ttl_to_expiration_time).with(Message::DEFAULT_TTL).returns(42)
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("server", header, body)
      assert_equal 42, m.expires_at
    end
  end

  class UUIdInsertionTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "no key should be inserted into the database if the message has no uuid" do
      body = Message.encode('my message', :with_uuid => false)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert !message.redundant?

      message.process(lambda {|*args|})

      assert_nil @r.get(message.status_key)
      assert_nil @r.get(message.timeout_key)
      assert_nil @r.get(message.ack_count_key)
    end

    test "processing a redundant message should insert the status key into the database" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert message.redundant?

      message.process(lambda {|*args|})

      assert @r.get(message.status_key)
      assert @r.get(message.ack_count_key)
    end
  end


  class AckingTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "an expired message should be acked without processing" do
      body = Message.encode('my message', :ttl => -1)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)
      assert message.expired?

      processed = :njet
      message.process(lambda {|*args| processed = true})
      assert_equal :njet, processed
    end

    test "a redundant message should be acked after successful processing" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)

      message.expects(:ack!)
      assert message.redundant?
      message.process(lambda {|*args|})
    end

    test "acking a redundant message should increment the ack_count key" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert_equal nil, @r.get(message.ack_count_key)
      message.process(lambda {|*args|})
      assert message.redundant?
      assert_equal 1, @r.get(message.ack_count_key).to_i
    end

    test "acking a redundant message twice should remove the ack_count key" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      header.expects(:ack).twice
      message = Message.new("somequeue", header, body)

      message.process(lambda {|*args|})
      message.process(lambda {|*args|})
      assert message.redundant?
      assert !@r.exists(message.ack_count_key)
    end

  end

  class HandlerAckSequenceTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "a retriable, non redundant message should first run the handler and then be acked" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.retriable = true
      assert message.retriable?
      assert !message.redundant?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      message.process(proc)
    end

    test "a non retriable, non redundant message should run the handler after being acked" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.retriable?
      assert !message.redundant?

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack).in_sequence(s)
      proc.expects(:call).in_sequence(s)
      message.process(proc)
    end

    test "a non retriable, redundant fresh message should run the handler after being acked" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.retriable?
      assert message.redundant?

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack).in_sequence(s)
      proc.expects(:call).in_sequence(s)
      message.process(proc)
    end

    test "a non retriable, redundant, existing message should not run the handler after being acked" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.retriable?
      assert message.redundant?

      # insert the key into the database
      assert !message.key_exists?
      assert message.key_exists?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      message.send(:process_internal, proc)
    end

  end

end
