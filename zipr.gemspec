# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = 'zipr'
  spec.version       = '0.1.0'
  spec.authors       = ['Alex Munoz']
  spec.email         = ['amunoz951@gmail.com']
  spec.license       = 'Apache-2.0'
  spec.summary       = 'Ruby library for easily extracting and creating 7zip and zip archives idempotently.'
  spec.homepage      = 'https://github.com/amunoz951/zipr'

  spec.required_ruby_version = '>= 2.3'

  spec.files         = Dir['LICENSE', 'lib/**/*']
  spec.require_paths = ['lib']

  spec.add_dependency 'zip'
  spec.add_dependency 'digest'
  spec.add_dependency 'easy_io'
  spec.add_dependency 'json'
  spec.add_dependency 'tmpdir'
  spec.add_dependency 'fileutils'
  spec.add_dependency 'seven_zip_ruby'
  spec.add_dependency 'os'
end
