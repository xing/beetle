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
      assert_equal "1", @r.get(message.ack_count_key)
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

    test "a retriable, redundant, fresh message should be acked after running the handler, and the ack count should be 1, and the status should be completed" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.retriable = true
      message.timeout = 10.seconds
      assert message.retriable?
      assert message.redundant?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      message.expects(:completed!).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      message.__send__(:process_internal, proc)
      assert_equal "1", @r.get(message.ack_count_key)
    end

    test "a retriable, redundant, fresh message should not be acked if running the handler crashes, the status should be incomplete and the timeout should be 0" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.retriable = true
      message.timeout = 10.seconds
      assert message.retriable?
      assert message.redundant?

      proc = lambda {|*args| raise "crash"}
      s = sequence("s")
      message.expects(:completed!).never
      header.expects(:ack).never
      assert_raises(HandlerCrash) { message.__send__(:process_internal, proc) }
      assert message.timed_out?
      assert !message.completed?
    end

    test "a retriable, redundant, existing message should be just acked if the status is complete" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.retriable = true
      message.timeout = 10.seconds
      assert message.retriable?
      assert message.redundant?
      message.completed!

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack)
      proc.expects(:call).never
      message.__send__(:process_internal, proc)
      assert message.timed_out?
    end

    test "a retriable, redundant, existing, incomplete, timed out message should be processed again" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.retriable = true
      message.timeout = 0
      assert !message.key_exists?
      assert message.key_exists?
      assert message.timed_out?
      assert message.retriable?
      assert message.redundant?
      assert !message.completed?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      message.__send__(:process_internal, proc)
      assert message.completed?
    end

    test "a retriable, redundant, existing, incomplete, not yet timed out message should be processed later" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.retriable = true
      message.timeout = Time.now.to_i + 10.seconds
      message.set_timeout!
      assert !message.key_exists?
      assert message.key_exists?
      assert !message.timed_out?
      assert message.retriable?
      assert message.redundant?
      assert !message.completed?

      proc = mock("proc")
      proc.expects(:call).never
      header.expects(:ack).never
      assert_raises(HandlerTimeout){ message.__send__(:process_internal, proc) }
      assert !message.completed?
    end

  end

  class ProcessingTest < Test::Unit::TestCase

    test "processing a message catches exceptions risen by process_internal and reraises them" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      e = Exception.new
      e2 = nil
      message.expects(:process_internal).raises(e)
      begin
        message.process(1)
      rescue Exception => e2
      end
      assert_equal e, e2
    end
  end

  class SettingCompletionStatusTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "completed! should store the status 'complete' in the database" do
      body = Message.encode('my message', :with_uuid => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.completed?
      message.completed!
      assert message.completed?
      assert_equal "completed", @r.get(message.status_key)
    end
  end
end

