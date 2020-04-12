module TakeOnRules
  module Site
    class Registry
      INDEX_FILENAME_REGEXP = /index\.html\Z/.freeze
      CITE_REGEXP = /\<(\/?)cite\>/.freeze
      # Note that is an mdash;
      MDASH_PREFIX_REGEXP = /^— */.freeze
      TAB_AND_NEWLINE_REGEXP = /[\n\t]/.freeze
      class Base
        attr_reader :path, :filename, :quote, :footer, :path, :json_for_page, :node
        def initialize(filename:, node:, json_for_page:)
          @filename = filename
          @node = node
          @json_for_page = json_for_page
          @path = File.join('/', filename.sub(PUBLIC_PATH, '').sub(INDEX_FILENAME_REGEXP,''), '/')
          initialize_from_output
        end

        include Comparable
        def <=>(other)
          comparison = publication_date <=> other.publication_date
          return comparison unless comparison == 0
          path <=> other.path
        end
        def publication_date
          @publication_date ||=  @json_for_page.fetch("datePublished")
        end
        def page_title
          json_for_page.fetch("name")
        end

        def skip?
          return true if path == "/"
          return true if PAGINATION_PATH_REGEXP.match(path)
        end

        def self.to_hash(entries:)
          entries.sort.map(&:to_hash)
        end
      end
      class Quote < Base
        def initialize_from_output
          return if skip?
          @citation = ""
          node.css("footer").each do |footer_node|
            @citation += footer_node.inner_html.strip.
              sub("<cite>", "<em>").
              sub("</cite>", "</em> ").
              sub(MDASH_PREFIX_REGEXP, "").
              gsub(TAB_AND_NEWLINE_REGEXP, '').
              strip
            footer_node.remove
          end
          @quote = node.inner_html.strip.
            gsub("<p>", "").
            gsub("</p>", "<br /><br />").
            gsub(TAB_AND_NEWLINE_REGEXP, '').
            gsub(%r{<br /><br />\Z}, '')
        end

        def to_hash
          hash = { "publication_date" => publication_date, "page_title" => page_title, "path" => @path, "quote" => @quote }
          hash["citation"] = @citation unless @citation.empty?
          hash
        end

        def self.filename
          File.join(PROJECT_PATH, 'data/list_of_all_quotes.yml')
        end
      end

      class Link < Base
        def self.filename
          File.join(PROJECT_PATH, 'data/list_of_all_external_links.yml')
        end
        attr_reader :href, :caption
        def initialize_from_output
          if @node.attributes.key?("href")
            @href = @node.attributes["href"].value
            @caption = @node.inner_html
          end
        end

        SKIPPABLE_PATH_REGEXP = %r{^/(metadata|blog-roll)/}
        def skip?
          return true if super
          return true if path.match(SKIPPABLE_PATH_REGEXP)
          return true if href.nil?
          return true if internal_href?
        end

        def <=>(other)
          [href, publication_date, path] <=> [other.href, other.publication_date, other.path]
        end

        def to_hash
          { "publication_date" => publication_date, "page_title" => page_title, "path" => path, "caption" => caption, "href" => href }
        end

        def self.to_hash(entries:)
          registry = {}
          entries.each do |entry|
            href = entry.href
            registry[href] ||= []
            registry[href] << entry
          end
          registry.map do |href, entries|
            {
              "href" => href,
              "entries" => entries.uniq.sort.map(&:to_hash)
            }
          end
        end

        private

        EXTERNAL_HREF_PATTHER = %r{https?://}
        TAKEONRULES_DOT_COM_REGEXP = %r{https?://takeonrules.com}
        def internal_href?
          return true if TAKEONRULES_DOT_COM_REGEXP.match(href)
          return true unless EXTERNAL_HREF_PATTHER.match(href)
        end
      end

      TYPE_TO_BUILDER_MAP = {
        quote: Quote,
        link: Link
      }

      def initialize
        @registry = {}
      end

      def add(type:, **kwargs)
        builder = TYPE_TO_BUILDER_MAP.fetch(type)
        @registry[type] ||= []
        object = builder.new(**kwargs)
        @registry[type] << object unless object.skip?
      end

      def dump!(commit: false)
        @registry.each do |type, entries|
          builder = TYPE_TO_BUILDER_MAP.fetch(type)
          File.open(builder.filename, 'w+') do |f|
            f.puts(Psych.dump(builder.to_hash(entries: entries)))
          end
          return unless commit
          Site.commit!(files: [builder.filename], message: "Updating list of all #{type}")
        end
      end

      private

      def data_to_dump
        @registry.sort.map(&:to_hash)
      end
    end
  end
end
