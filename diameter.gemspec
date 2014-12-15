Gem::Specification.new do |s|
  s.name        = 'diameter'
  s.version     = '0.1.0.beta'
  s.licenses    = ['MIT']
  s.summary     = "Pure-Ruby Diameter stack"
  s.authors     = ["Rob Day"]
  s.email       = 'ruby-diameter@rkd.me.uk'
  s.files       = Dir["lib/diameter/*.rb", "lib/diameter.rb"]
  s.homepage    = 'http://rkday.github.io/ruby-diameter/api-docs/master/'

  s.add_runtime_dependency 'concurrent-ruby', '~> 0.7'

  s.add_development_dependency 'rubocop', '~> 0.28'
  s.add_development_dependency 'yard', '0.8'
  s.add_development_dependency 'simplecov', '0.9' 
  s.add_development_dependency 'mocha', '1.1'
  s.add_development_dependency 'minitest-spec-context', '0.0.3'
end