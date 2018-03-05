require File.expand_path('../../../lib/beetle', __FILE__)

# See https://github.com/cucumber/cucumber/wiki/Using-MiniTest
require 'minitest/spec'

World do
  extend MiniTest::Assertions
end

Before do
  `ruby features/support/system_notification_logger start`
end

After do
  cleanup_test_env
end

at_exit do
  cleanup_test_env
end

def cleanup_test_env
  TestDaemons::RedisConfigurationClient.stop_all
  TestDaemons::RedisConfigurationServer.stop

  `ruby features/support/beetle_handler stop`
  redis_master_files = tmp_path + "/redis-master-*"
  `rm -f #{redis_master_files}`

  `ruby features/support/system_notification_logger stop`
  # `rm -f #{system_notification_log_path}`

  TestDaemons::Redis.stop_all
end

def redis_master_file(client_name)
  tmp_path + "/redis-master-#{client_name}"
end

def first_redis_configuration_client_pid
  File.read("redis_configuration_client_num0.pid").chomp.to_i
end

def system_notification_log_path
  log_path = tmp_path + "/system_notifications.log"
  `touch #{log_path}` unless File.exists?(log_path)
  log_path
end

def tmp_path
  File.expand_path("../../../tmp", __FILE__)
end
