# Not quite a rake take, but this ensures that all constants referenced
# in the tasks/*.rake are loaded
require_relative '../site.rb'
include TakeOnRules::Site
