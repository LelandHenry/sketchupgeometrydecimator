# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module SketchupGeometryDecimator
  EXTENSION_ID = 'sketchup_geometry_decimator'
  EXTENSION_NAME = 'SketchUp Geometry Decimator'
  EXTENSION_VERSION = '0.1.0'

  unless file_loaded?(__FILE__)
    extension = SketchupExtension.new(EXTENSION_NAME, 'src/extension')
    extension.description = 'Simplifies dense meshes, previews before/after, and applies a watertight mesh cleanup pass.'
    extension.version = EXTENSION_VERSION
    extension.copyright = 'OpenAI'
    extension.creator = 'OpenAI'
    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
