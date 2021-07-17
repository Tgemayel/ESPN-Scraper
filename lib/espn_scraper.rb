# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/time"
require "active_support/core_ext/integer/time"
require "nokogiri"
require "faraday"
require "faraday_middleware"
require "semantic_logger"
require_relative "espn_scraper/version"

module EspnScraper
  class Error < StandardError; end

  # TODO: add doc
  class Scraper
    include SemanticLogger::Loggable

    BASE_URL = "https://www.espn.com"

    #
    # GET GAME URL
    #

    VALID_GAME_URL_TYPES = %w[recap boxscore playbyplay conversation gamecast].freeze
    GAME_URL             = "#{BASE_URL}/%s/%s?gameId=%s&xhr=1"

    def get_game_url(url_type, league, espn_id)
      unless VALID_GAME_URL_TYPES.include?(url_type)
        error_msg = "Unknown url_type: '%s' for get_game_url. Valid url_types are %s" % [url_type,
                                                                                         VALID_GAME_URL_TYPES.join]
        logger.error(error_msg)
        raise(ArgumentError(error_msg))
      end

      GAME_URL % [league, url_type, espn_id]
    end

    #
    # GET TEAMS
    #

    TEAMS_URL                  = "#{BASE_URL}/%s/teams"
    COLLEGE_FOOTBALL_TEAMS_URL = "#{BASE_URL}/college-football/standings/_/view/%s"
    COLLEGE_FOOTBALL_DIVISIONS = %w[fbs fcs-i-aa].freeze

    # Returns a list of teams with ids && names
    def get_teams(league)
      if league == "ncf"

        # espn's college football teams page only lists fbs
        # need to grab teams from standings page instead if want all the fbs and fcs teams
        COLLEGE_FOOTBALL_DIVISIONS.reduce([]) do |results, division|
          logger.debug("#get_teams: scraping teams", league: league, division: division)

          url      = COLLEGE_FOOTBALL_TEAMS_URL % division
          html     = request_html_and_parse(url)
          selector = ".hide-mobile"

          results + html.css(selector).map do |team_div|
            id     = team_div.css("a").first["href"].split("/")[-2]
            name   = team_div.content
            result = {id: id, name: name, division: division}

            # logger.debug(result)
            result
          end
        end

      else
        url  = TEAMS_URL % league
        html = request_html_and_parse(url)

        selector = league == "wnba" ? "div.pl3" : "div.mt3"

        # /nfl/team/_/name/kc/kansas-city-chiefs -> kc
        html.css(selector).map do |team_div|
          id     = team_div.css("a").first["href"].split("/")[-2]
          name   = team_div.css("h2").first.text
          result = {id: id, name: name}

          # logger.debug(result)
          result
        end
      end
    end

    #
    # GET STANDINGS
    #

    STANDINGS_VALID_LEAGUES           = %w[nhl nfl mlb nba wnba ncf ncb ncw].freeze
    STANDINGS_VALID_COLLEGE_DIVISIONS = %w[fbs fcs fcs-i-aa d2 d3].freeze
    STANDINGS_COLLEGE_DIVISION_URL    = "#{BASE_URL}/%s/standings/_/season/%s/view/%s"
    STANDINGS_CONFERENCE_URL          = "#{BASE_URL}/%s/standings/_/season/%s/group/conference"
    STANDINGS_DIVISION_URL            = "#{BASE_URL}/%s/standings/_/season/%s/group/division"

    def get_standings(league, season_year, college_division: nil)
      standings = {conferences: {}}

      return standings unless STANDINGS_VALID_LEAGUES.include?(league)

      # URL chooser

      # default to fbs
      college_division = "fbs" if league == "ncf" && college_division.nil?

      url = if college_division
              college_division = "fcs-i-aa" if college_division == "fcs"

              if STANDINGS_VALID_COLLEGE_DIVISIONS.include?(college_division)
                STANDINGS_COLLEGE_DIVISION_URL % [league, season_year, college_division]
              else
                error_message = "College division must be nil or %s" % STANDINGS_VALID_COLLEGE_DIVISIONS.join
                raise(ArgumentError, error_message)
              end
            else
              url_pattern = league == "wnba" ? STANDINGS_CONFERENCE_URL : STANDINGS_DIVISION_URL
              url_pattern % [league, season_year]
            end

      # BUILDING DATA

      selector = "div.standings__table"
      html     = request_html_and_parse(url)
      html.css(selector).each do |standing_div|
        conference_name                          = standing_div.css("div.Table__Title")&.first&.text
        standings[:conferences][conference_name] = {divisions: {}}
        division                                 = "" # default blank division name

        logger.debug("#get_standings: found conference", conference_name: conference_name)

        teams_table = standing_div.css("table.Table--fixed-left").first
        teams_table.css("tr").each do |tr|
          if tr["class"].include?("subgroup-headers")
            division = tr.text # replace default blank division name

            standings[:conferences][conference_name][:divisions][division] = {teams: []}
          elsif tr.text.present?
            if division.blank? && standings[:conferences][conference_name][:divisions] == {}
              standings[:conferences][conference_name][:divisions][division] = {teams: []}
            end

            team          = {}
            team_span_tag = tr.css("td.Table__TD").css("span.hide-mobile").first
            team_a_tag    = team_span_tag.css("a").first

            if team_a_tag
              team[:name] = team_a_tag.text
              team[:abbr] = if %w[ncf ncb ncw].include?(league)
                              team_a_tag["href"].split("/id/")[1].split("/")[0].upcase
                            else
                              team_a_tag["href"].split("/name/")[1].split("/")[0].upcase
                            end
            else
              # some teams are now defunct with no espn links
              team[:name] = team_span_tag.text.strip
              team[:abbr] = ""
            end

            standings[:conferences][conference_name][:divisions][division][:teams].push(team)
          end
        end
      end

      standings
    end

    #
    # GET BY URL
    #

    VALID_DATA_TYPES_FROM_URL = %w[scoreboard recap boxscore playbyplay conversation gamecast].freeze

    # Guess && return the data_type based on the url
    def get_data_type_from_url(url)
      VALID_DATA_TYPES_FROM_URL.detect do |substr|
        url.include?(substr)
      end || begin
        error_message = "Unknown data_type for url. Url must contain one of '%s'" % VALID_DATA_TYPES_FROM_URL.join
        raise(ArgumentError, error_message)
      end
    end

    # Get stuff from URL or filenames
    def get_league_from_url(url)
      url.split(".com/")[1].split("/")[0]
    end

    def get_date_from_scoreboard_url(url)
      league = get_league_from_url(url)
      if league == "nhl"
        url.split("?date=")[1].split("&")[0]
      else
        url.split("/")[-1].split("?")[0]
      end
    end

    SPORTSCENTER_API_URL = "https:/sportscenter.api.espn.com/apis/v1/events?sport=%s&league=%s&dates=%s"

    def get_sportscenter_api_url(sport, league, dates)
      SPORTSCENTER_API_URL % [sport, league, dates]
    end

    HTML_BOXSCORE_LEAGUES = ["nhl"].freeze

    # Either html || json depending on league && data_type
    def expected_response_format_for(league, data_type)
      return :html if data_type == "boxscore" && HTML_BOXSCORE_LEAGUES.include?(league)

      :json
    end

    # Scoreboard json isn't easily available for some leagues, have to grab the game_ids
    # from sportscenter_api url
    NO_SCOREBOARD_JSON_LEAGUES = %w[wnba nhl].freeze

    # Retrieve an ESPN JSON data || HTML BeautifulSoup, either from cache || make new request
    def get_url(url, cache: false)
      data_type = get_data_type_from_url(url)
      league    = get_league_from_url(url)

      if data_type == "scoreboard" && NO_SCOREBOARD_JSON_LEAGUES.include?(league)
        logger.debug("#get_url: detected scoreboard data type with no json leagues")

        url = get_sportscenter_api_url(
          sport:  get_sport(league),
          league: league,
          dates:  get_date_from_scoreboard_url(url)
        )
      end

      logger.debug("#get_url: getting data from URL", url: url, data_type: data_type, league: league, cache: cache)

      raise(NotImplementedError) if cache

      # get_cached_url(url, league, data_type, cached_path)

      expected_format = expected_response_format_for(league, data_type)

      send(:"request_#{expected_format}", url)
    end

    #
    # GET SCOREBOARD URLS
    #

    SCOREBOARD_URL_BASE = "#{BASE_URL}/%s/scoreboard"
    NCB_GROUPS          = [50, 55, 56, 100].freeze
    NCW_GROUPS          = [50, 55, 100].freeze
    NCF_GROUPS          = [80, 81].freeze

    # DATE SCOREBOARD

    DATE_LEAGUES                 = %w[mlb nba ncb ncw wnba nhl].freeze
    DATE_SCOREBOARD_URL_NHL      = "#{SCOREBOARD_URL_BASE}?date=%s"
    DATE_SCOREBOARD_URL_NO_GROUP = "#{SCOREBOARD_URL_BASE}/_/date/%s?xhr=1"
    DATE_SCOREBOARD_URL_GROUP    = "#{SCOREBOARD_URL_BASE}/_/group/%s/date/%s?xhr=1"

    # Return a scoreboard url for a league that uses dates (nonfootball)
    def get_date_scoreboard_url(league, date, group = nil)
      if DATE_LEAGUES.include?(league)
        if league == "nhl"
          DATE_SCOREBOARD_URL_NHL % [league, date]
        elsif group
          DATE_SCOREBOARD_URL_GROUP % [league, group, date]
        else
          DATE_SCOREBOARD_URL_NO_GROUP % [league, date]
        end
      else
        error_msg = "League %s must be in '%s' to get date scoreboard url" % [league, DATE_LEAGUES.join]
        logger.error(error_msg, {league: league})

        raise(ArgumentError(error_msg))
      end
    end

    # WEEK SCOREBOARD

    WEEK_LEAGUES                 = %w[nfl ncf].freeze
    WEEK_SCOREBOARD_URL_GROUP    = "#{SCOREBOARD_URL_BASE}/_/group/%s/year/%s/seasontype/%s/week/%s?xhr=1"
    WEEK_SCOREBOARD_URL_NO_GROUP = "#{SCOREBOARD_URL_BASE}/_/year/%s/seasontype/%s/week/%s?xhr=1"

    # Return a scoreboard url for a league that uses weeks (football)
    def get_week_scoreboard_url(league, season_year, season_type, week, group = nil)
      if WEEK_LEAGUES.include?(league)
        if group
          WEEK_SCOREBOARD_URL_GROUP % [league, group, season_year, season_type, week]
        else
          WEEK_SCOREBOARD_URL_NO_GROUP % [league, season_year, season_type, week]
        end
      else
        error_msg = "League %s must be in '%s' to get week scoreboard url" % [league, WEEK_LEAGUES.join]
        logger.error(error_msg, {league: league})

        raise(ArgumentError(error_msg))
      end
    end

    # GET ALL SCOREBOARD URLS

    def get_season_start_end_datetimes_helper(url)
      # TODO: use cached replies if scoreboard url is older than 1 year
      scoreboard = get_url(url)
      dates_hash = scoreboard.dig("content", "sbData", "leagues")[0]

      raise(StandardError, "Not a hash") unless dates_hash.is_a?(Hash)

      start_date = dates_hash.fetch("calendarStartDate")
      end_date   = dates_hash.fetch("calendarEndDate")
      [Time.new(start_date), Time.new(end_date)]
    end

    TZ_US_EASTERN = "US/Eastern"

    # Guess a random date in a leagues season && return its calendar start && end dates,
    # only non football adheres to this format
    # Must return pair of Time objects
    def get_season_start_end_datetimes(league, season_year)
      case league
      when "mlb"
        get_season_start_end_datetimes_helper(get_date_scoreboard_url(league, "#{season_year.to_i}0415"))
      when "nba"
        get_season_start_end_datetimes_helper(get_date_scoreboard_url(league, "#{season_year.to_i - 1}1101"))
      when "ncb" || "ncw"
        get_season_start_end_datetimes_helper(get_date_scoreboard_url(league, "#{season_year.to_i - 1}1130"))
      when "wnba"
        # hardcode wnba start end dates, assumed to be April 20 thru Oct 31
        start_date = Time.new(season_year, 4, 20, 0, 0, 0, TZ_US_EASTERN).utc
        end_date   = Time.new(season_year, 10, 31, 0, 0, 0, TZ_US_EASTERN).utc

        [start_date, end_date]
      when "nhl"
        # hardcode nhl start end dates, assumed to be Oct 1 thru June 30
        start_date = Time.new(season_year - 1, 10, 1, 0, 0, 0, TZ_US_EASTERN).utc
        end_date   = Time.new(season_year, 6, 30, 0, 0, 0, TZ_US_EASTERN).utc

        [start_date, end_date]
      else
        error_message = "League must be '%s' to get season start && end datetimes" % DATE_LEAGUES.join
        logger.error(error_message)
        raise(ArgumentError, error_message)
      end
    end

    # Return a calendar for a league && season_year
    def get_calendar(league, date_or_season_year)
      logger.debug("#get_calendar: getting calendar for", league: league, date_or_season_year: date_or_season_year)

      url = if WEEK_LEAGUES.include?(league)
              get_week_scoreboard_url(league, date_or_season_year, 2, 1) # week: 2, group: 1
            elsif DATE_LEAGUES.include?(league)
              get_date_scoreboard_url(league, date_or_season_year)
            else
              error_message = "Unknown league: '%s'" % league
              logger.error(error_message)
              raise(ArgumentError, error_message)
            end

      # TODO: use cached replies for older urls
      get_url(url).dig("content", "calendar")
    end

    # Return a list of the current scoreboard urls for a league
    # For date leagues optional offset == in days
    # For week leagues optional offseet is in weeks
    def get_current_scoreboard_urls(league, offset = 0)
      urls = []
      if DATE_LEAGUES.include?(league)
        date_str = (Time.current + offset.days).strftime("%Y%m%d")
        logger.debug("#get_all_scoreboard_urls: date league detected", league: league, date: date_str)

        case league
        when "ncb"
          NCB_GROUPS.each do |group|
            urls.push(get_date_scoreboard_url(league, date_str, group))
          end
        when "ncw"
          NCW_GROUPS.each do |group|
            urls.push(get_date_scoreboard_url(league, date_str, group))
          end
        else
          urls.push(get_date_scoreboard_url(league, date_str))
        end
        urls

      elsif WEEK_LEAGUES.include?(league)
        # need to add timezone to now to compare with timezoned entry datetimes later
        date_time           = Time.current.utc + offset.weeks
        # guess the league season_year
        guessed_season_year = if date_time.month > 2
                                date_time.year
                              else
                                date_time.year - 1
                              end

        logger.debug("#get_all_scoreboard_urls: week league detected",
                     league: league, date_time: date_str, guessed_season_year: guessed_season_year)

        calendar = get_calendar(league, guessed_season_year)
        calendar.each do |season_type|
          next unless season_type.include?("entries")

          season_type["entries"].each do |entry|
            if date_time >= Time.new(entry["startDate"]) && date_time <= Time.new(entry["endDate"])
              if league == "ncf"
                NCF_GROUPS.each do |group|
                  urls.push(
                    get_week_scoreboard_url(league,
                                            guessed_season_year,
                                            season_type["value"],
                                            entry["value"],
                                            group)
                  )
                end
              else
                urls.push(
                  get_week_scoreboard_url(league,
                                          guessed_season_year,
                                          season_type["value"],
                                          entry["value"])
                )
              end
            end
          end
        end
        urls
      else
        error_message = "Unknown league '%s' for get_current_scoreboard_urls" % league
        logger.error(error_message)
        raise(ArgumentError, error_message)
      end
    end

    # Return a list of all scoreboard urls for a given league && season year
    def get_all_scoreboard_urls(league, season_year)
      urls = []
      if DATE_LEAGUES.include?(league)
        logger.debug("#get_all_scoreboard_urls: date league detected", league: league)

        start_date, end_date = get_season_start_end_datetimes(league, season_year)

        logger.debug("#get_all_scoreboard_urls: got initial start and end dates",
                     start_date: start_date, end_date: end_date)

        while start_date < end_date
          # logger.debug("Getting scoreboard for", start_date: start_date)

          case league
          when "ncb"
            NCB_GROUPS.each do |group|
              urls.push(get_date_scoreboard_url(league, start_date.strftime("%Y%m%d"), group))
            end
          when "ncw"
            NCW_GROUPS.each do |group|
              urls.push(get_date_scoreboard_url(league, start_date.strftime("%Y%m%d"), group))
            end
          else
            urls.push(get_date_scoreboard_url(league, start_date.strftime("%Y%m%d")))
          end

          # Adding 1 day and recur
          start_date += 1.day
        end

        urls

      elsif WEEK_LEAGUES.include?(league)
        logger.debug("#get_all_scoreboard_urls: week league detected", league: league)

        calendar = get_calendar(league, season_year)
        calendar.each do |season_type|
          next unless season_type.include?("entries")

          season_type["entries"].each do |entry|
            if league == "ncf"
              NCF_GROUPS.each do |group|
                urls.push(get_week_scoreboard_url(league, season_year, season_type["value"], entry["value"], group))
              end
            else
              urls.push(get_week_scoreboard_url(league, season_year, season_type["value"], entry["value"]))
            end
          end
        end
        urls
      else
        error_message = "Unknown league '%s' for get_all_scoreboard_urls" % league
        logger.error(error_message)
        raise(ArgumentError, error_message)
      end
    end

    #
    # TRANSPORT
    #

    MAX_REQUEST_RETRIES = 3
    REQUEST_TIMEOUT     = 10
    INTERVAL            = 2

    HTTP_CLIENT_REQUEST_DEFAULTS = {request: {timeout: REQUEST_TIMEOUT}}.freeze
    HTTP_CLIENT_RETRY_CONFIG     = {
      max:                 MAX_REQUEST_RETRIES,
      interval:            INTERVAL,
      interval_randomness: 0.5,
      backoff_factor:      2,
      methods:             %i[get]
    }.freeze

    # NOTE: had to add redirects here, because /ncf now leads to /college-football
    def json_client(headers: {})
      Faraday.new(headers: headers, **HTTP_CLIENT_REQUEST_DEFAULTS) do |f|
        f.response(:json)
        f.response(:follow_redirects)
        f.response(:raise_error)
        f.request(:retry, HTTP_CLIENT_RETRY_CONFIG)
      end
    end

    def http_client(headers: {})
      Faraday.new(headers: headers, **HTTP_CLIENT_REQUEST_DEFAULTS) do |f|
        f.response(:follow_redirects)
        f.response(:raise_error)
        f.request(:retry, HTTP_CLIENT_RETRY_CONFIG)
      end
    end

    def request_json(url)
      logger.debug("#request_json: requesting JSON and parsing", url: url)
      json_client.get(url).body
    end

    def request_html(url)
      logger.debug("#request_html: requesting HTML", url: url)
      http_client.get(url).body
    end

    def parse_html(raw_html)
      logger.debug("#parse_html: parsing HTML")
      Nokogiri::HTML(raw_html)
    end

    # Faraday::Response
    def request_html_and_parse(url)
      parse_html(request_html(url))
    end

    #
    # UTILS
    #

    def get_sport(league)
      if %w[nba wnba ncb ncw].include?(league)
        "basketball"
      elsif ["mlb"].include?(league)
        "baseball"
      elsif %w[nfl ncf].include?(league)
        "football"
      elsif ["nhl"].include?(league)
        "hockey"
      end
    end
  end
end
