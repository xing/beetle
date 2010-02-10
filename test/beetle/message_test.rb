require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class EncodingTest < Test::Unit::TestCase
    test "a message should encode/decode the message format version correctly" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal Message::FORMAT_VERSION, m.format_version
    end

    test "a redundantly encoded message should have the redundant flag set on delivery" do
      body = Message.encode("12345", :redundant => true)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert m.redundant?
      assert_equal(Message::FLAG_REDUNDANT, m.flags & Message::FLAG_REDUNDANT)
    end

    test "encoding a message with a specfied time to live should set an expiration time" do
      Message.expects(:ttl_to_expiration_time).with(17).returns(42)
      body = Message.encode("12345", :ttl => 17)
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.expires_at
    end

    test "encoding a message should set the default expiration date if none is provided in the call to encode" do
      Message.expects(:ttl_to_expiration_time).with(Message::DEFAULT_TTL).returns(42)
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("queue", header, body)
      assert_equal 42, m.expires_at
    end
  end

  class KeyManagementTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "successful processing of a non redundant message should delete all keys from the database" do
      body = Message.encode('my message', :redundant => false)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert !message.redundant?

      message.process(lambda {|*args|})

      message.all_keys.each do |key|
        assert !@r.exists(key)
      end
    end

    test "succesful processing of a redundant message twice should delete all keys from the database" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack).twice
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert message.redundant?

      message.process(lambda {|*args|})
      message.process(lambda {|*args|})

      message.all_keys.each do |key|
        assert !@r.exists(key)
      end
    end

    test "successful processing of a redundant message once should insert all but the delay key into the datbase" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert !message.expired?
      assert message.redundant?

      message.process(lambda {|*args|})

      assert @r.exists(message.status_key)
      assert @r.exists(message.execution_attempts_key)
      assert @r.exists(message.timeout_key)
      assert @r.exists(message.ack_count_key)
      assert !@r.exists(message.delay_key)
    end
  end

  class AckingTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "an expired message should be acked without calling the handler" do
      body = Message.encode('my message', :ttl => -1)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)
      assert message.expired?

      processed = :no
      message.process(lambda {|*args| processed = true})
      assert_equal :no, processed
    end

    test "a delayed message should not be acked and the handler should not be called" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack).never
      message = Message.new("somequeue", header, body)
      message.set_delay!
      assert !message.key_exists?
      assert message.delayed?

      processed = :no
      message.process(lambda {|*args| processed = true})
      assert_equal :no, processed
    end

    test "acking a non redundant message should remove the ack_count key" do
      body = Message.encode('my message')
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      message.process(lambda {|*args|})
      assert !message.redundant?
      assert !@r.exists(message.ack_count_key)
    end

    test "a redundant message should be acked after calling the handler" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)

      message.expects(:ack!)
      assert message.redundant?
      message.process(lambda {|*args|})
    end

    test "acking a redundant message should increment the ack_count key" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      header.expects(:ack)
      message = Message.new("somequeue", header, body)

      assert_equal nil, @r.get(message.ack_count_key)
      message.process(lambda {|*args|})
      assert message.redundant?
      assert_equal "1", @r.get(message.ack_count_key)
    end

    test "acking a redundant message twice should remove the ack_count key" do
      body = Message.encode('my message', :redundant => true)
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
      message.attempts_limit = 2
      assert !message.attempts_limit_reached?
      assert !message.redundant?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      message.process(proc)
    end

    test "a non retriable, redundant fresh message should ack after running the handler" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.attempts_limit_reached?
      assert message.redundant?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      message.process(proc)
    end

    test "a non retriable, redundant, existing message should not run the handler after being acked" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.attempts_limit_reached?
      Message::DEFAULT_HANDLER_EXECUTION_ATTEMPTS.times {message.increment_execution_attempts!}
      assert message.attempts_limit_reached?
      assert message.redundant?
      assert !message.completed?
      assert message.timed_out?

      # insert the key into the database
      assert !message.key_exists?
      assert message.key_exists?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      assert_raises(AttemptsLimitReached) { message.send(:process_internal, proc) }
    end

    test "a retriable, redundant, fresh message should be acked after running the handler, and the ack count should be 1, and the status should be completed" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.timeout = 10.seconds
      assert !message.attempts_limit_reached?
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
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.timeout = 10.seconds
      assert !message.attempts_limit_reached?
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
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.timeout = 10.seconds
      assert message.redundant?
      message.completed!

      proc = mock("proc")
      s = sequence("s")
      header.expects(:ack)
      proc.expects(:call).never
      message.__send__(:process_internal, proc)
      assert message.timed_out?
    end

    test "a message which has not reached its execution attempt limit, redundant, existing, incomplete, timed out should be processed again" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.timeout = 0
      assert !message.key_exists?
      assert message.key_exists?
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      assert message.redundant?
      assert !message.completed?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      message.__send__(:process_internal, proc)
      assert message.completed?
    end

    test "a message which has not reached its execution attempt limit, redundant, existing, incomplete, not yet timed out should be processed later" do
      body = Message.encode('my message', :redundant => true)
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.timeout = Time.now.to_i + 10.seconds
      message.set_timeout!
      assert !message.key_exists?
      assert message.key_exists?
      assert !message.timed_out?
      assert !message.attempts_limit_reached?
      assert message.redundant?
      assert !message.completed?

      proc = mock("proc")
      proc.expects(:call).never
      header.expects(:ack).never
      assert_raises(HandlerNotYetTimedOut){ message.__send__(:process_internal, proc) }
      assert !message.completed?
    end

  end

  class ProcessingTest < Test::Unit::TestCase

    test "processing a message catches exceptions risen by process_internal and reraises them" do
      body = Message.encode('my message', :redundant => true)
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

  class SettingsTest < Test::Unit::TestCase
    def setup
      @r = Message.redis
      @r.flushdb
    end

    test "completed! should store the status 'complete' in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert !message.completed?
      message.completed!
      assert message.completed?
      assert_equal "completed", @r.get(message.status_key)
    end

    test "set_delay! should store the current time plus the number of delayed seconds in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.delay = 1
      message.expects(:now).returns(1)
      message.set_delay!
      assert_equal "2", @r.get(message.delay_key)
      message.expects(:now).returns(2)
      assert !message.delayed?
      message.expects(:now).returns(0)
      assert message.delayed?
    end

    test "set_delay! should use the default delay if the delay hasn't been set on the message instance" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.expects(:now).returns(0)
      message.set_delay!
      assert_equal "#{Message::DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY}", @r.get(message.delay_key)
      message.expects(:now).returns(message.delay)
      assert !message.delayed?
      message.expects(:now).returns(0)
      assert message.delayed?
    end

    test "set_timeout! should store the current time plus the number of timeout seconds in the database" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.timeout = 1
      message.expects(:now).returns(1)
      message.set_timeout!
      assert_equal "2", @r.get(message.timeout_key)
      message.expects(:now).returns(2)
      assert !message.timed_out?
      message.expects(:now).returns(3)
      assert message.timed_out?
    end

    test "set_timeout! should use the default timeout if the timeout hasn't been set on the message instance" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.expects(:now).returns(0)
      message.set_timeout!
      assert_equal "#{Message::DEFAULT_HANDLER_TIMEOUT}", @r.get(message.timeout_key)
      message.expects(:now).returns(message.timeout)
      assert !message.timed_out?
      message.expects(:now).returns(Message::DEFAULT_HANDLER_TIMEOUT+1)
      assert message.timed_out?
    end

    test "incrementing execution attempts should increment by 1" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      assert_equal 1, message.increment_execution_attempts!
      assert_equal 2, message.increment_execution_attempts!
      assert_equal 3, message.increment_execution_attempts!
    end

    test "attempts limit should be reached after incrementing the attempt limit counter 'attempts limit' times" do
      body = Message.encode('my message')
      header = mock("header")
      message = Message.new("somequeue", header, body)
      message.attempts_limit = 2
      assert !message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert !message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert message.attempts_limit_reached?
      message.increment_execution_attempts!
      assert message.attempts_limit_reached?
    end

  end
end

