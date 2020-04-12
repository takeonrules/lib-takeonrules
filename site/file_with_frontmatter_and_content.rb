require_relative "./image_metadata"
module TakeOnRules
  module Site
    # Exposes a common data structure for interacting with a page/post
    class FileWithFrontmatterAndContent
      REGEXP_FOR_IMAGE = %r{\{\{[\%\<] (marginfigure|maincolumn)}
      def self.load(filename:)
        frontmatter_text = ''
        content = ''
        frontmatter = nil
        tables = []
        images = []
        quotes = []
        File.readlines(filename).each do |line|
          if line.strip == '---'
            if frontmatter.nil?
              frontmatter = true
              next
            elsif frontmatter == true
              frontmatter = false
            end
          elsif frontmatter
            frontmatter_text += line
          else
            content += line
            if REGEXP_FOR_IMAGE =~ line
              images << line.strip
            end
          end
        end
        frontmatter = Psych.load(frontmatter_text)
        new(filename, frontmatter, content, tables, images, quotes)
      end

      attr_reader :filename, :frontmatter, :tables, :images, :quotes
      attr_accessor :body
      def initialize(filename, frontmatter, body, tables = [], images = [], quotes =[])
        @filename = filename
        @frontmatter = frontmatter
        @body = body
        @tables = tables
        @images = images
        @quotes = quotes
      end

      def open(host:)
        `open #{File.join(host, permalink)}`
      end

      def open_editor
        `atom #{filename}`
      end

      def write!(update: false)
        self.frontmatter["lastmod"] = Time.now if update
        File.open(filename, 'w+') do |f|
          f.puts content
        end
      end

      def content
        [Psych.dump(sorted_frontmatter).strip, '---', body].join("\n")
      end

      def tags
        frontmatter.fetch("tags", [])
      end

      def permalink
        frontmatter.fetch("permalink") do
          "/#{publication_date.strftime('%Y/%m/%d')}/#{slug}/"
        end
      end

      def slug
        frontmatter.fetch('slug')
      rescue => e
        $stderr.puts "Error in filename: #{filename}"
        raise e
      end

      def title
        frontmatter.fetch('title')
      rescue => e
        $stderr.puts "Error in filename: #{filename}"
        raise e
      end

      def publication_date
        value = frontmatter.fetch('date')
        case value
        when Date, Time, DateTime
          value
        when String
          Date.parse(value).to_time
        else
          raise "Expected a date for #{date.inspect} (with slug #{slug})"
        end
      rescue => e
        $stderr.puts "Error in filename: #{filename}"
        raise e
      end

      def metadata_for_images
        images.map do |line|
          ImageMetadata.new(line: line).to_hash
        end
      end

      include Comparable
      def <=>(other)
        publication_date <=> other.publication_date
      end

      def sorted_frontmatter
        returning_value = {}
        frontmatter.delete("images")
        frontmatter["images"] = metadata_for_images
        sorted_frontmatter = frontmatter.sort { |a,b| a[0] <=> b[0] }
        sorted_frontmatter.each do |key, value|
          if value.is_a?(Array)
            begin
              returning_value[key] = value.sort
            rescue ArgumentError
              returning_value[key] = value
            end
          else
            returning_value[key] = value
          end
        end
        returning_value
      end
    end
  end
end
