require 'rake'
require 'rake/testtask'
require 'lib/beetle'
require 'rcov/rcovtask'

namespace :test do
  namespace :coverage do
    desc "Delete aggregate coverage data."
    task(:clean) { rm_f "coverage.data" }
  end

  desc 'Aggregate code coverage'
  task :coverage => "test:coverage:clean"

  Rcov::RcovTask.new(:coverage) do |t|
    t.libs << "test"
    t.test_files = FileList["test/**/*_test.rb"]
    t.output_dir = "test/coverage"
    t.verbose = true
    t.rcov_opts << "--exclude '.*' --include-file 'lib/beetle/'"
  end
  task :coverage do
    system 'open test/coverage/index.html'
  end if RUBY_PLATFORM =~ /darwin/
end


namespace :beetle do
  task :test do
    Beetle::Client.new.test
  end

  task :trace do
    trap('INT'){ EM.stop_event_loop }
    Beetle::Client.new.trace
  end
end

namespace :rabbit do
  def start(node_name, port)
    script = File.expand_path(File.dirname(__FILE__)+"/script/start_rabbit")
    puts "starting rabbit #{node_name} on port #{port}"
    puts "type ^C a RETURN to abort"
    sleep 1
    exec "sudo #{script} #{node_name} #{port}"
  end
  desc "start rabbit instance 1"
  task :start1 do
    start "rabbit1", 5672
  end
  desc "start rabbit instance 2"
  task :start2 do
    start "rabbit2", 5673
  end
end

namespace :redis do
  def config_file(suffix)
    File.expand_path(File.dirname(__FILE__)+"/etc/redis-#{suffix}.conf")
  end
  desc "start main redis"
  task :start1 do
    exec "redis-server #{config_file(:master)}"
  end
  desc "start slave redis"
  task :start2 do
    exec "redis-server #{config_file(:slave)}"
  end
end

task :default do
  Rake::Task[:test].invoke
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

require 'rake/rdoctask'

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'site/rdoc'
  rdoc.title    = 'Beetle'
  rdoc.options << '--line-numbers' << '--inline-source' << '--quiet'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name    = 'beetle'
    gemspec.version = '0.1.1'
    gemspec.summary = "High Availability AMQP Messaging with Redundant Queues"
    gemspec.description = "A highly available, reliable messaging infrastructure"
    gemspec.email = "developers@xing.com"
    gemspec.homepage = "http://xing.github.com/beetle/"
    gemspec.authors = ["Stefan Kaes", "Pascal Friederich", "Ali Jelveh"]
    gemspec.add_dependency('uuid4r', '>=0.1.1')
    gemspec.add_dependency('bunny', '>=0.6.0')
    gemspec.add_dependency('redis', '>=1.0.7')
    gemspec.add_dependency('amqp', '>=0.6.7')
    gemspec.add_dependency('activesupport', '>=2.3.4')

    gemspec.add_development_dependency('mocha')
    gemspec.add_development_dependency('rcov')
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  # puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

