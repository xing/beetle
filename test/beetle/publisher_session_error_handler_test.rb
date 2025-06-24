require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class PublisherSessionErrorHandlerTest < Minitest::Test
    BackgroundError = Class.new(StandardError)
    ForegroundError = Class.new(StandardError)
    DelayedError = Class.new(StandardError)

    def setup
      @logger_output = StringIO.new
      @logger = Logger.new(@logger_output)
      @handler = Beetle::PublisherSessionErrorHandler.new(@logger, "test-server")
    end

    test "#raise records the error" do
      background = Thread.new do
        @handler.raise(BackgroundError.new("Background error"))
      end

      wait_until { @handler.exception? }

      assert_raises(BackgroundError) do
        @handler.raise_pending_exception!
      end

      background.join
    end

    test "#raise logs the error" do
      error_message = "Test error"
      @handler.raise(DelayedError.new(error_message))
      assert_match(/Beetle: bunny session handler error. server=test-server/, @logger_output.string)
    end

    test "#raise_pending_exception! raises the recorded error" do
      @handler.raise(ForegroundError.new("Foreground error"))
      assert_raises(ForegroundError) do
        @handler.raise_pending_exception!
      end
    end

    test "#raise_pending_exception! does not raise if no error was recorded" do
      assert_nothing_raised do
        @handler.raise_pending_exception!
      end
    end

    test "#raise_pending_exception! clears the recorded error" do
      @handler.raise(ForegroundError.new("Foreground error"))
      assert_raises(ForegroundError) do
        @handler.raise_pending_exception!
      end

      refute @handler.exception?, "Handler should not have any recorded exceptions after raising"
    end

    test "#clear_exception! returns the arguments for the raise and clears it" do
      @handler.raise(ForegroundError, "Foreground error")
      args = @handler.clear_exception!
      assert_equal [ForegroundError, "Foreground error"], args
    end
  end
end
