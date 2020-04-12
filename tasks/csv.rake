namespace :csv do
  SPREADSHEET_KEY = "1Sf9k9o_nnX6ZCZFs5LkuWW-jrFXFxRzXQLn0a30HppA"
  SPREADSHEET_MAP = {
    "Classes" => { basename: "classes", name: "Classes and Subclasses" },
    "Backgrounds" => { basename: "backgrounds", name: "Backgrounds" },
    "Races" => { basename: "races-and-cultures", name: "Races and Cultures" },
    "Guess Who's Coming to Graywall" => { basename: "guess-whos-coming-to-graywall", name: "Guess Who's Coming to Graywall" },
    "Origin" => { basename: "eberron-origins", name: "Random Eberron Origin" }
  }

  desc "Open Google Sheet for editing"
  task :open do
    url = "https://docs.google.com/spreadsheets/d/#{SPREADSHEET_KEY}/edit#gid=1089422221"
    `open -a Firefox.app #{url}`
  end
  desc "Download spreadsheet information to local CSVs"
  task :download do
    require 'google_drive'
    credentials_file_name = File.join(PROJECT_PATH, "credentials/takeonrules-com-865c251f3f87.json")
    session = GoogleDrive::Session.from_service_account_key(credentials_file_name)
    spreadsheet = session.spreadsheet_by_key(SPREADSHEET_KEY)
    spreadsheet.worksheets.each do |worksheet|
      target_data = SPREADSHEET_MAP.fetch(worksheet.title)
      filename = File.join(PROJECT_PATH, "tmp/#{target_data.fetch(:basename)}.csv")
      worksheet.export_as_file(filename)
    end
  end
  desc "Given the Eberron data CSVs, convert them to YAML for dynamic rendering (assumes header row, label row, data rows)"
  task convert_to_yaml: ["csv:download"] do
    require 'csv'
    require 'psych'
    URL_COLUMN_PATTER = /(.*)_url\Z/

    SPREADSHEET_MAP.values.each do |file_data|
      basename = file_data.fetch(:basename)
      name = file_data.fetch(:name)
      rows = []
      columns = []
      data = {
        "name" => name,
        "columns" => columns,
        "rows" => rows
      }

      url_columns = []
      CSV.foreach(File.join(PROJECT_PATH, "tmp/#{basename}.csv"), headers: true) do |csv|
        if columns.empty?
          csv.headers.each do |header|
            is_match = URL_COLUMN_PATTER.match(header)
            if is_match
              url_columns << { "column_name" => header, "applies_to_column_name" => is_match[1] }
            else
              columns << { "key" => header , "label" => csv.fetch(header) }
            end
          end
          # Verify that URLs have corresponding columns
          url_columns.each do |url_column|
            next if csv.key?(url_column.fetch("applies_to_column_name"))
            $stderr.puts "Expected #{basename}.csv to have column_name: '#{url_column.fetch("applies_to_column_name")}'"
            exit!(5)
          end
          next
        end
        row = {}

        # Set row values from the CSV
        columns.each do |column|
          key = column.fetch("key")
          row[key] = csv[key]
        end

        url_columns.each do |url_column|
          column_name = url_column.fetch("column_name")
          applies_to_column_name = url_column.fetch("applies_to_column_name")
          if csv[url_column.fetch("column_name")]
            row[applies_to_column_name] = "[#{csv[applies_to_column_name]}](#{csv[column_name]})"
          end
        end
        rows << row
      end

      File.open(File.join(PROJECT_PATH, "data/eberron/#{basename}.yml"), 'w+') do |f|
        f.puts Psych.dump(data)
      end
    end
  end
end
