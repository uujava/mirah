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

class MethodStubWriter < StubWriter

  def self.initialize
    @@log = Logger.getLogger MethodStubWriter.class.getName
  end

  attr_reader start_position: Position
  attr_writer synthetic: boolean
  attr_writer preserve_lines: boolean

  def initialize(plugin:JavaStubPlugin, parent:StubWriter, class_name:String, node:MethodDefinition, append_self:boolean)
    super(plugin, parent, node)
    @node = node # hide superclass field to avoid casts!!!
    @start_position = @node.position
    @class_name = class_name
    @append_self = append_self
    @synthetic = false
  end

  # TODO optional args
  # TODO modifier
  def generate:void
    type:MethodType = getInferredType(@node).resolve
    @@log.fine "node:#{@node} type: #{type}"
    modifier = 'public'
    flags = []
    static = @node.kind_of?(StaticMethodDefinition) || @append_self
    this = self
    preserve_lines = @preserve_lines
    process_modifiers(@node:HasModifiers) do |atype:int, value:String|
      # workaround for PRIVATE and PUBLIC annotations for class constants
      if atype == ModifierVisitor.ACCESS
        modifier = value.toLowerCase
      else
        if value == 'SYNTHETIC' or value == 'BRIDGE'
            this.writeln StubWriter.TAB, '// ', value unless preserve_lines
            this.synthetic = true
        else
            flags.add value.toLowerCase
        end
      end
    end

    @@log.finest "access: #{modifier} modifier: #{flags}"

    return if type.name.endsWith 'init>' and static

    writeln @node.java_doc:JavaDoc.value if @node.java_doc
    writeln(start_position) if @preserve_lines
    write StubWriter.TAB, modifier, ' '
    #constructor
    if type.name.endsWith 'init>'
      write @class_name
    else
      write 'static ' if static
      flags.each { |f| write f, ' ' }
      write type.returnType, ' ', type.name
    end

    write '('
    write_args
    if flags.contains 'abstract'
      writeln ');'
    else
      write '){'
      write_body type.returnType:JVMType
      writeln '}'
    end
  end

  def write_args:void
    args = @node.arguments
    first = write_args(true, args.required)
    first = write_args(first, args.optional)
    if args.rest
      write_arg args.rest:Node
      first = false
    end
    first = write_args(first, args.required2)
  end

  def write_args(first:boolean, iterable:Iterable):boolean
    iterator = iterable.iterator
    while iterator.hasNext
      write ',' unless first
      first = false
      write_arg iterator.next:Node
    end
    first
  end

  def write_arg(arg:Node):void
    type = getInferredType(arg).resolve
    writeln(arg.position) if @preserve_lines
    write  type.name, ' ' , arg:Named.name.identifier
  end

  def write_body(type:JVMType):void
    write_src
    unless type.name == 'void'
      write ' return ', default_value(type), '; '
    end
  end

  def write_src:void
     return unless plugin.copy_src or plugin.preserve_lines
     return unless @node.body
     return if @synthetic
     # hack???: parser produce body position wrapping whole method definition?
     start_char = if @node.type
        @node.type.position.endChar
     else
        @node.arguments.position.endChar + 1
     end

     end_char = @node.position.endChar - 3 #end offset

     node_src = @node.position.source.substring(start_char, end_char)
     write '/** ', node_src, ' */'

  end

end