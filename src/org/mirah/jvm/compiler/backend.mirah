# Copyright (c) 2015 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.compiler

import java.util.Map


import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream

import javax.tools.DiagnosticListener
import mirah.lang.ast.Script
import org.mirah.typer.Typer
import org.mirah.util.Context
import org.mirah.util.Logger
import org.mirah.macros.Compiler
import org.mirah.MirahClassLoader

interface BytecodeConsumer
  def consumeClass(filename:String, bytecode:byte[]):void; end
end

class Backend

  def initialize(context:Context)
    @context = context
    @context[Compiler] = @context[Typer].macro_compiler
    @context[AnnotationCompiler] = AnnotationCompiler.new(@context)
    @compiler = ScriptCompiler.new(@context)
    unless @context[JvmVersion]
      @context[JvmVersion] = JvmVersion.new
    end
  end

  def clean(script:Script, arg:Object):void
    script.accept(ProxyCleanup.new, arg)
    script.accept(ScriptCleanup.new(@context), arg)
  end

  def compile(script:Script, arg:Object):void
    script.accept(@compiler, arg)
  end

  def generate(consumer:BytecodeConsumer)
    @compiler.generate(consumer)
  end

end

class MacroConsumer implements BytecodeConsumer

  @@log = Logger.getLogger(MacroConsumer.class.getName)

  def initialize(root_loader: ClassLoader, parent:BytecodeConsumer)
    @extension_classes = {}
    extension_parent = root_loader || MacroConsumer.class.getClassLoader()
    @extension_loader = MirahClassLoader.new(
       extension_parent, @extension_classes)
    @parent = parent
  end

  def consumeClass(filename, bytes):void
      classname = filename.replace(?/, ?.)
      @class_name ||= classname if classname.contains('$Extension')
      @extension_classes[classname] = bytes
      @parent.consumeClass(filename, bytes)
      @@log.fine "extensions file #{filename} compiled for: #{@class_name}"
  end

  def reset
    @class_name = nil
  end

  def load_class:Class
     @extension_loader.loadClass @class_name
  end
end