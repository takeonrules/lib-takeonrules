task metadata: ['metadata:guard', 'metadata:updates', 'metadata:tables', 'metadata:commit']
namespace :metadata do
  FILES_TO_COMMIT = [
    TakeOnRules::Site.each_project_filename(matching: "data/redirects.yml").first,
    TakeOnRules::Site.each_project_filename(matching: 'data/list_of_all_updates.yml').first,
    TakeOnRules::Site.each_project_filename(matching: "data/list_of_all_tables.yml").first
  ]
  desc 'Verify metadata files have yet to change'
  task :guard do
    if TakeOnRules::Site.changed?(files: FILES_TO_COMMIT)
      $stderr.puts "Ecnountere changed metadata files, please review"
      exit!(8)
    end
  end
  desc 'Commit metadata changes'
  task :commit do
    TakeOnRules::Site.commit!(files: FILES_TO_COMMIT, message: "Updated via 'metadata:commit' rake task")
  end
  desc 'Update "updates" metadata'
  task :updates do
    require 'psych'
    $stdout.puts "Extracting Updates Metadata…"
    UpdatesMetadata = Struct.new(:date, :page_title, :permalink, :inner) do
      include Comparable
      def <=>(other)
        [date, permalink, inner] <=> [other.date, other.permalink, other.inner]
      end
      def to_hash
        { "date" => date, "page_title" => page_title, "permalink" => permalink, "inner" => inner}
      end
    end
    UPDATE_SHORT_CODE = %r{\{\{(?<open_token>[<%]) +(?<shortcode>update )(?<params>[^(>|%)]*)(?<close_token>\>|%) *\}\}(?<inner>[^\{]*)}.freeze
    all_updates = []
    files_with_update_declarations = `ag "{{[%<] update" #{PROJECT_PATH} -l --ignore-dir public --ignore-dir themes`.split("\n")
    files_with_update_declarations.each do |filename|
      file = FileWithFrontmatterAndContent.load(filename: filename)
      file.body.split("\n").each do |line|
        match = UPDATE_SHORT_CODE.match(line)
        if match
          date = TakeOnRules::Site.extract_shortcode_parameter("date", from: match[:params])
          all_updates << UpdatesMetadata.new(date, file.title, file.permalink, match[:inner])
        end
      end
    end
    list_of_all_updates_filename = TakeOnRules::Site.each_project_filename(matching: 'data/list_of_all_updates.yml').first
    File.open(list_of_all_updates_filename, "w+") do |f|
      f.puts Psych.dump(all_updates.sort.map(&:to_hash))
    end
    $stdout.puts "Done Extracting Updates Metadata…"
  end
  desc "Update tables to include table numbering"
  task :tables do
    $stdout.puts "Numbering Tables and Creating Redirects…"
    Rake.application.invoke_task("audit:table_counter[exit_on_failure]")

    LEADING_SLASH = %r{^\/}.freeze
    TABLE_DECLARATION_REGEXP = %r{\{\{(?<token>[<%]) +(?<shortcode>table[^ ]*)(?<parameters>[^\}]+)}.freeze
    TABLE_NUMBER_EXISTS_REGEXP = %r{table_number=["'](?<table_number>\d+)["']}.freeze
    files_with_tables = []
    redirect_filename = TakeOnRules::Site.each_project_filename(matching: "data/redirects.yml").first
    redirects = Psych.load(File.read(redirect_filename))
    tables_filename = TakeOnRules::Site.each_project_filename(matching: "data/list_of_all_tables.yml").first
    tables = []

    ag_for_all_short_code_table_declarations = %(ag "{{[%<] table" #{PROJECT_PATH} -l --ignore-dir public --ignore-dir themes)

    filenames_with_tables = `#{ag_for_all_short_code_table_declarations}`.split("\n")
    table_numbers         = `#{ag_for_all_short_code_table_declarations} | xargs ag "table_number=\\"\\d+\\"" -o --nofilename | ag "\\d+" -o`.split("\n").map(&:to_i).sort
    last_table_number = table_numbers.last

    filenames_with_tables.each do |filename|
      files_with_tables << FileWithFrontmatterAndContent.load(filename: filename)
    end

    files_with_tables.sort.each do |file|
      lines = []
      updated = false
      file.body.split("\n").each do |line|
        if match = TABLE_DECLARATION_REGEXP.match(line)
          table_number_match = TABLE_NUMBER_EXISTS_REGEXP.match(line)
          if table_number_match
            table_number = table_number_match[:table_number]
          else
            last_table_number += 1
            updated = true
            table_number = last_table_number
            line = line.sub(TABLE_DECLARATION_REGEXP, %({{#{match[:token]} #{match[:shortcode]} table_number="#{table_number}"#{match[:parameters]}))
            $stdout.puts "\tAdding Table #{table_number} at #{file.permalink}"
          end
          from = "tables/#{table_number}"
          to = File.join(file.permalink.sub(LEADING_SLASH, ''), "#table-#{table_number}")
          redirects << { "from" => from, "to" => to, "skip_existing_file" => true }

          tables << {
            "publication_date" => file.publication_date.to_s,
            "page_title" => file.title,
            "path" => file.permalink,
            "table_number" => table_number.to_i,
            "caption" => TakeOnRules::Site.extract_shortcode_parameter("caption", from: match[0])
          }
        end
        lines << line
      end
      next unless updated
      file.body = lines.join("\n")
      file.write!(update: true)
    end

    File.open(tables_filename, "w+") do |f|
      f.write Psych.dump(tables)
    end

    File.open(redirect_filename, "w+") do |f|
      f.write Psych.dump(redirects.uniq)
    end
    $stdout.puts "Finished Numbering Tables and Creating Redirects"
  end
end
