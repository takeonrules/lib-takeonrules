# Adding bundler/setup to ensure that I can use rake task completion
require "bundler/setup"
require_relative "./take_on_rules/site"
TakeOnRules::Site.load_rake_tasks!

task default: :audit
