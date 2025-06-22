require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class PublisherSessionErrorHandlerTest < Minitest::Test
    class DummyPublisher; end
    BackgroundError = Class.new(StandardError)
    ForegroundError = Class.new(StandardError)
    DelayedError = Class.new(StandardError)

    def setup
      @logger_output = StringIO.new
      @logger = Logger.new(@logger_output)
      @handler = Beetle::PublisherSessionErrorHandler.new(@logger, "test-server")
    end

    def test_synchronize_errors_with_recorded_errors_from_background_thread
      background = Thread.new do
        @handler.raise(BackgroundError.new("Background error"))
      end

      sleep 0.5 # ensure that error is recorded while reraising is still false

      assert_raises(BackgroundError) do
        @handler.synchronize_errors do
          assert false, "synchronize_errors was expected to raise previously recorded error"
        end
      end

      background.join
    end

    def test_synchronize_errors_with_errors_from_background_thread_during_reraising
      raise_now = false

      background = Thread.new do
        loop do
          sleep 0.1 # give the main thread time to call synchronize_errors
          break if raise_now
        end
        @handler.raise(BackgroundError.new("Background error"))
      end

      assert_raises(BackgroundError) do
        @handler.synchronize_errors do
          raise_now = true
          sleep 0.5
          assert false, "synchronize_errors was expected to raise"
        end
      end

      background.join
    end

    def test_synchronize_errors_with_errors_from_main_thread
      assert_raises(ForegroundError) do
        @handler.synchronize_errors do
          raise ForegroundError.new("Foreground error")
        end
      end
    end

    def test_synchronize_errors_with_no_errors_succeeds
      assert_nothing_raised do
        result = @handler.synchronize_errors do
          "No errors here"
        end

        assert_equal "No errors here", result
      end
    end

    def test_records_exception_if_not_reraising
      @handler.raise(DelayedError.new("Delayed error"))
      assert @handler.exceptions?

      assert_raises(DelayedError) do
        @handler.synchronize_errors { } # should raise immediately
      end
    end

    def test_does_not_reraise_without_reraising_context
      assert_nothing_raised do
        @handler.raise(DelayedError.new("Should not raise"))
        assert @handler.exceptions?
      end
    end

    def test_reraising_errors_resets_state
      @handler.raise(BackgroundError.new("First"))

      assert_raises(BackgroundError) do
        @handler.synchronize_errors {}
      end

      # after that we should not have any recorded exceptions
      refute @handler.exceptions?

      assert_nothing_raised do
        @handler.synchronize_errors {}
      end
    end

    def test_kills_background_thread
      bg = Thread.new do
        @handler.raise(BackgroundError.new("die!"))
        sleep 0.7
      end

      sleep 0.3
      refute bg.alive?

      bg.join(0.2)
    end

    def test_never_kills_the_thread_in_which_handler_is_created
      th = Thread.new do
        handler = Beetle::PublisherSessionErrorHandler.new(@logger, "test-server")
        sleep 0.1
        handler.raise(DelayedError.new("Should not kill main thread"))
        sleep 1
      end

      assert th.alive?, "Thread should be alive even after raising an error"

      assert_nothing_raised do
        th.join(1) # wait for the thread to finish
      end
    end

    def test_nesting_calls_to_synchronize_errors_prohibited
      assert_raises(Beetle::PublisherSessionErrorHandler::SynchronizationError) do
        @handler.synchronize_errors do
          @handler.synchronize_errors do
            sleep 0.1
          end
        end
      end
    end

    def test_nested_call_error_does_not_change_state_of_synchronization
      @handler.synchronize_errors do
        # now the internal state is that we synchronize
        assert @handler.synchronous_errors?, "Expected to be in synchronized state after first call"
        assert_raises(Beetle::PublisherSessionErrorHandler::SynchronizationError) do
          @handler.synchronize_errors do
            sleep 0.1
          end
        end
        # previous block raised but we still expect to be in the synchronized state
        assert @handler.synchronous_errors?, "Expected to still be in synchronized state after nested call error"
      end
    end

    def test_synchronize_errors_on_different_thread_prohibited
      Thread.report_on_exception = false # prevent the thread from reporting exceptions just for this test
      other_thread = Thread.new do
        @handler.synchronize_errors {}
      end

      assert_raises(Beetle::PublisherSessionErrorHandler::SynchronizationError) do
        other_thread.join # join will re-raise any exception before
      end
    ensure
      Thread.report_on_exception = true # restore the default behavior
    end

    def test_logs_errors
      error_message = "Test error"
      @handler.raise(DelayedError.new(error_message))

      assert_raises(DelayedError) do
        @handler.synchronize_errors {}
      end

      assert_match(/Beetle: bunny session handler error. server=test-server reraise=false/, @logger_output.string)
    end
  end
end
