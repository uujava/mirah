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

package org.mirah.plugin.impl

import mirah.lang.ast.*
import org.mirah.plugin.*
import org.mirah.typer.*
import org.mirah.jvm.types.JVMType
import static org.mirah.jvm.types.JVMTypeUtils.*
import mirah.impl.MirahParser
import org.mirah.tool.MirahArguments
import org.mirah.util.Logger
import java.util.*
import java.io.*
import org.mirah.plugin.impl.javastub.*

# generates java stub file for javadoc or other processing
# preserve java doc style comments
# mirahc -plugin stub[:optional_dir] ...
# mirahc -plugin stub:* ... redirects output to System.out
# mirahc -plugin stub:optional_dir|+cs ... copy mirah source as java doc to method body
# TODO add tests
class JavaStubPlugin < CompilerPluginAdapter

  def self.initialize
    @@log = Logger.getLogger JavaStubPlugin.class.getName
  end

  def initialize:void
    super('stub')
  end

  attr_reader typer:Typer,
              copy_src:boolean,
              preserve_lines:boolean,
              encoding:String,
              stub_dir:String

  def start(param, context)
    super(param, context)
    context[MirahParser].skip_java_doc false
    args = context[MirahArguments]
    @typer = context[Typer]
    @@log.fine "typer: #{@typer} args: #{args}"
    @encoding = args.encoding
    @defs = Stack.new
    @writers = []
    @copy_src = false
    @stub_dir = args.destination
    read_params param, args
  end

  private def read_params(params:String, args: MirahArguments):void
    if params != nil and params.trim.length > 0
     split_regexp = '\|'
     param_list = ArrayList.new Arrays.asList params.trim.split split_regexp
     if param_list.contains "+cs"
       param_list.remove "+cs"
       @copy_src = true
     end
     if param_list.contains "+pl"
       param_list.remove "+pl"
       @preserve_lines = true
     end
     @stub_dir = String(param_list[0]) if param_list.size > 0
    end
    @@log.fine "stub dir: '#{@stub_dir}' mirahc destination: '#{args.destination}'"
    @@log.fine "copy src: '#{@copy_src}"
  end

  def on_clean(node)
    node.accept self, nil
  end

  def exitScript(node, ctx)
    iter = @writers.iterator
    while iter.hasNext
       ClassStubWriter(iter.next).generate
    end
    clear
    node
  end

  def clear
    @package = nil
    @defs.clear
    @writers.clear
  end

  def current:ClassStubWriter
    ClassStubWriter(@defs.peek)
  end

  def enterPackage(node, ctx)
    @package = node.name.identifier
    false
  end

  def enterClassAppendSelf(node, ctx)
    current.append_self = true
    true
  end

  def exitClassAppendSelf(node, ctx)
    current.append_self = false
    nil
  end

  def enterMethodDefinition(node, ctx)
    current.add_method node
    false
  end

  def enterStaticMethodDefinition(node, ctx)
    current.add_method node
    false
  end

  def enterConstructorDefinition(node, ctx)
    current.add_method node
    false
  end

  def enterClassDefinition(node, ctx)
    new_writer node
    true
  end

  def exitClassDefinition(node, ctx)
    @defs.pop
    nil
  end

  def enterInterfaceDeclaration(node, ctx)
    new_writer node
    true
  end

  def exitInterfaceDeclaration(node, ctx)
    @defs.pop
    nil
  end

  def enterNodeList(node, ctx)
    # Scan the children
    true
  end

  def enterFieldDeclaration(node, ctx)
    current.add_field node
    false
  end

  def enterMacroDefinition(node, ctx)
    @@log.fine "enterMacroDefinition #{node}"
    false
  end

  def new_writer(node:ClassDefinition):void
     stub_writer = ClassStubWriter.new self, node
     stub_writer.set_package @package
     @writers.add stub_writer
     @defs.add stub_writer
  end

end