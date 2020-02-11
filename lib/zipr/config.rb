module Zipr
  module_function

  def config
    @config ||= EasyJson.config(defaults: defaults)
  end

  def defaults
    {
      'common' => {
        'paths' => {
          'cache' => nil,
        },
      },
    }
  end
end
