# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'open3'
require 'pathname'

module SketchupGeometryDecimator
  module Extension
    extend self

    DialogState = Struct.new(
      :dialog,
      :target,
      :preview_group,
      :original_faces,
      :reduced_faces,
      :final_faces,
      :last_result,
      keyword_init: true
    )

    def activate
      create_menu
      create_toolbar
    end

    def state_for(model)
      @states ||= {}
      @states[model.object_id] ||= DialogState.new(
        original_faces: 0,
        reduced_faces: 0,
        final_faces: 0,
        last_result: nil
      )
    end

    def create_menu
      menu = UI.menu('Plugins').add_submenu('Geometry Decimator')
      menu.add_item('Open Decimator') { open_dialog }
    end

    def create_toolbar
      cmd = UI::Command.new('Geometry Decimator') { open_dialog }
      cmd.tooltip = 'Open Geometry Decimator'
      cmd.status_bar_text = 'Simplify selected mesh and preview watertight result.'
      toolbar = UI::Toolbar.new('Geometry Decimator')
      toolbar.add_item(cmd)
      toolbar.restore
    end

    def open_dialog
      model = Sketchup.active_model
      state = state_for(model)

      if state.dialog.nil?
        state.dialog = UI::HtmlDialog.new(
          dialog_title: 'Geometry Decimator',
          preferences_key: 'com.openai.sketchup.geometrydecimator',
          scrollable: true,
          resizable: true,
          width: 900,
          height: 700,
          style: UI::HtmlDialog::STYLE_DIALOG
        )

        html_path = File.join(__dir__, 'ui', 'index.html')
        state.dialog.set_file(html_path)
        bind_dialog_callbacks(state)
      end

      state.dialog.show
      dispatch_log(state, 'Plugin opened. Select a Group or Component Instance and click Analyze.')
    end

    def bind_dialog_callbacks(state)
      state.dialog.add_action_callback('analyzeSelection') do |_ctx|
        analyze_selection(state)
      end

      state.dialog.add_action_callback('runDecimation') do |_ctx, level|
        run_decimation(state, level.to_f)
      end

      state.dialog.add_action_callback('togglePreview') do |_ctx, enabled|
        toggle_preview(state, enabled)
      end

      state.dialog.add_action_callback('applyResult') do |_ctx|
        apply_result(state)
      end

      state.dialog.add_action_callback('resetResult') do |_ctx|
        reset_preview(state)
      end
    end

    def analyze_selection(state)
      model = Sketchup.active_model
      selection = model.selection
      target = selection.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      unless target
        dispatch_log(state, 'No valid target selected. Select one Group or Component Instance.', :error)
        return
      end

      mesh = extract_mesh(target)
      state.target = target
      state.original_faces = mesh[:faces].size
      state.reduced_faces = 0
      state.final_faces = 0
      state.last_result = nil
      clear_preview(state)
      push_stats(state)
      dispatch_log(state, "Analyzed target '#{target.entityID}' with #{state.original_faces} faces.")
    rescue StandardError => e
      dispatch_log(state, "Analyze failed: #{e.message}", :error)
    end

    def run_decimation(state, level)
      unless state.target
        dispatch_log(state, 'Analyze a target before running decimation.', :error)
        return
      end

      normalized_level = [[level, 0.0].max, 1.0].min
      mesh = extract_mesh(state.target)
      result = call_python_decimator(mesh, normalized_level)
      preview = build_preview_group(state, result)

      state.preview_group = preview
      state.reduced_faces = result['reduced_faces'].to_i
      state.final_faces = result['final_faces'].to_i
      state.last_result = result

      toggle_preview(state, true)
      push_stats(state)
      dispatch_log(state, "Decimation complete at #{(normalized_level * 100).round}% strength.")
    rescue StandardError => e
      dispatch_log(state, "Decimation failed: #{e.message}", :error)
    end

    def toggle_preview(state, enabled)
      return unless state.target

      show_preview = enabled == true || enabled.to_s == 'true'
      if state.preview_group&.valid?
        state.preview_group.hidden = !show_preview
        state.target.hidden = show_preview
        dispatch_log(state, show_preview ? 'Preview enabled.' : 'Preview disabled.')
      end
    end

    def apply_result(state)
      unless state.preview_group&.valid? && state.target&.valid?
        dispatch_log(state, 'Nothing to apply. Run decimation first.', :error)
        return
      end

      model = Sketchup.active_model
      model.start_operation('Apply Decimated Mesh', true)
      state.target.erase!
      state.preview_group.hidden = false
      state.target = state.preview_group
      state.preview_group = nil
      model.commit_operation

      dispatch_log(state, 'Decimated result applied to model.')
      push_stats(state)
    rescue StandardError => e
      model.abort_operation
      dispatch_log(state, "Apply failed: #{e.message}", :error)
    end

    def reset_preview(state)
      clear_preview(state)
      state.reduced_faces = 0
      state.final_faces = 0
      state.last_result = nil
      push_stats(state)
      dispatch_log(state, 'Preview cleared and counters reset.')
    end

    def clear_preview(state)
      if state.preview_group&.valid?
        state.preview_group.erase!
      end
      state.preview_group = nil
      state.target.hidden = false if state.target&.valid?
    end

    def push_stats(state)
      payload = {
        original: state.original_faces,
        reduced: state.reduced_faces,
        final: state.final_faces
      }
      state.dialog.execute_script("window.geometryDecimator.updateStats(#{payload.to_json});")
    end

    def dispatch_log(state, message, level = :info)
      escaped = { level: level, message: message }.to_json
      state.dialog&.execute_script("window.geometryDecimator.log(#{escaped});")
    end

    def extract_mesh(target)
      mesh = target.definition.entities.grep(Sketchup::Face)
      points = []
      point_lookup = {}
      faces = []

      mesh.each do |face|
        polygon = face.outer_loop.vertices.map { |v| v.position.transform(target.transformation) }
        next if polygon.length < 3

        indices = polygon.map do |pt|
          key = [pt.x.to_f.round(6), pt.y.to_f.round(6), pt.z.to_f.round(6)]
          point_lookup[key] ||= begin
            points << key
            points.length - 1
          end
        end
        faces << indices
      end

      { points: points, faces: faces }
    end

    def call_python_decimator(mesh, level)
      script_path = File.join(__dir__, 'python', 'decimator.py')
      Tempfile.create(['mesh', '.json']) do |input|
        Tempfile.create(['mesh_result', '.json']) do |output|
          input.write({ level: level, mesh: mesh }.to_json)
          input.flush

          cmd = ['python3', script_path, input.path, output.path]
          stdout, stderr, status = Open3.capture3(*cmd)
          raise "Python decimator failed: #{stderr.strip}\n#{stdout.strip}" unless status.success?

          JSON.parse(File.read(output.path))
        end
      end
    end

    def build_preview_group(state, result)
      model = Sketchup.active_model
      model.start_operation('Build Decimation Preview', true)
      group = model.active_entities.add_group
      entities = group.entities
      points = result.fetch('points').map { |coords| Geom::Point3d.new(coords[0], coords[1], coords[2]) }

      result.fetch('faces').each do |indices|
        next if indices.length < 3

        face_points = indices.map { |idx| points[idx] }
        face = entities.add_face(face_points)
        face.reverse! if face&.normal&.z.to_f < 0
      rescue StandardError
        next
      end

      group.material = state.target.material if state.target&.material
      group.hidden = false
      model.commit_operation
      group
    rescue StandardError => e
      model.abort_operation
      raise e
    end
  end
end

SketchupGeometryDecimator::Extension.activate
