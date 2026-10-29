# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ClaimLibrary
  # The little of the MediaWiki Action API the library needs: an article's
  # latest revision, and a revision rendered in full with its citation markup
  # intact.
  class Wiki
    TIMEOUT = 30
    MAX_RETRIES = 3

    attr_reader :language, :project

    def initialize(language: 'en', project: 'wikipedia', contact: 'dev')
      @language = language
      @project = project
      @user_agent = "ClaimLibrary/0.1 (#{contact})"
    end

    def name
      "#{language}.#{project}"
    end

    def api_url
      "https://#{language}.#{project}.org/w/api.php"
    end

    def latest_revision_id(title)
      pages = query(action: 'query', prop: 'revisions', titles: title, rvprop: 'ids')
              .dig('query', 'pages') || {}
      pages.values.first&.dig('revisions', 0, 'revid')
    end

    # { html:, title: } for a revision, or {} when it cannot be rendered.
    def revision_html(rev_id)
      data = query(action: 'parse', oldid: rev_id, prop: 'text', formatversion: 1)
      return {} if data.nil? || data['error']
      { html: data.dig('parse', 'text', '*'), title: data.dig('parse', 'title') }
    end

    private

    def query(params, attempt = 1)
      uri = URI(api_url)
      uri.query = URI.encode_www_form(params.merge(format: 'json'))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                     open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri, 'User-Agent' => @user_agent))
      end
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue StandardError
      raise if attempt >= MAX_RETRIES
      sleep(2**attempt)
      query(params, attempt + 1)
    end
  end
end
