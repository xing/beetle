FROM ruby:2.3.1
WORKDIR /app
RUN apt-get update -y && apt-get install -y libossp-uuid-dev
COPY ./lib/beetle/version.rb /app/lib/beetle/version.rb
COPY Gemfile* beetle.gemspec /app/
RUN BUNDLE_SILENCE_ROOT_WARNING=1 bundle install -j4 --without development test
ADD . /app/
ENTRYPOINT ["/app/docker/entrypoint.sh"]
