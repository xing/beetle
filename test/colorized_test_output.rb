# colorized output for Test::Unit / MiniTest
begin
  if RUBY_VERSION < "1.9"
    require 'redgreen'
  else
    module ColorizedDots
      require 'ansi/code'
      def run(runner)
        r = super
        ANSI.ansi(r, ANSI_COLOR_MAPPING[r])
      end
      ANSI_COLOR_MAPPING = Hash.new(:white).merge!('.' => :green, 'S' => :magenta, 'F' => :yellow, 'E' => :red )
    end
    class MiniTest::Unit
      TestCase.send(:include, ColorizedDots)
      def status(io = @@out)
        format = "%d tests, %d assertions, %d failures, %d errors, %d skips"
        color = (errors + failures) > 0 ? :red : :green
        io.puts ANSI.ansi(format % [test_count, assertion_count, failures, errors, skips], color)
      end
    end
  end
rescue LoadError => e
  # do nothing
end if $stdout.tty?
