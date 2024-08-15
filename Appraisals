# keep the same versions in .github/workflows/build.yml
activerecord_versions = [
  "6.1.7.8",
  "7.0.8.4",
  "7.1.3.4",
  "7.2.0"
]
activerecord_versions.each do |activerecord_version|
  appraise "redis_4_activerecord_#{activerecord_version}" do
    gem "redis", "~> 4.0"
    gem "activerecord", activerecord_version
  end
  appraise "redis_5_activerecord_#{activerecord_version}" do
    gem "redis", "~> 5.0"
    gem "hiredis-client"
    gem "activerecord", activerecord_version
  end
end
