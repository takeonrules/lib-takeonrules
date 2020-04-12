namespace :social do
  desc "Post given [URL] to mastodon instances"
  task :to_mastodon, [:url] do |task, args|
    url = args.fetch(:url)
    require_relative "../../take_on_rules/socializer"
    $stdout.puts TakeOnRules::Socializer.call(url: url, to: :mastodon)
  end
  desc "Post given [URL] to twitter instances"
  task :to_twitter, [:url] do |task, args|
    url = args.fetch(:url)
    require_relative "../../take_on_rules/socializer"
    $stdout.puts TakeOnRules::Socializer.call(url: url, to: :twitter)
  end
end

desc "Post given [URL] to mastodon and twitter instances"
task :social, [:url] do | task, args|
  Rake::Task["social:to_mastodon"].invoke(*args)
  Rake::Task["social:to_twitter"].invoke(*args)
end
