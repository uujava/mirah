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

package org.mirah.plugin.impl.javastub

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
import org.mirah.plugin.impl.*

class ClassStubWriter < StubWriter

  def self.initialize
    @@log = Logger.getLogger ClassStubWriter.class.getName
  end

  attr_accessor append_self: boolean


  def initialize(plugin:JavaStubPlugin, node:ClassDefinition)
    super(plugin, nil, node)
    @dest_path = plugin.stub_dir
    @encoding = plugin.encoding
    @node = node # hides superclass field to avoid casts!!!
    @fields = []
    @methods = []
    @imports = []
    @append_self = false
    # handle TopLevel scripts package
    ppath = node.name.identifier.split("\\.")
    if ppath.length > 1
      @class_name = ppath[ppath.length-1]
      @class_package = ppath.as_list.subList(0, ppath.length-1).join('.')
    else
      @class_name = node.name.identifier
      @class_package = nil
    end

  end

  def set_package(pckg:String):void
    if pckg
      @package = @class_package ? "#{pckg}.#{@class_package}" : pckg
    else
      @package = @class_package
    end
  end

  def add_imports(nodes:List):void
    @imports.addAll nodes
  end

  def add_method(node:MethodDefinition):void
    @@log.fine "add method #{class_name} #{node.name} #{@append_self}"
    stub_writer = MethodStubWriter.new plugin, self, @class_name, node, @append_self
    @methods.add stub_writer
  end

  def add_field(node:FieldDeclaration):void
    @fields.add FieldStubWriter.new plugin, self, node
  end

  def generate:void
    start
    write_package
    write_imports
    write_definition
  ensure
    stop
  end

  def start:void
   if @dest_path == '*'
     self.writer = OutputStreamWriter.new(System.out, @encoding);
   else
     dest_dir = File.new @dest_path
     base = @package ?  @package.replace(".", File.separator) : '.'
     base_dir = File.new dest_dir, base
     base_dir.mkdirs unless base_dir.exists
     java_file = File.new base_dir, "#{@class_name}.java"
     java_file.delete  if java_file.exists
     @@log.fine "start writing #{java_file.getAbsolutePath}"
     self.writer = OutputStreamWriter.new(BufferedOutputStream.new(FileOutputStream.new(java_file)), @encoding);
   end
  end

  def write_package:void
    writeln 'package ', @package, ';' if @package
  end

  def write_imports:void
    @imports.each do |imp:Import|
      sname = imp.simpleName.identifier
      if sname == ".*"
        write 'import static ', imp.fullName.identifier,'.*'
      else
        if sname == "*"
          write 'import ', imp.fullName.identifier,".*"
        else
          write 'import ', imp.fullName.identifier
        end
      end
      writeln ';'
    end
  end

  def write_definition:void
    writeln @node.java_doc.value if @node.java_doc
    modifier = 'public'
    flags = HashSet.new
    process_modifiers(@node) do |atype:int, value:String|
      if atype == ModifierVisitor.ACCESS
        modifier = value.toLowerCase
      else
        flags.add value.toLowerCase
      end
    end
    write modifier
    this = self
    flags.each { |f| this.write ' ', f }
    if @node.kind_of? InterfaceDeclaration
      write ' interface '
    else
      write ' class '
    end
    write @class_name, ' '
    write_extends
    write_implements
    writeln  '{'
    if plugin.preserve_lines
      write_methods
      write_fields
    else
      write_fields
      write_methods
    end
    write '}'
  end

  def write_extends
    superclass = node_type.superclass
    writeln 'extends ', superclass unless superclass.toString == 'java.lang.Object'
  end

  def write_implements
    type = node_type
    if type.interfaces.size > 0
      if isInterface(type)
        write 'extends '
      else
        write 'implements '
      end
      first = true
      node_type.interfaces.each do |iface|
        write ',' unless first
        write iface.resolve.name
        first = false
      end
    end
  end

  def node_type
    typer.getInferredType(@node).resolve:JVMType
  end

  def write_fields:void
    Collections.sort @fields { |field1:FieldStubWriter, field2:FieldStubWriter| field1.name.compareTo field2.name }

    @fields.each do |stub_writer:StubWriter|
      stub_writer.writer=writer
      stub_writer.generate
    end
  end

  def write_methods:void
    outer = self
    if plugin.preserve_lines
    # reorder by position
      Collections.sort @methods do |m1:MethodStubWriter, m2:MethodStubWriter|
        if outer.same_source m1, m2
          m1.start_position.startLine - m2.start_position.startLine
        else
          if outer.same_source m1
            m1.start_position.startLine - Integer.MAX_VALUE
          elsif outer.same_source m2
            Integer.MAX_VALUE - m2.start_position.startLine
          else
            Integer.MAX_VALUE
          end
        end
      end
    end
    @methods.each do |stub_writer:MethodStubWriter|
      stub_writer.preserve_lines = plugin.preserve_lines && outer.same_source(stub_writer)
      stub_writer.generate
    end
  end

end