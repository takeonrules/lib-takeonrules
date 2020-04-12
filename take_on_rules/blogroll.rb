require 'faraday'
require 'nokogiri'

module Blogroll
  # For each HREFs at a given URL within the given CSS selector,
  # visit that HREF and look for either a `type="application/atom+xml"` or
  # `type="application/rss+xml"` link.
  class Crawler
    BLOGROLL_REGEXP = %r{blog +roll}i
    BLOGSPOT_BLOGROLL_SELECTOR = ".blog-list-container .blog-title a"
    SKIP_THESE_BLOGS = [
      "dndwithpornstars",
      "vengersatanis"
    ]
    def initialize(opml_filename:, found_url_filename:)
      @opml_filename = opml_filename
      @array = []
      @found_url_filename = found_url_filename
    end

    def crawl
      xml = File.read(@opml_filename)
      doc = Nokogiri::XML(xml)
      doc.css("outline[type=rss]").each do |outline|
        url = outline["htmlUrl"]
        next if url.to_s.empty?
        # Blogspot's with blog rolls have a predictable blog roll ".blog-list-container .blog-title a"
        next unless url.include?("blogspot.com")
        ForSite.new(crawler: self, url: url, css_selector: BLOGSPOT_BLOGROLL_SELECTOR).crawl!
      end
      File.open(@found_url_filename, "w+") do |file|
        @array.each do |entry|
          next if SKIP_THESE_BLOGS.detect { |blog| host.include?(blog) }
          file.puts entry
        end
      end
    end

    def add(host:, href:)
      $stdout.puts "Found\t#{host}\t#{href}"
      @array << "#{host}\t#{href}"
    end

    class ForSite
      def initialize(crawler:, url:, css_selector:)
        @url = url
        @css_selector = css_selector
        @crawler = crawler
      end
      attr_reader :url, :css_selector, :crawler

      def crawl!
        begin
          response = Faraday.get(url)
          Nokogiri::XML(response.body).css(css_selector).each do |node|
            href = node["href"].to_s
            next if href.empty?
            $stdout.puts "Visiting: #{href}"
            # TODO: Change from visiting to capturing. This will allow a step
            # to reduced duplicates and not visit sites already in the blog
            # roll
            visit_blogroll_entry(href: href)
          end
        rescue Faraday::ConnectionFailed, Faraday::SSLError
          # Skip these pernicious errors
        rescue => e
          $stderr.puts "#{e.class}: #{e}"
        end
      end

      private

      def visit_blogroll_entry(href:)
        uri = URI.parse(href)
        response = Faraday.get("#{uri.scheme}://#{uri.host}")
        entry_doc = Nokogiri::HTML(response.body)
        entry_doc.css("link[type='application/atom+xml']").each do |node|
          crawler.add(host: uri.host, href: node['href'])
        end
        entry_doc.css("link[type='application/rss+xml']").each do |node|
          crawler.add(host: uri.host, href: node['href'])
        end
      rescue Faraday::ConnectionFailed, Faraday::SSLError
        # Skip these pernicious errors
      rescue
        $stderr.puts "#{e.class}: #{e}"
      end
    end
  end

  class Merger
    def initialize(candidate_url_filename:, current_urls_filename:, merged_filename:, skip_filename:)
      @candidate_url_filename = candidate_url_filename
      @current_urls_filename = current_urls_filename
      @merged_filename = merged_filename
      @skip_filename = skip_filename
    end

    def consolidate!
      lines = {}
      blogroll_lines = File.read(@current_urls_filename).split("\n")
      blogroll_lines.each do |line|
        url, _tags = line.split(" ")
        lines[url] = line
      end
      File.read(@candidate_url_filename).split("\n").each do |url|
        uri = URI.parse(url)
        next if lines.key?(url)
        uri.scheme = 'http'
        next if lines.key?(uri.to_s)
        uri.scheme = 'https'
        next if lines.key?(uri.to_s)
        lines[url] ||= "#{url} batch-loaded"
      end
      File.open(@merged_filename, 'w+') do |file|
        lines.values.each do |line|
          file.puts line
        end
      end
    end
  end
end
