require_relative "../blogroll"

namespace :blogroll do
  namespace :opml do
    desc "Export OPML from Newsboat"
    task :export_from_newsboat do
      require 'open3'
      urls_filename = File.join(TakeOnRules::Site::PROJECT_PATH, 'rss/urls.txt')
      stdout, _stderr, _status = Open3.capture3("newsboat -e -C ~/.newsboatrc -u #{urls_filename}")
      File.open(File.join(TakeOnRules::Site::PROJECT_PATH, "rss/full-blogroll.opml"), "w+") do |file|
        file.puts stdout
      end
    end

    desc "Crawls current opml to find other RSS candidates"
    task :crawl_blogroll do
      Blogroll::Crawler.new(
        opml_filename: File.join(TakeOnRules::Site::PROJECT_PATH, "rss/full-blogroll.opml"),
        found_url_filename: File.join(TakeOnRules::Site::PROJECT_PATH, "rss/candidate_urls.tsv")
      ).crawl
    end

    desc "Merge current URLs and crawled_urls"
    task :merge do
      Blogroll::Merger.new(
        candidate_url_filename: File.join(TakeOnRules::Site::PROJECT_PATH, "rss/candidate_urls.tsv"),
        current_urls_filename: File.join(TakeOnRules::Site::PROJECT_PATH, "rss/urls.txt"),
        merged_filename: File.join(TakeOnRules::Site::PROJECT_PATH, "rss/urls-merged.txt"),
        skip_filename: File.join(TakeOnRules::Site::PROJECT_PATH, "rss/skip-these-urls.txt")
      )
    end
  end
end

task(
  "blogroll:opml" => [
    "blogroll:opml:export_from_newsboat",
    "blogroll:opml:crawl_blogroll",
    # "blogroll:opml:merge"
  ]
)
