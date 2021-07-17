# ESPN Scraper

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'espn_scraper'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install espn_scraper

## Usage

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Pry shortcuts

Just run `pry` in repo's dir and call methods on `S` constant, like so:

```
S.get_teams("nfl")
S.get_teams("ncf")
S.get_standings("nba", 2020)
S.get_url("https://www.espn.com/nfl/boxscore?gameId=401131040&xhr=1")
S.get_all_scoreboard_urls("nba", 2020)
S.get_all_scoreboard_urls("ncf", 2020)
S.get_all_scoreboard_urls("nfl", 2020)
S.get_current_scoreboard_urls("ncb", offset_days = 5)
S.get_current_scoreboard_urls("nfl", offset_weeks = 5)
```

## Faraday

- [middleware list](https://github.com/lostisland/awesome-faraday/)
- [caching](https://github.com/lostisland/faraday_middleware/blob/main/docs/caching_responses.md)

## TODO

- [ ] add optional caching
- [ ] CLI?
