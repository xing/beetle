# keep the same versions in .github/workflows/build.yml
rails_versions = [
  "6.1.7.8",
  "7.0.8.4",
  "7.1.4",
  "7.2.1"
]
rails_versions.each do |rails_version|
  appraise "redis_4_rails_#{rails_version}" do
    gem "redis", "~> 4.0"
    gem "activerecord", rails_version
    gem "activesupport", rails_version
  end
  appraise "redis_5_rails_#{rails_version}" do
    gem "redis", "~> 5.0"
    gem "hiredis-client"
    gem "activerecord", rails_version
    gem "activesupport", rails_version
  end
end
