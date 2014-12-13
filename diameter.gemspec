Gem::Specification.new do |s|
  s.name        = 'diameter'
  s.version     = '0.1.0.pre1'
  s.licenses    = ['MIT']
  s.summary     = "Pure-Ruby Diameter stack"
  s.authors     = ["Rob Day"]
  s.email       = 'ruby-diameter@rkd.me.uk'
  s.files       = Dir["lib/diameter/*.rb"]
  s.homepage    = 'http://rkday.github.io/ruby-diameter/api-docs/master/'

  s.add_runtime_dependency 'concurrent-ruby'

  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'minitest-spec-context'
end