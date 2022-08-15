Given /^consul state has been cleared$/ do
  consul_host = ENV["CONSUL_HOST"] || "localhost:8500"
  system "killall beetle beetle_handler >/dev/null 2>/dev/null"
  system "curl --silent --request PUT http://#{consul_host}/v1/kv/apps/beetle/config/ >/dev/null"
  system "curl --silent --request PUT http://#{consul_host}/v1/kv/shared/config/ >/dev/null"
  system "curl --silent --request DELETE http://#{consul_host}/v1/kv/apps/beetle/state/redis_master_file_content >/dev/null"
end

Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart
  TestDaemons::Redis[redis_name].master
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  TestDaemons::Redis[redis_name].restart
  step "redis server \"#{redis_name}\" is slave of \"#{redis_master_name}\""
end

Given /^redis server "([^\"]*)" is master$/ do |redis_name|
  TestDaemons::Redis[redis_name].master
end

Given /^redis server "([^\"]*)" is slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  TestDaemons::Redis[redis_name].slave_of(TestDaemons::Redis[redis_master_name].port)
  master = TestDaemons::Redis[redis_master_name].redis
  slave = TestDaemons::Redis[redis_name].redis
  begin
    sleep 1
  end while !slave.slave_of?(master.host, master.port)
end

Given /^a redis configuration server using redis servers "([^\"]*)" with clients "([^\"]*)" (?:and confidence level "([^\"]*)" )?exists$/ do |redis_names, redis_configuration_client_names, confidence_level|
  redis_servers = redis_names.split(";").map do |system_spec|
    if system_spec.include?("/")
      system_name, servers = system_spec.split("/", 2)
    else
      system_name, servers = nil, system_spec
    end
    servers = servers.split(",").map { |redis_name| TestDaemons::Redis[redis_name].ip_with_port }.join(",")
    system_name.nil? ? servers : "#{system_name}/#{servers}"
  end.join(";")
  TestDaemons::RedisConfigurationServer.start(redis_servers, redis_configuration_client_names, (confidence_level || 100).to_i)
  # wait until the notification logger has connected
  100.times do
    break if TestDaemons::RedisConfigurationServer.has_notification_channel? && `curl -s 127.0.0.1:9651`.chomp == "true"
    sleep 0.1
  end
  raise "could not attach notification logger!!!!" unless TestDaemons::RedisConfigurationServer.has_notification_channel?
end

Given /^a redis configuration client "([^\"]*)" using redis servers "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_names|
  redis_names.split(";").each do |system_spec|
    servers = system_spec.sub(/^.*\//, '')
    servers.split(",").map { |redis_name| TestDaemons::Redis[redis_name].ip_with_port }
  end
  TestDaemons::RedisConfigurationClient[redis_configuration_client_name].start
end

Given /^redis server "([^\"]*)" is down$/ do |redis_name|
  TestDaemons::Redis[redis_name].stop
end

Given /^redis configuration client "([^\"]*)" is down$/ do |redis_configuration_client_name|
  TestDaemons::RedisConfigurationClient[redis_configuration_client_name].stop
end

Given /^the retry timeout for the redis master check is reached$/ do
  basetime = Time.now
  i = 0
  while (i <= 10.0) do
    break if TestDaemons::RedisConfigurationClient.instances.values.all? {|instance| File.mtime(instance.redis_master_file) > basetime rescue false}
    i += 0.1
    sleep(0.1)
  end
  sleep 1 # give it time to switch because the modified mtime might be because of the initial invalidation and not the switch
end

Given /^a beetle handler using the redis-master file from "([^\"]*)" exists$/ do |redis_configuration_client_name|
  master_file = redis_master_file(redis_configuration_client_name)
  `ruby features/support/beetle_handler start -- --redis-master-file=#{master_file}`
  assert File.exist?(master_file), "file #{master_file} does not exist"
end

Given /^redis server "([^\"]*)" is down for less seconds than the retry timeout for the redis master check$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart(1)
end

Given /^the retry timeout for the redis master determination is reached$/ do
  sleep 1
end

Given /^redis server "([^\"]*)" is coming back$/ do |redis_name|
  TestDaemons::Redis[redis_name].restart
end

Given /^an old redis master file for "([^\"]*)" with master "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_name|
  master_file = redis_master_file(redis_configuration_client_name)
  File.open(master_file, 'w') do |f|
    f.puts "system/#{TestDaemons::Redis[redis_name].ip_with_port}"
  end
end

Then /^the role of redis server "([^\"]*)" should be "(master|slave)"$/ do |redis_name, role|
  expected_role = false
  10.times do
    expected_role = true and break if TestDaemons::Redis[redis_name].__send__ "#{role}?"
    sleep 1
  end
  assert expected_role, "#{redis_name} is not a #{role}"
end

Then /^the redis server "([^\"]*)" is a slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  master = TestDaemons::Redis[redis_master_name].redis
  slave = TestDaemons::Redis[redis_name].redis
  3.times do
    sleep 1
    break if slave.slave_of?(master.host, master.port)
  end
  assert slave.slave_of?(master.host, master.port)
end

Then /^the redis master of "([^\"]*)" (?:in system "([^"]*)" )?should be "([^\"]*)"$/ do |redis_configuration_client_name, system_name, redis_name|
  system_name ||= "system"
  master_file = redis_master_file(redis_configuration_client_name)
  master = false
  server_info = ''
  10.times do
    server_name = TestDaemons::Redis[redis_name].ip_with_port
    server_info = File.read(master_file).chomp if File.exist?(master_file)
    if server_info.include?("/")
      master = true and break if server_info =~ /#{system_name}\/#{server_name}/m
    else
      master = true and break if server_info == server_name
    end
    sleep 1
  end
  assert master, "#{redis_name} is not master of #{redis_configuration_client_name}, master file content: #{server_info.inspect}"
end

Then /^the redis master file of the redis configuration server should contain "([^"]*)"$/ do |redis_name|
  master_file = TestDaemons::RedisConfigurationServer.redis_master_file
  file_contents = File.read(master_file).chomp
  assert_match /#{TestDaemons::Redis[redis_name].ip_with_port}/, file_contents
end

Then /^the redis master of "([^\"]*)" should be undefined$/ do |redis_configuration_client_name|
  master_file = redis_master_file(redis_configuration_client_name)
  empty = false
  server_info = nil
  10.times do
    server_info = File.read(master_file).chomp if File.exist?(master_file)
    empty = server_info !~ /:\d+/
    break if empty
    sleep 1
  end
  assert empty, "master file is not empty: #{server_info}"
end

Then /^the redis master of the beetle handler should be "([^\"]*)"$/ do |redis_name|
  Beetle.config.servers = "127.0.0.1:5672" # rabbitmq
  Beetle.config.logger.level = Logger::FATAL
  redis_master = TestDaemons::Redis[redis_name].ip_with_port
  response = `curl -s 127.0.0.1:10254/redis_master`.chomp
  assert_equal redis_master, response
end

Then /^a system notification for "([^\"]*)" not being available should be sent$/ do |redis_name|
  text = "Redis master '#{TestDaemons::Redis[redis_name].ip_with_port}' not available"
  lines = File.readlines(system_notification_log_path)
  tail = (["","",""]+lines)[-3..-1].join("\n")
  assert_match /#{text}/, tail
end

Then /^a system notification for switching from "([^\"]*)" to "([^\"]*)" should be sent$/ do |old_redis_master_name, new_redis_master_name|
  text = "Setting redis master to '#{TestDaemons::Redis[new_redis_master_name].ip_with_port}' (was '#{TestDaemons::Redis[old_redis_master_name].ip_with_port}')"
  lines = File.readlines(system_notification_log_path)
  tail = (["","",""]+lines)[-3..-1].join("\n")
  assert_match /#{Regexp.escape(text)}/, tail
end

Then /^a system notification for no slave available to become new master should be sent$/ do
  text = "Redis master could not be switched, no slave available to become new master"
  tail = ""
  3.times do
    lines = File.readlines(system_notification_log_path)
    tail = (["","",""]+lines)[-3..-1].join("\n")
    sleep 0.1 unless tail =~ /#{text}/
  end
  assert_match /#{text}/, tail
end

Then /^the redis configuration server should answer http requests$/ do
  assert TestDaemons::RedisConfigurationServer.answers_text_requests?
  assert TestDaemons::RedisConfigurationServer.answers_html_requests?
  assert TestDaemons::RedisConfigurationServer.answers_json_requests?
end

Given /^an immediate master switch is initiated and responds with (\d+)$/ do |response_code|
  response = TestDaemons::RedisConfigurationServer.initiate_master_switch
  assert_equal response_code.to_s, response.code, "unexpected response code #{response.code}, message: #{response.body}"
  sleep 1
end
