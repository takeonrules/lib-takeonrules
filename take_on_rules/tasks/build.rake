desc "Publish changes to https://takeonrules.com"
task publish: :build do
  Rake::Task["audit"].invoke(true, 0)
  project_sha = `cd #{PROJECT_PATH} && git log --pretty=format:'%H' -1`.strip
  message = "Site updated at #{Time.now.utc}\n\nUsing SHA1 #{project_sha}\nfrom source repository\n\n\\`\\`\\`console\n$ bundle exec rake publish\n\\`\\`\\`"
  $stdout.puts "Committing ./public pages"
  system("cd #{PUBLIC_PATH} && git checkout gh-pages && git add . && git commit -am '#{message}' && git checkout master && git rebase gh-pages")
  $stdout.puts "Pushing ./public pages"
  system("cd #{PUBLIC_PATH} && git push origin gh-pages && git push origin master")
  $stdout.puts "Updating project's pointer for ./public submodule"
  system(%(cd #{PROJECT_PATH} && git add public && git commit -m "#{message}" && git push origin master))
end

namespace :maintenance do
  # A script that crawls the posts looking for licenses to apply; Envisioned as a one-time script
  # but here for reference
  task :add_license do
    require 'psych'
    TakeOnRules::Site.each_project_filename(matching: 'content/posts/**/*.md') do |filename|
      file_with_frontmatter_and_content = FileWithFrontmatterAndContent.load(filename: filename)
      file_with_frontmatter_and_content.frontmatter["licenses"] ||= []
      if file_with_frontmatter_and_content.tags.include?("open game content")
        file_with_frontmatter_and_content.frontmatter["licenses"] += ["ogl"]
      else
        file_with_frontmatter_and_content.frontmatter["licenses"] += ["by-nc-nd-4_0"]
      end
      file_with_frontmatter_and_content.write!
    end
  end
end

namespace :build do
  desc 'Remove all, except .git, files in ./public'
  task :cleanDestinationDir do
    require 'fileutils'
    if !system("cd #{PUBLIC_PATH} && git checkout gh-pages && git reset --hard && git clean -df && git pull --rebase")
      $stderr.puts "Error cleaning destination directory, see above messages"
      exit!(1)
    end
    TakeOnRules::Site.each_project_filename(matching: 'public/*') do |filename|
      next if filename =~ /\.git$/
      FileUtils.rm_rf(filename)
    end
  end
  desc "Use hugo to build the ./public dir"
  task hugo: ["build:guard", "build:cleanDestinationDir"] do
    $stdout.puts "Building hugo site to ./public"
    if !system("cd #{PROJECT_PATH}; hugo")
      $stderr.puts "\tError building website"
      exit!(2)
    end
  end
  desc 'Using the ./data/redirects.yml, build redirects in ./public'
  task redirects: ["build:hugo"] do
    $stdout.puts "Creating Redirects…"
    require 'fileutils'
    require 'psych'
    redirects_file = TakeOnRules::Site.each_project_filename(matching: 'data/redirects.yml').first
    Psych.load_file(redirects_file).each do |redirect|
      TakeOnRules::Site.create_redirect_page_for(
        from_slug: File.join('/', redirect.fetch('from'), '/'),
        to_slug: redirect.fetch('to'),
        skip_existing_file: redirect.fetch('skip_existing_file')
      )
    end
    $stdout.puts "\tDone Creating Redirects"
  end

  desc "Extract metadata for YAML files"
  task metadata_extration: ["build:hugo"] do
    require 'nokogiri'
    $stdout.puts "Extracting Metadata…"
    registry = Registry.new
    TakeOnRules::Site.each_project_filename(matching: "public/**/*.html") do |filename|
      next if filename =~ AMP_FILENAME_REGEXP
      content = File.read(filename)
      doc = Nokogiri::HTML(content)

      json_as_string = nil
      doc.css('script').each do |node|
        if node['type'] == 'application/ld+json'
          json_as_string = node.text
        end
      end
      # Because not all pages have JSON-LD representations
      next unless json_as_string
      json = JSON.parse(json_as_string)

      doc.css('blockquote').each do |node|
        registry.add(type: :quote, filename: filename, node: node, json_for_page: json)
      end

      doc.css('.content a').each do |node|
        registry.add(type: :link, filename: filename, node: node, json_for_page: json)
      end
    end
    registry.dump!(commit: true)
    $stdout.puts "\tDone Extracting Metadata"
    # Necessary, as we've extracted metadata from the generated HTML, and need to feed that
    # back into the system.
    Rake::Task['build:hugo'].execute
  end

  desc 'Working with the existing files, build AMP friendly versions in ./public'
  task amplify: ["build:hugo"] do
    require 'nokogiri'
    $stdout.puts "Amplifying the content…"

    # Because there are style declarations that should not be included as they violate
    # AMP requirements
    tufte_amp_filename = TakeOnRules::Site.each_project_filename(matching: "public/css/tufte-amp.*.css").first
    stylesheet_content = File.read(tufte_amp_filename)
    stylesheet_content.sub!('@charset "UTF-8";','')

    # These scripts need to be injected into every page
    base_amp_scripts = []
    base_amp_scripts << %(<style amp-custom>#{stylesheet_content}</style>)
    base_amp_scripts << %(<style amp-boilerplate>body{-webkit-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-moz-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-ms-animation:-amp-start 8s steps(1,end) 0s 1 normal both;animation:-amp-start 8s steps(1,end) 0s 1 normal both}@-webkit-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-moz-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-ms-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-o-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}</style><noscript><style amp-boilerplate>body{-webkit-animation:none;-moz-animation:none;-ms-animation:none;animation:none}</style></noscript>)
    base_amp_scripts << %(<script async src="https://cdn.ampproject.org/v0.js"></script>)
    base_amp_scripts << %(<script async custom-element="amp-form" src="https://cdn.ampproject.org/v0/amp-form-0.1.js"></script>)
    base_amp_scripts << %(<script async custom-element="amp-analytics" src="https://cdn.ampproject.org/v0/amp-analytics-0.1.js"></script>)

    TakeOnRules::Site.each_project_filename(matching: "public/**/*.html") do |filename|
      next if filename.start_with?(File.join(PUBLIC_PATH, 'assets'))
      next if filename.start_with?(File.join(PUBLIC_PATH, 'css'))
      next if filename.start_with?(File.join(PUBLIC_PATH, 'fonts'))
      next if filename.start_with?(File.join(PUBLIC_PATH, 'amp'))
      # Skipping tag as those are now in tags/
      next if filename.start_with?(File.join(PUBLIC_PATH, 'tag/'))

      amp_scripts = base_amp_scripts.clone

      # Checking blog posts
      if filename =~ /\/\d{4}\//
        amp_filename = filename.sub(/\/(\d{4})\//, '/amp/\1/')
      else
        # Checking pages
        amp_filename = filename.sub(PUBLIC_PATH, File.join(PUBLIC_PATH, 'amp'))
      end
      FileUtils.mkdir_p(File.dirname(amp_filename))
      content = File.read(filename)

      # Ensure that HTML is marked as AMP ready
      content.sub!(/^ *\<html /, '<html amp ')
      content.sub!(%(manifest="/cache.appcache"), '')
      content.sub!("hide-when-javascript-disabled", '')
      content.gsub!(/\<details +(closed|open)/, "<span")
      content.gsub!(/\<(\/?)(summary|details)/, '<\1span')

      doc = Nokogiri::HTML(content)
      doc.css('img').each do |node|
        amp_img = doc.create_element('amp-img')
        src = node.get_attribute('src')
        width = node.get_attribute('data-width')
        height = node.get_attribute('data-height')
        amp_img.set_attribute('src', src)
        amp_img.set_attribute('width', width)
        amp_img.set_attribute('height', height)
        amp_img.set_attribute('layout', 'responsive')
        node.replace amp_img
      end

      added_iframe_script = false
      doc.css('iframe').each do |node|
        amp_iframe = doc.create_element('amp-iframe')
        node.attributes.each do |key, value|
          next if key == 'marginheight'
          next if key == 'marginwidth'
          amp_iframe.set_attribute(key, value.to_s)
        end
        amp_iframe.set_attribute('sandbox', "allow-scripts allow-same-origin")
        amp_iframe.set_attribute('layout', "responsive")
        noscript = doc.create_element('noscript')
        noscript << node.clone
        node.parent << noscript
        node.replace amp_iframe
        next if added_iframe_script
        added_iframe_script = true
        amp_scripts << %(<script async custom-element="amp-iframe" src="https://cdn.ampproject.org/v0/amp-iframe-0.1.js"></script>)
      end

      doc.css('script').each do |node|
        next if node['type'] == 'application/ld+json'
        node.remove
      end

      doc.css('link[media]').each(&:remove)
      doc.css('link[rel=preload]').each(&:remove)
      doc.css('link[rel=stylesheet]').each(&:remove)
      doc.css('style').each(&:remove)
      doc.css('meta[name=amp-css-name]').each(&:remove)

      # Because the license contains several problematic amp attributes,
      # I'm removing that license
      doc.css('.credits .license').each(&:remove)
      content = doc.to_html

      content.sub!("</head>", amp_scripts.join("\n") + "\n</head>")

      File.open(amp_filename, 'w+') { |f| f.puts content }
    end
    $stdout.puts "\tDone Amplifying"
  end

  desc 'Beautify the HTML of the sites'
  task beautify: ["build:hugo", "build:redirects", "build:amplify"] do
    $stdout.puts "Beautfying the HTML…"
    # Redirects and resulting amp pages should be beautiful too
    require 'htmlbeautifier'
    require 'nokogiri'
    require 'json'
    TakeOnRules::Site.each_project_filename(matching: "public/**/*.html") do |filename|
      messy = File.read(filename)
      doc = Nokogiri::HTML(messy)
      doc.css('script').each do |node|
        next unless node['type'] == 'application/ld+json'
        begin
          json = JSON.dump(JSON.load(node.content))
          node.content = json
        rescue JSON::ParserError => e
          $stderr.puts "JSON parse error encountered in #{filename}"
          raise e
        end
      end
      messy = doc.to_html
      beautiful = HtmlBeautifier.beautify(messy, indent: "\t")
      File.open(filename, 'w+') do |f|
        f.puts beautiful
      end
    end
    $stdout.puts "\tDone Beautifying"
  end

  task duplicate_feed: ["build:hugo"] do
    # Because some sources have https://takeonrules.com/feed/ I need to resolve that behavior
    require 'fileutils'
    $stdout.puts "Duplicating and building externally published feeds"
    feed = File.join(PUBLIC_PATH, 'feed.xml')
    alternate_feed = File.join(PUBLIC_PATH, 'feed/index.xml')
    FileUtils.mkdir_p(File.join(PUBLIC_PATH, "feed"))
    FileUtils.cp(feed, alternate_feed)
  end

  namespace :blogroll do
    desc "Synchronize from RSS URLs"
    task :synchronize do
      require 'psych'
      rss_urls = File.expand_path("../../../../rss/urls.txt", __FILE__)
      urls = []
      File.read(rss_urls).split("\n").each do |line|
        entries = line.split(" ")
        next if entries.grep("blogroll").empty?
        urls << entries[0]
      end
      blogroll_yml = File.expand_path("../../../../data/blogroll.yml", __FILE__)
      File.open(blogroll_yml, "w+") do |file|
        file.puts Psych.dump(urls.sort)
      end
    end
    desc "Fetch blogroll entries"
    task :fetch do
      if ENV["NO_BLOGROLL"]
        $stdout.puts "Skipping blog roll"
        next
      end
      $stdout.puts "Fetching blog roll entries"
      require 'faraday'
      require 'nokogiri'
      require 'time'
      require 'psych'
      require 'feedjira'
      require 'uri'

      class BlogRollEntry
        attr_reader :site_url, :item_pubDate, :item_title, :item_url, :author
        def initialize(xml:)
          feed = Feedjira.parse(xml)
          item = feed.entries.first
          uri = URI.parse(feed.url)
          @site_url = "#{uri.scheme}://#{uri.host}"
          @site_title = feed.title
          @item_pubDate = item.published.strftime('%Y-%m-%d %H:%M:%S %z')
          @item_url = item.url
          if item.title
            @item_title = item.title
          else
            @item_title = item.url.split("/").last.sub(/\.\w+$/, '').gsub(/\W+/, ' ')
          end
        end

        include Comparable
        def <=>(other)
          comparison = item_pubDate <=> other.item_pubDate
          return comparison unless comparison == 0
          site_title.to_s <=> other.site_title.to_s
        end

        def site_title
          @site_title || site_url.sub(/^https?:\/\//,'')
        end

        def to_hash
          {
            "site_url" => site_url,
            "site_title" => site_title,
            "item_pubDate" => item_pubDate,
            "item_title" => item_title,
            "item_url" => item_url
          }
        end
      end

      entries = []
      blogroll = Psych.load_file(File.join(PROJECT_PATH, 'data/blogroll.yml'))
      blogroll.each do |feed_url|
        begin
          $stdout.puts "\tFetching #{feed_url}"
          response = Faraday.get(feed_url)
          entries << BlogRollEntry.new(xml: response.body)
        rescue Faraday::TimeoutError
          $stderr.puts "\t\tWARNING: Timeout for #{feed_url}, moving on"
        rescue Feedjira::NoParserAvailable
          $stderr.puts "\t\tERROR: Encountered an error for #{feed_url}, moving on"
        end
      end

      output = entries.sort.reverse.map(&:to_hash)

      File.open(File.join(PROJECT_PATH, 'data/blogroll_entries.yml'), 'w+') do |f|
        f.puts Psych.dump(output)
      end
      blogroll_filename = File.join(PROJECT_PATH, 'content/blog-roll/index.md')
      blogroll = FileWithFrontmatterAndContent.load(filename: blogroll_filename)
      # blogroll.write!(update: true)
    end

    desc "Commit blogroll entries"
    task commit: ["build:blogroll:fetch"] do
      if ENV["NO_BLOGROLL"]
        $stdout.puts "Skipping blog roll"
        next
      end
      message = "Updating blogroll entries\n\n\\`\\`\\`console\n$ bundle exec rake publish:blogroll\n\\`\\`\\`"
      TakeOnRules::Site.commit!(files: ["data/blogroll_entries.yml"], message: message)
    end
  end
  desc "Process blog roll entries"
  task blogroll: ["build:blogroll:synchronize", "build:blogroll:fetch", "build:blogroll:commit"]

  desc "Pre Build Content: Sort frontmatter alphabetically"
  task pre_build_content: ["build:pre_build_content:main","build:pre_build_content:commit"]
  namespace :pre_build_content do
    task main: ["build:guard"] do
      require 'psych'
      $stdout.puts "Sorting front matter and extracting images"
      TakeOnRules::Site.each_project_filename(matching: 'content/**/*.md') do |filename|
        file_with_frontmatter_and_content = FileWithFrontmatterAndContent.load(filename: filename)
        file_with_frontmatter_and_content.metadata_for_images
        file_with_frontmatter_and_content.write!
      end
      ImageMetadata.dump!
    end
    task commit: ["build:pre_build_content:main"] do
      message = "Updating content via pre_build\n\n\\`\\`\\`console\n$ bundle exec rake build:pre_build_content\n\\`\\`\\`"
      $stdout.puts "Committing prebuild content"
      TakeOnRules::Site.commit!(files: [IMAGE_METADATA_FILE_PATH], paths: ["content"], message: "#{message}")
    end
  end

  desc "Guard against an unclean working directory"
  task :guard do
    if `cd #{PROJECT_PATH}; git status`.include?("working tree clean")
      $stdout.puts "Working tree clean, proceeding with build"
    else
      unless ENV['SKIP_GUARD']
        $stderr.puts "ERROR: Working tree dirty, please review changes"
        exit!(1)
      end
    end
  end

  task check_hugo_template: ["build:hugo"] do
    # Likely indicates a change in API for Hugo
    if system("ag -l '\\\\n{\\\\n  \\\\\"@context' #{File.join(PUBLIC_PATH, '**')}")
      $stderr.puts("ERROR: Encountered '\\\\n{\\\\n  \\\\\"@context' in public directory. Something is amiss with the build.")
      exit!(4)
    end
  end

end

desc "Build the hugo site for production"
task build: ["build:guard", "metadata", "build:blogroll", "build:pre_build_content", "build:hugo", "build:redirects", "build:metadata_extration", "build:amplify", "build:beautify", "build:duplicate_feed", "build:check_hugo_template"] do
  Rake::Task["audit"].invoke(true, 0)
end
