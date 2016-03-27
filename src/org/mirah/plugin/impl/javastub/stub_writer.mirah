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
import java.util.regex.*
import org.mirah.plugin.impl.*

abstract class StubWriter

  TAB = '    '

  def self.initialize
    @@log = Logger.getLogger StubWriter.class.getName
  end

  attr_reader typer: Typer, plugin: JavaStubPlugin, line: int, parent: StubWriter, node: Node

  def initialize(plugin:JavaStubPlugin, parent: StubWriter, node: Node)
    @typer = plugin.typer
    @parent = parent
    @plugin = plugin
    @line = 0
    @node = node
  end

  def same_source(*children:StubWriter):boolean
    children.each do |child|
      if child.node and child.node.position
        return false unless node.position.source == child.node.position.source
      else
        return false
      end
    end
    true
  end

  abstract def generate:void
  end

  def writer_set(w:Writer)
    @writer = w
  end

  def writer:Writer
    @writer
  end

  def writeln(*parts:Object):void
     if parent
       parent.writeln parts
       return
     end
     write parts
     @writer.write "\n"
     @line += 1
  end

  EOL = Pattern.compile '\n'

  def write(*parts:Object):void
     if parent
       parent.write parts
       return
     end
     this = self
     parts.each do |part|
       unless part.nil?
         part_str = part.toString
         @writer.write part_str
         this.line += line_count part_str
       end
     end
  end

  def writeln(position:Position):void
    return if node.position.source != position.source
    target_line = position.startLine - 1
    if parent
      parent.writeln position
      return
    end
    offset = target_line - @line
    if offset < 0
      @@log.warning "wrong line #{@line} offset: #{offset} target position: #{position} node: #{@node.position}"
    else
      this = self
      offset.times { this.writeln }
    end
  end

  private def line_count(str:String):int
    count = 0
    if str
      matcher = EOL.matcher str
      while matcher.find
        count +=1
      end
    end
    return count
  end

  def stop:void
    @writer.close if @writer
  end

  protected def getInferredType(node:Node):TypeFuture
    @typer.getInferredType(node)
  end

  protected def process_annotations(node:Annotated, visitor:AnnotationVisitor):void
    iterator = Annotated(node).annotations.iterator
    while iterator.hasNext
     anno = Annotation(iterator.next)
     @@log.finest "anno: #{anno} #{anno.type}"
     inferred = getInferredType(anno)
     next unless inferred
     anno_type = JVMType(inferred.resolve)
     if anno.values.size == 0
       visitor.visit(anno, anno_type, nil, nil)
     else
       values = anno.values.iterator
       while values.hasNext
         entry = HashEntry(values.next)
         key = Identifier(entry.key).identifier
         visitor.visit(anno, anno_type, key, entry.value)
       end
     end
    end
  end

  protected def process_modifiers(node:HasModifiers, visitor:ModifierVisitor):void
    node.modifiers.each do |m:Modifier|
        visitor.visit(access_opcode(m.value) ? ModifierVisitor.ACCESS : ModifierVisitor.FLAG, m.value)
    end
  end

  def default_value type:JVMType
    unless isPrimitive type
      return 'null'
    else
      if 'boolean'.equals(type.name)
        return 'false'
      else
        return '0'
      end
    end
  end
end