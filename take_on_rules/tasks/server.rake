desc 'Serve the existing ./public on port 4000'
task :serve do
  # Responsible for serving up takeonrules.github.io locally
  require 'webrick'
  root = File.join(PUBLIC_PATH)
  server = WEBrick::HTTPServer.new :Port => 4000, :DocumentRoot => root
  trap 'INT' do server.shutdown end
  server.start
end
