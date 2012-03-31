
module Fony

  require "fileutils"
  require "stringio"
  require "rexml/document"
  require "optparse"
  
  @linux = RUBY_PLATFORM.end_with? "linux"
  @windows = not(@linux)
  @home_dir = @linux ? ENV["HOME"] : ENV["USERPROFILE"]
  
  def Fony.copy_file(src, dest)
    if File.file? src
      puts "copying '#{src}' to '#{dest}'..."
      FileUtils.cp src, dest
    end
  end

  def Fony.change_ext(path, ext)
    path[0, (path.length - (File.extname path).length)] << "." << ext
  end
  
  def Fony.compile_project(project_file, config)
    config ||= "Debug"
    # scrape options
    proj = REXML::Document.new (File.read project_file)
    target = (proj.get_elements "/Project/PropertyGroup/OutputType")[0].text.downcase
    asm_name = (proj.get_elements "/Project/PropertyGroup/AssemblyName")[0].text
    group = (proj.get_elements "/Project/PropertyGroup[contains(@Condition, '#{config}')]")[0]
    debug_symbols = (group.get_elements "DebugSymbols")[0]
    debug_symbols = debug_symbols ? debug_symbols.text == "true" : false
    debug_type = (group.get_elements "DebugType")[0]
    debug_type = debug_type ? debug_type.text : "full"
    optimize = (group.get_elements "Optimize")[0]
    optimize = optimize ? optimize.text == "true" : false
    tailcalls = (group.get_elements "Tailcalls")[0]
    tailcalls = tailcalls ? tailcalls.text == "true" : false
    output_dir = (group.get_elements "OutputPath")[0].text.gsub "$(Configuration)", config
    output_dir = File.absolute_path output_dir
    output_path = (File.join output_dir, asm_name) << "." << (target == "library" ? "dll" : "exe")
    define_constants = (group.get_elements "DefineConstants")[0]
    define_constants = define_constants ? (define_constants.text.split ";") : []
    warning_level = (group.get_elements "WarningLevel")[0]
    warning_level = warning_level ? warning_level.text.to_i : 3
    doc_file = (group.get_elements "DocumentationFile")[0]
    doc_file = doc_file ? (File.absolute_path (doc_file.text.gsub "$(Configuration)", config)) : nil
    refs = (proj.get_elements "/Project/ItemGroup/Reference").map do |ref|
      name = (ref.attribute "Include").to_s
      hint_path = (ref.get_elements "HintPath")[0]
      hint_path = hint_path ? (File.absolute_path (hint_path.text.gsub "$(Configuration)", config)) : nil
      private = (ref.get_elements "Private")[0]
      private = private ? private.text == "True" : false
      { :name => name, :hint_path => hint_path, :private => private }
    end
    refs = refs.find_all {|r| r[:name] != "mscorlib" && r[:name] != "FSharp.Core" }
    sources = (proj.get_elements "/Project/ItemGroup/Compile").map { |c| (c.attribute "Include").to_s }
    # build arguments
    arg_output = "--out:\"#{output_path}\""
    arg_target = "--target:#{target}"
    arg_debug_symbols = "--debug" << (debug_symbols ? "+" : "-")
    arg_debug_type = "--debug:#{debug_type}"
    arg_optimize = "--optimize" << (optimize ? "+" : "-")
    arg_tailcalls = "--tailcalls" << (tailcalls ? "+" : "-")
    arg_define_constants = (define_constants.map {|c| "--define:#{c}" }).join " "
    arg_warning_level = "--warn:#{warning_level}"
    arg_doc_file = doc_file ? "--doc:\"#{doc_file}\"" : ""
    arg_refs = refs.map do |ref|
      ref = ref[:hint_path] ? ref[:hint_path] : ref[:name]
      "--reference:\"#{ref}\""
    end
    arg_refs = arg_refs.join " "
    arg_sources = (sources.map {|s| File.absolute_path s }).join " "
    # build command
    cmd = @linux ? "fsharpc" : "fsc.exe"
    cmd << " --noframework"
    cmd << " #{arg_output}"
    cmd << " #{arg_target}"
    cmd << " #{arg_debug_symbols}"
    cmd << " #{arg_debug_type}"
    cmd << " #{arg_optimize}"
    cmd << " #{arg_tailcalls}"
    cmd << " #{arg_define_constants}"
    cmd << " #{arg_warning_level}"
    cmd << " #{arg_doc_file}"
    cmd << " #{arg_refs}"
    cmd << " #{arg_sources}"
    puts cmd
    puts `#{cmd}`
    # copy references
    refs = refs.find_all {|r| r[:private] }
    refs.each do |ref|
      ref = ref[:hint_path]
      copy_file ref, output_dir
      copy_file (change_ext ref, "pdb"), output_dir
      copy_file (change_ext ref, "xml"), output_dir
    end
  end
  
  def Fony.cmd_fony
    options = {}
    parser = OptionParser.new do |ops|
      ops.banner = "Usage: fony [options] <projectfile1> [<projectfile2>...]"
      ops.on("-c", "--config CONFIG", "Use the specific configuration (default: Debug)") do |config|
        options[:config] = config
      end
      ops.on("-h", "--help", "Display this screen") do
        puts ops
        exit
      end
    end
    parser.parse!
    ARGV.each do |project_file|
      compile_project project_file, options[:config]
    end
  end  

end
