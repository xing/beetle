# frozen_string_literal: true

require "mkmf"

class HiredisConnectionExtconf
  def initialize(debug)
    @debug = debug
  end

  def configure
    if RUBY_ENGINE == "ruby" && !Gem.win_platform?
      configure_extension
      create_makefile("redis_client/hiredis_connection")
    else
      File.write("Makefile", dummy_makefile($srcdir).join)
    end
  end

  def configure_extension
    build_hiredis

    have_func("rb_hash_new_capa", "ruby.h")

    $CFLAGS = concat_flags($CFLAGS, "-I#{hiredis_dir}", "-std=c99", "-fvisibility=hidden")
    $CFLAGS = if @debug
      concat_flags($CFLAGS, "-Werror", "-g", RbConfig::CONFIG["debugflags"])
    else
      concat_flags($CFLAGS, "-O3")
    end

    if @debug
      $CPPFLAGS = concat_flags($CPPFLAGS, "-DRUBY_DEBUG=1")
    end

    append_cflags("-Wno-declaration-after-statement") # Older compilers
    append_cflags("-Wno-compound-token-split-by-macro") # Older rubies on macos
  end

  def build_hiredis
    env = {
      "USE_SSL" => 1,
      "CFLAGS" => concat_flags(ENV["CFLAGS"], "-fvisibility=hidden"),
    }
    env["OPTIMIZATION"] = "-g" if @debug

    env = configure_openssl(env)

    env_args = env.map { |k, v| "#{k}=#{v}" }
    Dir.chdir(hiredis_dir) do
      unless system(*Shellwords.split(make_program), "static", *env_args)
        raise "Building hiredis failed"
      end
    end

    $LDFLAGS = concat_flags($LDFLAGS, "-lssl", "-lcrypto")
    $libs = concat_flags($libs, "#{hiredis_dir}/libhiredis.a", "#{hiredis_dir}/libhiredis_ssl.a")
  end

  def configure_openssl(original_env)
    original_env.dup.tap do |env|
      config = dir_config("openssl")
      if config.none?
        config = dir_config("opt").map { |c| detect_openssl_dir(c) }
      end

      unless have_header("openssl/ssl.h")
        message = "ERROR: OpenSSL library could not be found."
        if config.none?
          message += "\nUse --with-openssl-dir=<dir> option to specify the prefix where OpenSSL is installed."
        end
        abort message
      end

      if config.any?
        env["CFLAGS"] = concat_flags(env["CFLAGS"], "-I#{config.first}")
        env["SSL_LDFLAGS"] = "-L#{config.last}"
      end
    end
  end

  private

  def detect_openssl_dir(paths)
    paths
      &.split(File::PATH_SEPARATOR)
      &.detect { |dir| dir.include?("openssl") }
  end

  def concat_flags(*args)
    args.compact.join(" ")
  end

  def hiredis_dir
    File.expand_path('vendor', __dir__)
  end

  def make_program
    with_config("make-prog", ENV["MAKE"]) ||
      case RUBY_PLATFORM
      when /(bsd|solaris)/
        'gmake'
      else
        'make'
      end
  end
end

HiredisConnectionExtconf.new(ENV["EXT_PEDANTIC"]).configure
