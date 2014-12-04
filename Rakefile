require 'rake/testtask'
require 'rubocop/rake_task'
require 'yard'

Rake::TestTask.new do |t|
  t.libs = ["lib", "test"]
  t.warning = true
  t.verbose = true
  t.test_files = FileList['test/test_*.rb']
end

YARD::Rake::YardocTask.new

RuboCop::RakeTask.new do |task|
  task.patterns = ['lib/**/*.rb', 'test/*.rb']
end