#
# Author:: Alex Munoz (<amunoz951@gmail.com>)
# Copyright:: Copyright (c) 2020 Alex Munoz
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'zip' # rubyzip gem
require 'digest'
require 'easy_io'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'seven_zip_ruby'
require 'os'

require_relative 'zipr/config'
require_relative 'zipr/archive'
require_relative 'zipr/helper'
require_relative 'zipr/sfx'
