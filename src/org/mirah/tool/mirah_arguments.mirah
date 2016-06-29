# Copyright (c) 2014 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package org.mirah.tool

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.net.URLClassLoader
import java.util.HashSet
import java.util.List
import org.mirah.util.Logger
import java.util.logging.LogManager
import java.util.logging.Level
import java.util.regex.Pattern
import javax.tools.DiagnosticListener
import mirah.lang.ast.CodeSource
import mirah.lang.ast.StringCodeSource
import org.mirah.MirahLogFormatter
import org.mirah.jvm.compiler.JvmVersion
import org.mirah.jvm.mirrors.debug.ConsoleDebugger
import org.mirah.jvm.mirrors.debug.DebuggerInterface
import org.mirah.util.SimpleDiagnostics
import org.mirah.util.OptionParser
import java.util.Arrays
import java.util.Comparator

class MirahArguments

  attr_accessor logger_color: boolean,
                code_sources: List,
                jvm_version: JvmVersion,
                destination: String,
                diagnostics: SimpleDiagnostics,
                vloggers: String,
                verbose: boolean,
                silent: boolean,
                max_errors: int,
                use_type_debugger: boolean,
                exit_status: int,
                encoding: String,
                plugins: String,
                debugger: DebuggerInterface,
                skip_compile:boolean

  def initialize(env=System.getenv)
    @logger_color = true
    @use_type_debugger = false
    @code_sources = []
    @destination = "."

    @jvm_version = JvmVersion.new
    @classpath = nil
    @diagnostics = SimpleDiagnostics.new true
    @env = env
    @encoding = EncodedCodeSource.DEFAULT_CHARSET
    @skip_compile = false
  end

  def classpath= classpath: String
    @classpath = parseClassPath(classpath)
  end

  def bootclasspath= classpath: String
    @bootclasspath = parseClassPath(classpath)
  end
  def macroclasspath= classpath: String
    @macroclasspath = parseClassPath(classpath)
  end

  def real_classpath
    # if flag set, use flag
    # else look at env
    # else use destination directory
    return @classpath if @classpath

    env_classpath = @env["CLASSPATH"]:String
    if env_classpath
      @classpath = parseClassPath env_classpath
    elsif destination
      @classpath = parseClassPath destination
    end

    @classpath
  end

  def real_bootclasspath
    @bootclasspath
  end

  def real_macroclasspath
    @macroclasspath
  end

  def exit?
    @should_exit
  end

  def isExit
    @should_exit
  end

  def prep_for_exit status: int
    @should_exit = true
    @exit_status = status
  end

  def applyArgs(args:String[]):void
    compiler_args = self

    parser = OptionParser.new("mirahc [flags] <files or -e SCRIPT>")
    parser.addFlag(["h", "help"], "Print this help message.") do
      parser.printUsage
      compiler_args.prep_for_exit 0
    end

    parser.addFlag(
        ["e"], "CODE",
        "Compile an inline script.\n\t(The class will be named DashE)") do |c|
      compiler_args.code_sources.add(StringCodeSource.new('DashE', c))
    end

    parser.addFlag(['v', 'version'], 'Print the version.') do
      puts "Mirah v#{Mirahc.VERSION}"
      compiler_args.prep_for_exit 0
    end
    
    parser.addFlag(['V', 'verbose'], 'Verbose logging.') do
      compiler_args.verbose = true
    end

    parser.addFlag(
        ['vmodule'], 'logger.name=LEVEL[,...]',
        "Customized verbose logging. `logger.name` can be a class or package\n"+
        "\t(e.g. org.mirah.jvm or org.mirah.tool.Mirahc)\n"+
        "\t`LEVEL` should be one of \n"+
        "\t(SEVERE, WARNING, INFO, CONFIG, FINE, FINER FINEST)") do |spec|
      compiler_args.vloggers = spec
    end

    parser.addFlag(['silent'], 'disable all logging. default for run commands.') do
      compiler_args.silent = true
    end

    parser.addFlag(
        ['classpath', 'cp'], 'CLASSPATH',
        "A #{File.pathSeparator} separated list of directories, JAR \n"+
        "\tarchives, and ZIP archives to search for class files.") do |classpath|
      compiler_args.classpath = classpath
    end

    parser.addFlag(
        ['c'], 'CLASSPATH',
        "Deprecated: same as cp/classpath") do |classpath|
      System.err.println "WARN: option -c is deprecated."
      compiler_args.classpath = classpath
    end

    parser.addFlag(
        ['bootclasspath'], 'CLASSPATH',
        "Classpath to search for standard JRE classes."
    ) do |classpath|
      compiler_args.bootclasspath = classpath
    end

    parser.addFlag(
        ['macroclasspath'], 'CLASSPATH',
        "Classpath to use when compiling macros."
    ) do |classpath|
      compiler_args.macroclasspath = classpath
    end

    parser.addFlag(
        ['dest', 'd'], 'DESTINATION',
        'Directory where class files should be saved.'
    ) { |dest| compiler_args.destination = dest }

    parser.addFlag(
        ['macro-dest'], 'DESTINATION',
        'DEPRECATED: Use of macro-dest is deprecated and has no effect. Use macro registration API.'
    ) { System.err.puts 'DEPRECATED: Use of macro-dest is deprecated and has no effect. Use macro registration API.'  }

    parser.addFlag(['all-errors'],
        'Display all compilation errors, even if there are a lot.') {
      compiler_args.max_errors = -1
    }

    parser.addFlag(
        ['jvm'], 'VERSION',
        'Emit JVM bytecode targeting specified JVM version (1.5, 1.6, 1.7)'
    ) { |v| compiler_args.jvm_version = JvmVersion.new(v) }

    parser.addFlag(['no-color'],
      "Don't use color when writing logs"
    ) { compiler_args.logger_color = false }

    parser.addFlag(
        ['tdb'], 'Start the interactive type debugger.'
    ) { compiler_args.use_type_debugger = true }

    parser.addFlag(
        ['new-closures'], 'DEPRECATED: Use new closure implementation. Has no effect. The "new closure" implementation is now always used.'
    ) { System.err.puts 'WARN: Use of --new-closures is deprecated and has no effect. The "new closure" implementation is now always used.' }

    parser.addFlag(
        ['skip-compile'], 'Do not enter compile step'
    ) { compiler_args.skip_compile = true}

    parser.addFlag(
        ['encoding'], 'ENCODING', 'File encoding. Default to OS encoding'
    ) { |v| compiler_args.encoding = v }

    parser.addFlag(
        ['plugins'], 'PLUGIN_LIST', 'Comma separated plugin list with options. Examples --plugins pluginKeyA[:PROPERTY_A][,pluginKeyB[:PROPERTY_B]]. '
    ) { |v| compiler_args.plugins = v }

    begin
      files_compile = parser.parse(args)
      self.setup_logging
      files_compile.each do |filename: String|
        f = File.new(filename)
        addFileOrDirectory(f)
      end
    rescue IllegalArgumentException => e
      puts e.getMessage
      prep_for_exit 1
    end

    self.diagnostics.setMaxErrors(max_errors)

   if @use_type_debugger && !@debugger
      console_debugger = ConsoleDebugger.new
      console_debugger.start
      @debugger = console_debugger.debugger
    end

    self
  end

  def addFileOrDirectory(f:File):void
    unless f.exists
      raise IllegalArgumentException, "No such file #{f.getPath}"
    end
    if f.isDirectory
      files = f.listFiles

      Arrays.sort(files) do |a,b|
        f1 = a:File; f2 = b:File
        f1.getName.compareTo f2.getName
      end

      f.listFiles.each do |c|
        if c.isDirectory || c.getPath.endsWith(".mirah")
          addFileOrDirectory(c)
        end
      end
    else
      @logger.info "adding code source: #{f.getPath}"  if @logger
      code_sources.add(EncodedCodeSource.new(f.getPath, encoding))
    end
  end

  def setup_logging: void
    if silent && !verbose && !vloggers
      LogManager.getLogManager.reset()
      return
    end

    @logger = MirahLogFormatter.new(logger_color).install
    if verbose
      @logger.setLevel(Level.FINE)
    end
    @real_loggers = build_loggers
  end

  def build_loggers
    loggers = HashSet.new
    return loggers unless vloggers

    split = vloggers.split(',')
    i = 0
    while i < split.length
      pieces = split[i].split("=", 2)
      i += 1
      vlogger = Logger.getLogger(pieces[0])
      level = Level.parse(pieces[1])
      vlogger.setLevel(level)
      loggers.add(vlogger)
    end
    loggers
  end

  def parseClassPath(classpath:String)
    filenames = classpath.split(File.pathSeparator)
    urls = URL[filenames.length]
    filenames.length.times do |i|
      urls[i] = File.new(filenames[i]).toURI.toURL
    end
    urls
  end
end
