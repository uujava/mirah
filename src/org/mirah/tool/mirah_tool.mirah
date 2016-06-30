# Copyright (c) 2013 The Mirah project authors. All Rights Reserved.
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
import org.mirah.util.Logger
import org.mirah.util.CompilationFailure
import mirah.impl.MirahParser
import mirah.lang.ast.CodeSource
import mirah.lang.ast.StringCodeSource
import org.mirah.jvm.compiler.BytecodeConsumer
import org.mirah.jvm.compiler.JvmVersion
import org.mirah.jvm.mirrors.debug.DebuggerInterface
import javax.tools.DiagnosticListener

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream

class MirahTool implements BytecodeConsumer
  def initialize
    reset()
  end

  def self.initialize:void
    @@log = Logger.getLogger(Mirahc.class.getName)
  end

  def reset
    @compiler_args = MirahArguments.new
  end

  def setDiagnostics(diagnostics: DiagnosticListener):void
    @compiler_args.diagnostics = diagnostics
  end

  def compile(args:String[]):int
    @compiler_args.applyArgs(args)
    if @compiler_args.exit?
      return @compiler_args.exit_status
    end
    @compiler = MirahCompiler.new(@compiler_args)
    parseAllFiles()
    @compiler.compile(self)
    0
  rescue CompilationFailure => ex
    puts ex.getMessage
    1
  end

  def setDestination(dest:String):void
    @compiler_args.destination = dest
  end

  def destination
    @compiler_args.destination
  end

  def setClasspath(classpath:String):void
    @compiler_args.classpath = classpath
  end

  def classpath
    @compiler_args.real_classpath
  end

  def setBootClasspath(classpath:String):void
    @compiler_args.bootclasspath = classpath
  end

  def setMacroClasspath(classpath:String):void
    @compiler_args.macroclasspath = classpath
  end

  def setMaxErrors(count:int):void
    @compiler_args.max_errors = count
  end

  def setJvmVersion(version:String):void
    @compiler_args.jvm_version = JvmVersion.new(version)
  end

  def setDebugger(debugger:DebuggerInterface):void
    @compiler_args.debugger = debugger
  end

  def addFakeFile(name:String, code:String):void
    @compiler_args.code_sources.add(StringCodeSource.new(name, code))
  end

  def parseAllFiles
    @compiler_args.code_sources.each do |c:CodeSource|
      @compiler.parse(c)
    end
  end

  def compiler
    @compiler
  end

  def consumeClass(filename:String, bytes:byte[]):void
    file = File.new(destination, "#{filename.replace(?., ?/)}.class")
    parent = file.getParentFile
    parent.mkdirs if parent
    output = BufferedOutputStream.new(FileOutputStream.new(file))
    output.write(bytes)
    output.close
  end
end