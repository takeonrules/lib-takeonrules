module TakeOnRules
  module Site
    class ImageMetadata
      @@all_image_metadata = Psych.load(File.read(IMAGE_METADATA_FILE_PATH)) rescue {}

      def self.dump!
        File.open(IMAGE_METADATA_FILE_PATH, "w+") do |f|
          f.puts(Psych.dump(@@all_image_metadata))
        end
      end

      attr_reader :src, :height, :width, :alt
      def initialize(line:)
        @line = line
        extract_data_from_line!
        build_metadata!
      end

      def to_hash
        hash = { "src" => src, "height" => height, "width" => width }
        hash["alt"] = alt unless alt.empty?
        hash
      end

      private

      def extract_data_from_line!
        @src = TakeOnRules::Site.extract_shortcode_parameter("src", from: @line)
        @alt = TakeOnRules::Site.extract_shortcode_parameter("alt", from: @line)
      end

      def build_metadata!
        if @@all_image_metadata.key?(src)
          image_metadata = @@all_image_metadata.fetch(src)
          @height = image_metadata.fetch("height")
          @width = image_metadata.fetch("width")
        else
          filename = File.join(IMAGE_ASSET_BASE_PATH, src)
          image = MiniMagick::Image.open(filename)
          @height = image.height
          @width = image.width
        end
        @@all_image_metadata[src] = to_hash
      end
    end
  end
end
