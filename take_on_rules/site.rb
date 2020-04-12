require 'toml-rb'
require 'pry'
require 'mini_magick'

require_relative './site/constants'
require_relative './site/file_with_frontmatter_and_content'
require_relative './site/image_metadata'
require_relative './site/registry'
module TakeOnRules
  module Site
    def self.load_rake_tasks!
      each_project_filename(matching: "lib/take_on_rules/tasks/*.rake") do |filename|
        load filename
      end
    end

    def self.each_project_filename(matching:, &block)
      if block_given?
        Dir.glob(File.join(PROJECT_PATH, matching)).each(&block)
      else
        Dir.glob(File.join(PROJECT_PATH, matching)).to_enum(:each)
      end
    end

    def self.extract_shortcode_parameter(parameter, from:)
      contains = from.split(/#{parameter} *= */).last
      opening_quote = contains[0]
      contains.split(opening_quote)[1].strip
    end

    # Only commit the given files
    def self.commit!(files:[], message:, paths: [], push: false)
      commands = [
        "cd #{PROJECT_PATH}"
      ]
      paths.each do |path|
        $stdout.puts "\tCommiting: #{path}"
        commands << "git add #{path}"
      end
      files.each do |file|
        $stdout.puts "\tCommitting: #{file.sub(File.join(PROJECT_PATH,''), "")}"
        commands << "git add #{file}"
      end
      if push
        $stdout.puts "\tPushing commits"
        commands << "git push #{push}"
      end
      commands << %(git commit -m "#{message}")
      system(commands.join("; "))
    end

    def self.changed?(files:)
      is_changed = false
      files = files.map {|f| f.sub(File.join(PROJECT_PATH, ""), '') }
      changed_files = `cd #{Shellwords.escape(PROJECT_PATH)}; git status --porcelain`.split("\n")
      changed_files.each do |changed_file|
        _, path = changed_file.split(" ")
        next unless files.include?(path)
        $stderr.puts %(\tExpected "#{path}" not to have uncommitted changes)
        is_changed = true
      end
      is_changed
    end

    # Responsible for creating a redirect page based on the given paramters.
    # The page will redirect to the given :to_slug, from the given :from_slug
    def self.create_redirect_page_for(from_slug:, to_slug:, skip_existing_file: true)
      from_file_directory = File.join(PUBLIC_PATH, from_slug)
      from_filename = File.join(from_file_directory, 'index.html')
      if skip_existing_file && File.exist?(from_filename)
        $stdout.puts "\tSkipping #{from_slug}; Redirect already exists"
      else
        if to_slug.include?("#")
          to = File.join(SITE_CONFIG.fetch("baseURL"), to_slug)
        else
          to = File.join(SITE_CONFIG.fetch("baseURL"), to_slug, '/')
        end
        content = REDIRECT_TEMPLATE % { to: to }
        FileUtils.mkdir_p(from_file_directory)
        File.open(from_filename, 'w+') do |file|
          file.puts(content)
        end
      end
    end

  end
end
