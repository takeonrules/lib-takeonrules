require 'nokogiri'
require 'open-uri'
module TakeOnRules
  # This class is responsible for pushing posts to Social platforms
  class Socializer
    BLOG_TAGS_TO_SOCIAL_TAGS_MAP = {
      "dungeonsanddragons" => "dnd",
      "roleplayinggame" => "rpg"
    }

    def self.call(url:, to:, clients: nil)
      socializer = SOCIALIZERS.fetch(to)
      clients ||= socializer.clients
      socializer.new(url: url, clients: clients).call
    end

    class Base
      attr_reader :url, :clients
      def initialize(url:, clients:)
        @url = url
        @clients = Array(clients)
        parse_url!
      end

      def call
        clients.each do |client|
          create_status(client: client)
        end
        true
      end

      private

      attr_reader :headline, :url, :tags, :title, :image_url

      def client_for(credentials:)
        client_builder.call(base_url: credentials.fetch("base_url"), bearer_token: credentials.fetch("bearer_token"))
      end

      def parse_url!
        content = URI.open(url)
        doc = Nokogiri::HTML(content)
        json = JSON.parse(doc.css("script[type='application/ld+json']").text)
        @title = "#{json.fetch("name")} // Take on Rules"
        @url = doc.css('link[rel=canonical]').attribute("href").value
        @image_url = json.fetch("image").first.fetch("url")
        @headline = extract_headline(from: json)
        @tags = extract_tags(from: json)
      end

      def extract_headline(from:)
        title = from.fetch("name")
        headline = from.fetch("headline")
        return headline unless title == headline
        nil
      end

      def extract_tags(from:)
        keywords = from.fetch("keywords")
        keywords.split(",").map do |keyword|
          normalize_tag(keyword)
        end.join(" ")
      rescue KeyError
        nil
      end

      TAGSANITIZER_REGEXP = %r{\W+}
      def normalize_tag(keyword)
        tag = keyword.strip.gsub(TAGSANITIZER_REGEXP, '')
        begin
          "##{BLOG_TAGS_TO_SOCIAL_TAGS_MAP.fetch(tag)}"
        rescue KeyError
          "##{tag}"
        end
      end
    end
    private_constant :Base

    class ToTwitter < Base
      def self.clients
        require 'twitter'
        credentials_file_name = File.join(PROJECT_PATH, "credentials/twitter.json")
        list_of_credentials = JSON.parse(File.read(credentials_file_name))
        Array(list_of_credentials).map do |credentials|
          Twitter::REST::Client.new do |config|
            config.consumer_key        = credentials.fetch("consumer_key")
            config.consumer_secret     = credentials.fetch("consumer_secret")
            config.access_token        = credentials.fetch("access_token")
            config.access_token_secret = credentials.fetch("access_secret")
          end
        end
      end

      def create_status(client:)
        text = [title, url, tags].compact.join("\n\n")
        client.update(text)
      end
    end
    private_constant :ToTwitter

    class ToMastodon < Base
      def self.clients
        require 'mastodon'
        credentials_file_name = File.join(PROJECT_PATH, "credentials/mastodon.json")
        list_of_credentials = JSON.parse(File.read(credentials_file_name))
        Array(list_of_credentials).map do |credentials|
          Mastodon::REST::Client.new(base_url: credentials.fetch("base_url"), bearer_token: credentials.fetch("bearer_token"))
        end
      end

      def create_status(client:)
        text = [title, headline, url, tags].compact.join("\n\n")
        visibility = "public"
        card = { "url" => url, "title" => title, "image" => image_url }

        card["description"] = headline if headline
        attributes = { "visibility" => visibility, "card" => card }
        client.create_status(text, attributes)
      end
    end
    private_constant :ToMastodon

    SOCIALIZERS = {
      mastodon: ToMastodon,
      twitter: ToTwitter
    }
    private_constant :ToMastodon

  end
end
