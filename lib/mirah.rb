require 'fileutils'
require 'rbconfig'
require 'mirah/transform'
require 'mirah/ast'
require 'mirah/threads'
require 'mirah/typer'
require 'mirah/compiler'
require 'mirah/env'
begin
  require 'bitescript'
rescue LoadError
  $: << File.dirname(__FILE__) + '/../../bitescript/lib'
  require 'bitescript'
end
require 'mirah/jvm/compiler'
require 'mirah/jvm/typer'
Dir[File.dirname(__FILE__) + "/mirah/plugin/*"].each {|file| require "#{file}" if file =~ /\.rb$/}
require 'jruby'
require 'jruby/synchronized'

class Duby::AST::Node
  include JRuby::Synchronized
end

module Duby
  def self.run(*args)
    DubyImpl.new.run(*args)
  end

  def self.compile(*args)
    DubyImpl.new.compile(*args)
  end

  def self.parse(*args)
    DubyImpl.new.parse(*args)
  end

  def self.plugins
    @plugins ||= []
  end

  def self.reset
    plugins.each {|x| x.reset if x.respond_to?(:reset)}
  end

  def self.print_error(message, position)
    puts "#{position.file}:#{position.start_line}: #{message}"
    file_offset = 0
    startline = position.start_line - 1
    endline = position.end_line - 1
    start_col = position.start_col - 1
    end_col = position.end_col - 1
    # don't try to search dash_e
    # TODO: show dash_e source the same way
    if File.exist? position.file
      File.open(position.file).each_with_index do |line, lineno|
        if lineno >= startline && lineno <= endline
          puts line.chomp
          if lineno == startline
            print ' ' * start_col
          else
            start_col = 0
          end
          if lineno < endline
            puts '^' * (line.size - start_col)
          else
            puts '^' * [end_col - start_col, 1].max
          end
        end
      end
    end
  end

  class CompilationState
    attr_accessor :verbose, :destination, :builtins_initialized
    attr_reader :executor, :mutex, :main_thread

    def initialize
      @executor = Duby::Threads::Executor.new
      @mutex = Mutex.new
      @main_thread = Thread.current
    end

    def log(message)
      # TODO allow filtering which logs to show.
      if verbose
        @mutex.synchronize {
          puts message
        }
      end
    end
  end
end

# This is a custom classloader impl to allow loading classes with
# interdependencies by having findClass retrieve classes as needed from the
# collection of all classes generated by the target script.
class DubyClassLoader < java::security::SecureClassLoader
  def initialize(parent, class_map)
    super(parent)
    @class_map = class_map
  end

  def findClass(name)
    if @class_map[name]
      bytes = @class_map[name].to_java_bytes
      defineClass(name, bytes, 0, bytes.length)
    else
      raise java.lang.ClassNotFoundException.new(name)
    end
  end

  def loadClass(name, resolve)
    cls = findLoadedClass(name)
    if cls == nil
      if @class_map[name]
        cls = findClass(name)
      else
        cls = super(name, false)
      end
    end

    resolveClass(cls) if resolve

    cls
  end
end

class DubyImpl
  def initialize
    Duby::AST.type_factory = Duby::JVM::Types::TypeFactory.new
  end

  def run(*args)
    main = nil
    class_map = {}

    # generate all bytes for all classes
    generate(args) do |outfile, builder|
      bytes = builder.generate
      name = builder.class_name.gsub(/\//, '.')
      class_map[name] = bytes
    end

    # load all classes
    dcl = DubyClassLoader.new(java.lang.ClassLoader.system_class_loader, class_map)
    class_map.each do |name,|
      cls = dcl.load_class(name)
      # TODO: using first main; find correct one
      main ||= cls.get_method("main", java::lang::String[].java_class) #rescue nil
    end

    # run the main method we found
    if main
      begin
        main.invoke(nil, [args.to_java(:string)].to_java)
      rescue java.lang.Exception => e
        e = e.cause if e.cause
        raise e
      end
    else
      puts "No main found"
    end
  end

  def compile(*args)
    generate(args) do |filename, builder|
      filename = "#{@state.destination}#{filename}"
      FileUtils.mkdir_p(File.dirname(filename))
      bytes = builder.generate
      File.open(filename, 'wb') {|f| f.write(bytes)}
    end
  end

  def generate(args, &block)
    all_nodes = parse(*args)

    # enter all ASTs into inference engine
    infer_asts(all_nodes)

    # compile each AST in turn
    all_nodes.each do |ast|
      compile_ast(ast, &block)
    end
  end

  def parse(*args)
    process_flags!(args)

    files = expand_files(args)
    if files.empty?
      print_help
      exit(1)
    end

    # collect all ASTs from all files
    all_nodes = @state.executor.each(files) do |pair|
      filename, src = pair
      begin
        ast = Duby::AST.parse_ruby(src, filename)
      # rescue org.jrubyparser.lexer.SyntaxException => ex
      #   Duby.print_error(ex.message, ex.position)
      #   raise ex if @state.verbose
      end
      transformer = Duby::Transform::Transformer.new(@state)
      @state.mutex.synchronize {
        @state.builtins_initialized ||= begin
          Java::MirahImpl::Builtin.initialize_builtins(transformer)
          true
        end
      }
      transformer.filename = filename
      ast = transformer.transform(ast, nil)
      @state.mutex.synchronize {
        transformer.errors.each do |ex|
          Duby.print_error(ex.message, ex.position)
          raise ex.cause || ex if @state.verbose
        end
      }
      @error ||= transformer.errors.size > 0
      ast
    end

    all_nodes
  end

  def infer_asts(asts)
    typer = Duby::Typer::JVM.new(@transformer)
    asts.each {|ast| typer.infer(ast) }
    begin
      typer.resolve(false)
    ensure
      puts asts.inspect if @state.verbose

      failed = !typer.errors.empty?
      if failed
        puts "Inference Error:"
        typer.errors.each do |ex|
          if ex.node
            Duby.print_error(ex.message, ex.node.position)
          else
            puts ex.message
          end
          puts ex.backtrace if @state.verbose
        end
        exit 1
      end
    end
  end

  def compile_ast(ast, &block)
    begin
      compiler = @compiler_class.new
      ast.compile(compiler, false)
      compiler.generate(&block)
    rescue Exception => ex
      if ex.respond_to? :node
        @state.mutex.synchronize {
          Duby.print_error(ex.message, ex.node.position)
          @state.log(ex.backtrace)
        }
        @error = true
      else
        raise ex
      end
    end

  end

  def process_flags!(args)
    @state ||= Duby::CompilationState.new
    while args.length > 0 && args[0] =~ /^-/
      case args[0]
      when '--verbose', '-V'
        Duby::Typer.verbose = true
        Duby::AST.verbose = true
        Duby::Compiler::JVM.verbose = true
        @state.verbose = true
        args.shift
      when '--java', '-j'
        require 'mirah/jvm/source_compiler'
        @compiler_class = Duby::Compiler::JavaSource
        args.shift
      when '--dest', '-d'
        args.shift
        @state.destination = File.join(File.expand_path(args.shift), '')
      when '--cd'
        args.shift
        Dir.chdir(args.shift)
      when '--plugin', '-p'
        args.shift
        plugin = args.shift
        require "mirah/plugin/#{plugin}"
      when '-I'
        args.shift
        $: << args.shift
      when '--classpath', '-c'
        args.shift
        Duby::Env.decode_paths(args.shift, $CLASSPATH)
      when '--explicit-packages'
        args.shift
        Duby::AST::Script.explicit_packages = true
      when '--help', '-h'
        print_help
        exit(0)
      when '-e'
        break
      else
        puts "unrecognized flag: " + args[0]
        print_help
        exit(1)
      end
    end
    @state.destination ||= File.join(File.expand_path('.'), '')
    @compiler_class ||= Duby::Compiler::JVM
  end

  def print_help
    $stdout.puts "#{$0} [flags] <files or \"-e SCRIPT\">
  -V, --verbose\t\tVerbose logging
  -j, --java\t\tOutput .java source (jrubyc only)
  -d, --dir DIR\t\tUse DIR as the base dir for compilation, packages
  -p, --plugin PLUGIN\tLoad and use plugin during compilation
  -c, --classpath PATH\tAdd PATH to the Java classpath for compilation
  --explicit-packages\tDisable guessing the package from the filename
  -h, --help\t\tPrint this help message
  -e\t\t\tCompile or run the script following -e (naming it \"DashE\")"
  end

  def expand_files(files)
    expanded = []
    dash_e = false
    files.each do |filename|
      if dash_e
        expanded << ['DashE', filename]
        dash_e = false
      elsif filename == '-e'
        dash_e = true
        next
      elsif File.directory?(filename)
        Dir[File.join(filename, '*')].each do |child|
          if File.directory?(child)
            files << child
          elsif child =~ /\.(duby|mirah)$/
            expanded << [child, File.read(child)]
          end
        end
      else
        expanded << [filename, File.read(filename)]
      end
    end
    expanded
  end
end

module JRuby::Synchronized
  def respond_to?(*args)
    m = Object.instance_method(:respond_to?)
    begin
      m.bind(self).call(*args)
    rescue java.lang.NullPointerException
      nil
    end
  end
end

class Array
  alias join_unsynchronized join
  def join(*args)
    map{|x| x.to_s}.join_unsynchronized(*args)
  end

  alias to_s_unsynchronized to_s

  def to_s
    map{|x| x.to_s}.to_s_unsynchronized
  end
end

Mirah = Duby

if __FILE__ == $0
  Duby.run(ARGV[0], *ARGV[1..-1])
end
