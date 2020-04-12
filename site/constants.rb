require 'toml-rb'

module TakeOnRules
  module Site
    PROJECT_PATH = File.expand_path('../../../../', __FILE__)
    SITE_CONFIG = TomlRB.load_file(File.join(PROJECT_PATH, 'config.toml'))
    PUBLIC_PATH = File.join(PROJECT_PATH, 'public')
    IMAGE_METADATA_FILE_PATH = File.join(PROJECT_PATH, "data/image_metadata.yml")
    IMAGE_ASSET_BASE_PATH = File.join(PROJECT_PATH, "assets")
    AMP_FILENAME_REGEXP = /\/amp\//
    PAGINATION_PATH_REGEXP = /\A\/page\/\d/
    # The template used when generating an HTML-page redirect.
    REDIRECT_TEMPLATE = %(
    <!DOCTYPE html>
    <html>
      <head>
        <title>%{to}</title>
        <link rel="canonical" href="%{to}"/>
        <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
        <meta http-equiv="refresh" content="0; url=%{to}"/>
      </head>
      <body>
        <h1>Redirecting to %{to}</h1>
        <a href="%{to}">Click here if you are not redirected.</a>
      </body>
    </html>
    ).strip
  end
end

if $0 == __FILE__
  TakeOnRules::Site.constants.each do |name|
    const = TakeOnRules::Site.const_get(name)
    puts "#{name.inspect}\t#{const}" if const.is_a?(String)
  end
end
