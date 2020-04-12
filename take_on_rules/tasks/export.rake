namespace :export do
  desc "Export to RPGGeek Format"
  task :to_rpggeek, [:path] do |task, args|
    path = args.fetch(:path, "")
    require_relative "../../take_on_rules/exporter"
    $stdout.puts TakeOnRules::Exporter.call(path: path, to: :rpggeek)
  end
  desc "Export to Reddit Format"
  task :to_reddit, [:path] do |task, args|
    path = args.fetch(:path, "")
    require_relative "../../take_on_rules/exporter"
    $stdout.puts TakeOnRules::Exporter.call(path: path, to: :reddit)
  end
end
