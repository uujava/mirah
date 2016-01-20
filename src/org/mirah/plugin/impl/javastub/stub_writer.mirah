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

class StubWriter

  TAB = '    '

  def self.initialize
    @@log = Logger.getLogger StubWriter.class.getName
  end

  attr_reader typer:Typer, plugin:JavaStubPlugin

  def initialize(plugin:JavaStubPlugin)
    @typer = plugin.typer
    @plugin = plugin
  end

  def generate:void
  end

  def writer_set(w:Writer)
    @writer = w
  end

  def writer:Writer
    @writer
  end

  def writeln(part1:Object=nil, part2:Object=nil, part3:Object=nil, part4:Object=nil, part5:Object=nil):void
     write part1, part2, part3, part4, part5
     @writer.write "\n"
  end

  def write(part1:Object=nil, part2:Object=nil, part3:Object=nil, part4:Object=nil, part5:Object=nil):void
     @writer.write part1.toString if part1
     @writer.write part2.toString if part2
     @writer.write part3.toString if part3
     @writer.write part4.toString if part4
     @writer.write part5.toString if part5
  end

  def stop:void
    @writer.close if @writer
  end

  def getInferredType(node:Node):TypeFuture
    @typer.getInferredType(node)
  end

  def process_annotations(node:Annotated, visitor:AnnotationVisitor):void
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

  def process_modifiers(node:HasModifiers, visitor:ModifierVisitor):void
    node.modifiers.each do |m:Modifier|
        visitor.visit(access_opcode(m.value) ? 0 : 1, m.value)
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