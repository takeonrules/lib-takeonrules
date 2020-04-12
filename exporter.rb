require 'nokogiri'
require 'open-uri'
require 'markdown-tables'
module TakeOnRules
  # A module that contains logic for exporting content to other formats.
  #
  # @see TakeOnRules::Exporter::Converter::RedditMarkdown
  # @see TakeOnRules::Exporter::Converter::RpggeekMarkdown
  module Exporter
    def self.call(path:, to:)
      converter = CONVERTERS.fetch(to).new
      Parser.call(path: path, converter: converter)
    end
    module Converter
      class Base
        def ogc_preambler
          sidenoter(lines: [%(All non-image content between the Begin "OPEN GAME CONTENT" and "End OPEN GAME CONTENT" is "Open Game Content". All other content not declared as "Open Game Content" is "Product Identity".)])
        end
      end
      class RedditMarkdown < Base
        def canonical_line(url)
          "**Originally posted at [Take on Rules](#{url})**"
        end

        def footer(text)
          text
        end

        def h_tag(tag:, text:)
          text = escaper(text)
          case tag
          when "h1", "h2"
            "# #{text}"
          when "h3"
            "**#{text}**"
          when "h4"
            "*#{text}*"
          else
            text
          end
        end

        def a_tag(href:, text:)
          "[#{escaper(text)}](#{href})"
        end

        def blockquoter(lines:)
          lines.map do |line|
            ">#{line}"
          end.join("\n>\n")
        end

        def sidenoter(lines:)
          output = []
          lines.each_with_index do |line, index|
            if index == 0
              output << "SIDENOTE: #{line}"
            else
              output << "#{line}"
            end
          end
          "^(#{output.join(" ")})"
        end

        def newthoughter(text:)
          text = escaper(text)
          "**#{text}**"
        end

        def image_tag(*args)
        end

        def finalize_line(line:)
          line.join(" ").strip.gsub("[/url] )", "[/url])").gsub("\n ", "\n")
        end

        def simple_tag(tag:, text:)
          text = escaper(text)
          case tag
          when "strong", "b"
            "**#{text}**"
          when "em", "i"
            "*#{text}*"
          when "del", "s"
            "~~#{text}~~"
          else
            raise "#{self.class}#simple_tag case for #{tag} not implemented"
          end
        end

        def with_table_buffer
          text = ""
          yield(text)
          text
        end

        def table_caption(caption:)
          "**#{escaper(caption)}**"
        end

        def render_table(table:)
          "\n#{table}"
        end

        CONTROLLED_CHARCTERS_REGEXP = %r{([\^\*\#~])}
        def escaper(text)
          text.gsub(CONTROLLED_CHARCTERS_REGEXP) do |char|
            "\\#{char}"
          end
        end

      end

      class RpggeekMarkdown < Base
        FONT_SIZE_MAP = {
          "h1" => 24,
          "h2" => 24,
          "h3" => 18,
          "h4" => 14,
          "footer" => 8,
          "newthought" => 14
        }.freeze

        def canonical_line(url)
          "[b]Originally posted at [url=#{url}]Take on Rules[/url][/b]"
        end

        def footer(text)
          "[i][size=#{FONT_SIZE_MAP.fetch("footer")}]#{text}[/size][/i]"
        end

        SIMPLE_TAG_MAP = {
          "code" => "c",
          "em" => "i",
          "i" => "i",
          "s" => "-",
          "del" => "-",
          "strong" => "b",
          "b" => "b"
        }.freeze
        def simple_tag(tag:, text:)
          mapped_tag = SIMPLE_TAG_MAP.fetch(tag)
          "[#{mapped_tag}]#{text}[/#{mapped_tag}]"
        end

        def h_tag(tag:, text:)
          size = FONT_SIZE_MAP.fetch(tag)
          "[size=#{size}]#{text}[/size]"
        end

        def a_tag(href:, text:)
          "[url=#{href}]#{text}[/url]"
        end

        def image_tag(src:)
          "[IMG]#{src}[/IMG]"
        end

        def finalize_line(line:)
          line.join(" ").strip.gsub("[/url] )", "[/url])").gsub("\n ", "\n")
        end

        def blockquoter(lines:)
          lines.unshift("[q]")
          lines.push("[/q]")
          lines.map(&:strip).join("\n\n")
        end

        def sidenoter(lines:)
          lines.unshift("[COLOR=#9900CC][i][size=9]")
          lines.push("[/size][/i][/COLOR]")
          lines.map(&:strip).join(" ")
        end

        def newthoughter(text:)
          "[i][b][size=#{FONT_SIZE_MAP.fetch("newthought")}]#{text}[/size][/b][/i]"
        end

        def render_table(table:)
          MarkdownTables.plain_text(table)
        end

        def table_caption(caption:)
          "[b]#{caption}[/b]"
        end
        def table_footer(footer:)
          "[i]#{footer}[/i]"
        end
        def with_table_buffer
          text = "[c]\n"
          yield(text)
          text += "\n[/c]"
          text
        end
      end
    end
    CONVERTERS = {
      rpggeek: Converter::RpggeekMarkdown,
      reddit: Converter::RedditMarkdown
    }
    # Responsible for converting an HTML document to a RPGGeek format
    # object.
    #
    # The parser needs to include a buffer. At present, I'm writing to a line
    # but that line sometimes gets joined as a string.
    class Parser
      def self.call(path:, converter:)
        new(path: path, converter: converter).call.to_s
      end

      attr_reader :content, :path, :converter
      def initialize(path:, converter:)
        @path = path
        @content = open(path)
        @converter = converter
        @output = []
      end

      def call
        doc = Nokogiri::HTML(content)
        title = doc.css("article header h1").text.strip
        @output << "# #{title}"
        canonical_url = doc.css('link[rel=canonical]').attribute("href").value
        canonical_line = converter.canonical_line(canonical_url)
        @output << canonical_line

        body = doc.css(".content").first
        raise "Empty content for #{path.inspect}. Cannot process" unless body
        body.children.each do |node|
          line = []
          handle(node: node, line: line)
          @output << converter.finalize_line(line: line) unless line.all?(&:empty?)
        end
        @output << canonical_line
        self
      end

      def to_s
        @output.join("\n\n")
      end

      private

      CONTROL_CHAR_REGEXP = %r{[\t\n]+}.freeze
      ANCHOR_TAG_REGEXP =  %r{^\#}.freeze
      def handle(node:, line:)
        case node.name.downcase
        when "sup", "sub", "iframe", "script", "noscript", "aside", "details", "hr", "br", "label", "input"
          :ignore
        when "footer"
          line << converter.footer(node.text.gsub(CONTROL_CHAR_REGEXP,' '))
        when "code", "em", "s", "strong", "i", "b", "del"
          line << converter.simple_tag(tag: node.name, text: node.text.strip)
        when "text", "cite", "time"
          text = node.text.strip
          line << text unless text.empty?
        when "h1", "h2", "h3", "h4"
          line << converter.h_tag(tag: node.name, text: node.text.strip)
        when "ul", "ol", "dl"
          node.children.each do |child|
            handle(node: child, line: line)
          end
        when "li"
          inner_line = ["*"]
          node.children.each do |child|
            handle(node: child, line: inner_line)
          end
          inner_line[-1] += "\n"
          line << inner_line.join(" ")
        when "p"
          inner_line = []
          node.children.each do |child|
            handle(node: child, line: inner_line)
          end
          line << inner_line.join(" ")
        when "section"
          if node.classes.include?("open-game-content")
            link = converter.a_tag(href: "https://takeonrules.com/open-game-license/", text: "OPEN GAME CONTENT")
            inner_line = ["#{converter.ogc_preambler}\n\nBEGIN #{link}"]
            node.children.each do |child|
              handle(node: child, line: inner_line)
            end
            inner_line += ["END OPEN GAME CONTENT"]
            line << inner_line.map(&:strip).join("\n\n")
          else
            raise "Unable to handle SECTION"
          end
        when "blockquote"
          inner_lines = []
          node.children.each do |child|
            handle(node: child, line: inner_lines)
          end
          line << converter.blockquoter(lines: inner_lines)
        when "pre"
          line
        when "a"
          href_node =  node.attribute("href")
          return unless href_node
          href = href_node.value
          if href =~ ANCHOR_TAG_REGEXP
            line << "#{node.text.strip}"
          else
            line << converter.a_tag(href: href, text: node.text.strip)
          end
        when "div", "section"
          if node.classes.include?("table-wrapper")
            node.children.each do |child|
              handle(node: child, line: line)
            end
          else
            raise "Unable to handle #{node.name.upcase}"
          end
        when "table"
          handle_table(node: node, line: line)
        when "span"
          if node.classes.include?("marginfigure")
            img = node.css("img").first
            line << converter.image_tag(src: img.attribute("src").value) if img
          elsif node.classes.include?("sidenote") || node.classes.include?("marginnote")
            inner_lines = []
            node.children.each do |child|
              handle(node: child, line: inner_lines)
            end
            line << converter.sidenoter(lines: inner_lines)
          elsif node.classes.include?("newthought")
            line << converter.newthoughter(text: node.text)
          end
        when "figure"
          img = node.css("img").first
          line << converter.image_tag(src: img.attribute("src").value) if img
        else
          raise "Unable to handle #{node.name.upcase}"
        end
      end

      # @note I don't know the results of rows with colspan or columns
      # with rowspans. This also ignores links within the table.
      def handle_table(node:, line:)
        table = Table.new(node: node, converter: converter)
        table.extract!
        line << table.to_line
      end

      class Table
        attr_accessor :caption, :headers, :rows, :footer, :converter
        attr_reader :node
        def initialize(node:, converter:)
          @node = node
          @converter = converter
          @rows = []
          @footer = []
        end

        def extract!
          node.children.each do |child|
            case child.name
            when "caption"
              self.caption = child.text
            when "thead"
              self.headers = child.css("tr th").map { |th| th.text.strip }
            when "tbody"
              child.css("tr").each do |tr|
                row = []
                tr.children.each do |tr_child|
                  cell_text = tr_child.text.gsub(CONTROL_CHAR_REGEXP, "").strip
                  row << cell_text unless cell_text.empty?
                end
                self.rows << row
              end
            when "tfoot"
              child.css("tr").each do |tr|
                self.footer << tr.children.map(&:text).join(" ").gsub(CONTROL_CHAR_REGEXP, "").strip
              end
            end
          end
        end

        def to_line
          normalize_headers_and_rows!
          table = MarkdownTables.make_table(headers, rows, is_rows: true)
          text = converter.with_table_buffer do |buffer|
            buffer << "#{converter.table_caption(caption: caption)}\n"
            buffer << converter.render_table(table: table)
            buffer << "\n#{converter.table_footer(footer: footer.join("\n"))}" unless footer.empty?
          end
          text
        end

        private
        def normalize_headers_and_rows!
          self.headers ||= []
          max_columns = (rows.map(&:count).uniq << headers.count).max
          rows.each do |row|
            next if row.size == max_columns
            while row.size < max_columns
              row << ""
            end
          end
          if headers.count < max_columns
            while headers.size < max_columns
              headers << ""
            end
          end
        end
      end
    end
  end
end
