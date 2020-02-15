module Zipr
  module_function

  def config
    @config ||= EasyJSON.config(defaults: defaults)
  end

  def defaults
    {
      'paths' => {
        'cache' => Dir.tmpdir,
      },
    }
  end
end
