# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = 'zipr'
  spec.version       = '0.3.1'
  spec.authors       = ['Alex Munoz']
  spec.email         = ['amunoz951@gmail.com']
  spec.license       = 'Apache-2.0'
  spec.summary       = 'Ruby library for easily extracting and creating 7zip and zip archives idempotently.'
  spec.homepage      = 'https://github.com/amunoz951/zipr'

  spec.required_ruby_version = '>= 2.3'

  spec.files         = Dir['LICENSE', 'lib/**/*']
  spec.require_paths = ['lib']

  spec.add_dependency 'easy_io', '~> 0'
  spec.add_dependency 'json', '~> 2'
  spec.add_dependency 'rubyzip', '~> 2'
  spec.add_dependency 'seven_zip_ruby', '~> 1.3'
  spec.add_dependency 'os', '~> 1'

  spec.add_development_dependency 'rspec', '~> 3'
end
