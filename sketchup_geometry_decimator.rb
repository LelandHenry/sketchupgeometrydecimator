# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module SketchupGeometryDecimator
  EXTENSION_ID = 'sketchup_geometry_decimator'
  EXTENSION_NAME = 'SketchUp Geometry Decimator'
  EXTENSION_VERSION = '0.1.1'

  unless file_loaded?(__FILE__)
    extension_path = File.join(__dir__, 'src', 'extension')
    extension = SketchupExtension.new(EXTENSION_NAME, extension_path)
    extension.description = 'Simplifies dense meshes, previews before/after, and applies a watertight mesh cleanup pass.'
    extension.version = EXTENSION_VERSION
    extension.copyright = 'OpenAI'
    extension.creator = 'OpenAI'
    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
