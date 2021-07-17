# frozen_string_literal: true

module EspnScraper
  RSpec.describe Scraper do
    it "has a version number" do
      expect(EspnScraper::VERSION).not_to be nil
    end

    describe "#get_teams" do
      let(:nfl_pattern) do
        {id:   "buf",
         name: "Buffalo Bills"}
      end

      example "getting NFL teams" do
        VCR.use_cassette("get_teams/nfl") do
          col = subject.get_teams("nfl")
          expect(col).to include(nfl_pattern)
        end
      end

      # NOTE: for some reason this page is empty currently, skipping
      # https://www.espn.com/college-football/standings/_/view/fbs

      let(:ncf_pattern_div_fbs) do
        {id:       "302",
         name:     "UC Davis Aggies",
         division: "fbs"}
      end

      let(:ncf_pattern_div_fcs) do
        {id:       "2717",
         name:     "Western Carolina Catamounts",
         division: "fcs-i-aa"}
      end

      example "getting NCF teams for 'fbs, fcs-i-aa' divisions" do
        VCR.use_cassette("get_teams/ncf") do
          col = subject.get_teams("ncf")

          expect(col).to include(ncf_pattern_div_fcs)
        end
      end
    end

    # TODO: test different branches:
    # - league: "ncf" && college_division == nil
    # - college_division: "fcs"
    # - league: "wnba"
    describe "#get_standings" do
      let(:example) do
        {
          conferences: {
            "Eastern Conference" => {
              divisions: {
                "Atlantic" => {
                  teams: [
                    {
                      abbr: "MIA",
                      name: "Miami Heat"
                    },
                    {
                      abbr: "NY",
                      name: "New York Knicks"
                    }
                  ]
                },
                "Central"  => {
                  teams: [
                    {
                      abbr: "IND",
                      name: "Indiana Pacers"
                    }
                  ]
                }
              }
            },
            "Western Conference" => {
              divisions: {
                "Midwest" => {
                  teams: [
                    {
                      abbr: "MIN",
                      name: "Minnesota Timberwolves"
                    }
                  ]
                }
              }
            }
          }
        }
      end

      # You can test with expect(example).to include(conferences_pattern)
      let(:conferences_pattern) do
        # EASTERN CONF EXAMPLE

        atlantic_team1       = {abbr: "MIA", name: "Miami Heat"}
        atlantic_teams_array = {teams: include(atlantic_team1)}
        atlantic_division    = {"Atlantic" => include(atlantic_teams_array)}

        eastern_conf_divisions = {divisions: include(atlantic_division)}
        eastern_conf           = {"Eastern Conference" => include(eastern_conf_divisions)}

        # WESTERN CONF EXAMPLE

        midwest_team1       = {abbr: "MIN", name: "Minnesota Timberwolves"}
        midwest_teams_array = {teams: include(midwest_team1)}
        midwest_division    = {"Midwest" => include(midwest_teams_array)}

        western_conf_divisions = {divisions: include(midwest_division)}
        western_conf           = {"Western Conference" => include(western_conf_divisions)}

        {conferences: include(eastern_conf, western_conf)}
      end

      example "standings for NBA 2004" do
        VCR.use_cassette("get_standings/nba-2004") do
          col = subject.get_standings("nba", 2004)
          expect(col).to include(conferences_pattern)
        end
      end
    end

    # TODO: caching
    describe "#get_url" do
      example "getting boxscore by game ID" do
        game_id = 401_131_040
        url     = "https://www.espn.com/nfl/boxscore?gameId=#{game_id}&xhr=1"

        VCR.use_cassette("get_url/boxscore-xhr-gid-#{game_id}") do
          json = subject.get_url(url)
          expect(json["gameId"]&.to_i).to eq(game_id)
        end
      end
    end

    # REVIEW: really not sure this date thing works correctly
    describe "#get_all_scoreboard_urls" do
      example "get for NBA" do
        year = 2021
        VCR.use_cassette("get_all_scoreboard_urls/nba-#{year}") do
          urls = subject.get_all_scoreboard_urls("nba", year)
          expect(urls).to include("https://www.espn.com/nba/scoreboard/_/date/20191231?xhr=1")
        end
      end

      example "get for NCF" do
        year = 2019
        VCR.use_cassette("get_all_scoreboard_urls/ncf-#{year}") do
          urls = subject.get_all_scoreboard_urls("ncf", year)
          expect(urls).to include("https://www.espn.com/ncf/scoreboard/_/group/80/year/2019/seasontype/2/week/1?xhr=1")
        end
      end

      example "get for NFL" do
        year = 2019
        VCR.use_cassette("get_all_scoreboard_urls/nfl-#{year}") do
          urls = subject.get_all_scoreboard_urls("nfl", year)
          expect(urls).to include("https://www.espn.com/nfl/scoreboard/_/year/2019/seasontype/1/week/1?xhr=1")
        end
      end
    end

    describe "#get_current_scoreboard_urls for date league" do
      example "get for NCF" do
        offset_days = 5
        VCR.use_cassette("get_current_scoreboard_urls/ncb-#{offset_days}") do
          urls = subject.get_current_scoreboard_urls("ncb", offset_days)
          expect(urls).to include("https://www.espn.com/ncb/scoreboard/_/group/50/date/20210527?xhr=1")
        end
      end
    end

    describe "#get_current_scoreboard_urls for week league" do
      example "get for NFL" do
        offset_weeks = 10
        VCR.use_cassette("get_current_scoreboard_urls/nfl-#{offset_weeks}") do
          urls = subject.get_current_scoreboard_urls("nfl", offset_weeks)
          expect(urls).to include("https://www.espn.com/nfl/scoreboard/_/year/2021/seasontype/2/week/17?xhr=1")
        end
      end
    end
  end
end
