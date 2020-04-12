require 'uri'
require 'faraday'

module TakeOnRules
  # A module for managing interaction with Newsboat
  module Newsboat
    # A data-structure with builders for context-based parsing
    module Entry
      NEWSBOAT_URL_FORMAT_SPLITTER = %r{ +}
      URL_PREFIX = %r{^http}
      def self.build_from_newsboat(line:)
        if line.match(URL_PREFIX)
          url, tags = line.split(NEWSBOAT_URL_FORMAT_SPLITTER)
          Url.new(url: url, tags: tags)
        else
          Query.new(line: line)
        end
      end

      class Query
        def initialize(line:)
          @line = line
        end
        attr_reader :line
        alias url line
        alias to_s line

        include Comparable
        def <=>(other)
          url.to_s <=> other.url.to_s
        end

        def update!; end
      end

      class Url
        def initialize(url:, tags:)
          self.url = url
          self.tags = tags
          self.updated_url = url
        end

        private
        def url=(value)
          @url = URI.parse(value.to_s)
        end

        def tags=(value)
          @tags = Array(value)
        end

        def updated_url=(value)
          @updated_url = URI.parse(value.to_s)
        end

        public
        attr_reader :url, :tags, :updated_url

        include Comparable
        def <=>(other)
          url.to_s <=> other.url.to_s
        end

        def to_s
          "#{url} #{tags.join(' ')}"
        end

        def update!
          self.updated_url = curler!(url: url)
          self.updated_url = ssler!(url: updated_url)
          puts updated_url
        end

        private

        def ssler!(url:)
          return url unless url.is_a?(URI::HTTP)
          return url if url.scheme == 'https'
          ssl_url = url.clone
          ssl_url.scheme = "https"
          return ssl_url if url.host == "feeds.feedburner.com"
          response = Faraday.head(ssl_url)
          if response.status >= 300
            return url
          else
            return ssl_url
          end
        rescue Faraday::SSLError, Faraday::ConnectionFailed
          return url
        end

        def curler!(ttl: 5, url:)
          return url unless url.is_a?(URI::HTTP)
          return url if ttl <= 0
          response = Faraday.head(url)
          if response.status >= 500
            return url
          elsif response.status >= 400
            return :gone
          elsif response.status >= 300
            return curler!(ttl: ttl - 1, url: response.headers.fetch(:location))
          else
            return url
          end
        rescue Faraday::ConnectionFailed
          return url
        end
      end
    end

    # Given the URLs file and Cache DB for Newboat
    #
    # 1) See if HTTP URLs can be converted to HTTPS
    # 2) Follow any redirects to get to the preferred feed URL
    # 3) Update underlying cache record for updated feeds
    class UrlMaintenance
      def initialize(url_filename:, cache_filename:)
        @url_filename = url_filename
        @cache_filename = cache_filename
        load_entries!
      end

      def update!
        @entries.each(&:update!)
      end

      private

      def load_entries!
        @entries = File.read(@url_filename).split("\n").map do |line|
          Entry.build_from_newsboat(line: line)
        end
      end
    end
  end
end
