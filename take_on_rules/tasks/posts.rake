namespace :post do
  desc "Inject lastmod date on content not yet committed"
  task :lastmod do
    changed_files = `git status --porcelain`.split("\n")
    changed_files.each do |changed_file|
      status, path = changed_file.split(" ")
      next unless status == "M"
      next unless path =~ /^\/?content/
      filename = File.join(PROJECT_PATH, path)
      file = FileWithFrontmatterAndContent.load(filename: filename)
      file.write!(update: true)
      `git add #{path}`
    end
  end

  LOCAL_HOST = "http://localhost:1313".freeze
  desc "Review modified by opening in browser, defaults to #{LOCAL_HOST}"
  task :review, [:host] do |task, args|
    host = args.fetch(:host, LOCAL_HOST)
    changed_files = `git status --porcelain`.split("\n")
    changed_files.each do |changed_file|
      status, path = changed_file.split(" ")
      next unless status == "M"
      next unless path =~ /^\/?content/
      filename = File.join(PROJECT_PATH, path)
      file = FileWithFrontmatterAndContent.load(filename: filename)

      $stdout.puts "Editing #{filename.sub(PROJECT_PATH, "")}"
      sleep(0.5)
      file.open(host: host)
      file.open_editor
    end
  end

  desc "Create a new post `new_post[\"Your Title Here\"]'"
  task :new, [:title] do |task, args|
    require 'fileutils'
    title = args.fetch(:title, "")
    require 'time'
    require 'psych'
    now = Time.now
    slug = title.gsub(/'/, "").gsub(/\W+/, "-").downcase.sub(/^-+/,'').sub(/-+$/,'')
    while title =~ /"/
      # Close double quotes
      title = title.sub('"', "“").sub('"',"”")
    end
    frontmatter = {
      "date" => now,
      "layout" => "post",
      "slug" => slug,
      "title" => title,
      "type" => "post"
    }

    filename = File.join(PROJECT_PATH, "content", "posts", "#{now.year}", "#{now.strftime("%Y-%m-%d-")}#{slug}.md")
    FileUtils.mkdir_p(File.dirname(filename))
    File.open(filename, "w+") do |f|
      f.puts Psych.dump(frontmatter)
      f.puts "---"
    end
    system("atom #{filename}")
  end
  task :update_series do
    TakeOnRules::Site.each_project_filename(matching: "content/posts/**/*.*") do |filename|
      file = FileWithFrontmatterAndContent.load(filename: filename)
      if file.frontmatter.key?('series')
        next
      elsif file.tags.include?('review')
        file.frontmatter['series'] = 'reviews'
        file.write!(update: true)
      elsif file.tags.include?('interview')
        file.frontmatter['series'] = 'interviews'
        file.write!(update: true)
      end
    end
  end
  task :update do
    urls = []
    TakeOnRules::Site.each_project_filename(matching: "content/**/*.*").each do |filename|
      changed = false
      lines = File.read(filename).split("\n")
      lines.each do |line|
        urls.each do |url|
          if line.include?(url)
            changed = true
            ssl_url = url.sub("http:", "https:")
            line.gsub!(url, ssl_url)
          end
        end
      end
      next unless changed
      File.open(filename, "w+") do |file|
        lines.each do |line|
          file.puts line
        end
      end
    end
  end
  task :crawl, [:filename] do |task, args|
    require 'faraday'
    filename = args.fetch(:filename, "urls-not-ssl.txt")
    visited = []
    has_ssl = []
    gone = []
    File.read(filename).split.sort.each do |url|
      begin
        uri = URI.parse(url)
        next if visited.include?(uri.host)
        next if uri.scheme == "https"
        visited << uri.host
        response = Faraday.get("https://#{uri.host}#{uri.path}")
        if response
          $stdout.puts "SSL\t#{url}"
          has_ssl << url
        end
      rescue Faraday::SSLError
        $stdout.puts "NOSSL\t#{url}"
      rescue Faraday::ConnectionFailed
        $stdout.puts "GONE\t#{url}"
        gone << url
      end
    end
  end
end
task post: ["post:new"]
