FROM ruby:3.3-alpine

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN bundle config --global frozen 1 && \
    bundle config set deployment 'true' && \
    bundle config set without 'development test' && \
    bundle config set path 'vendor/bundle' && \
    bundle install

COPY . .

CMD ["bundle", "exec", "ruby", "main.rb"]
