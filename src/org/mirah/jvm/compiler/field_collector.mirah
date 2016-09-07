# Copyright (c) 2012 The Mirah project authors. All Rights Reserved.
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

import java.util.Collections
import org.mirah.util.Logger
import javax.tools.DiagnosticListener
import mirah.lang.ast.*
import org.mirah.typer.Typer
import org.mirah.typer.ResolvedType
import org.mirah.macros.Compiler as MacroCompiler
import org.mirah.util.Context
import org.mirah.util.MirahDiagnostic
import static org.mirah.jvm.types.JVMTypeUtils.*
import org.mirah.typer.MethodType
import org.mirah.jvm.mirrors.Member
import org.mirah.jvm.types.JVMType

import java.util.ArrayList

# Helper for annotating fields in ClassCleanup: Finds and removes
# annotations on FieldAssignments. ClassCleanup will generate
# FieldDeclarations containing the annotations.
class FieldCollector < NodeScanner
  def initialize(context:Context, type:JVMType)
    @context = context
    @field_annotations = {}
    @field_modifiers = {}
    @type = type
    @typer = context[Typer]
  end

  def error(message:String, position:Position)
    @context[DiagnosticListener].report(MirahDiagnostic.error(position, message))
  end

  def collect(node:Node, parent:Node):void
    scan(node, parent)
  end

  def getAnnotations(field:String):AnnotationList
    @field_annotations[field]:AnnotationList || AnnotationList.new
  end

  def getModifiers(field:String):ModifierList
    @field_modifiers[field]:ModifierList || ModifierList.new
  end
  
  def enterFieldAssign(node, parent)
    name = node.name.identifier
    if node.annotations && node.annotations_size > 0
      if @field_annotations[name]
        error("Multiple declarations for field #{name} #{node.modifiers}", node.position)
      else
        @field_annotations[name] = node.annotations
        node.annotations = AnnotationList.new
      end
    end
    if node.modifiers && node.modifiers_size > 0
      if @field_modifiers[name]
        error("Multiple declarations for field #{name} #{node.modifiers}", node.position)
      else
        @field_modifiers[name] = node.modifiers
         node.modifiers = ModifierList.new
      end
    end
    validate(node, parent:Node)
    false
  end
  
  def enterNodeList(node, arg)
    # Scan the children
    true
  end

  def enterRescue(node, arg)
    true
  end

  def enterDefault(node, arg)
    # We only treat it as a declaration if it's at the top level
    false
  end

  def validate(node: FieldAssign, parent:Node):void
    name = node.name.identifier
    # field declared in typer use field type here
    field = Member @type.getDeclaredField(name)

    # invalidate constant field assign in instance method
    is_meta = parent.kind_of?(ClassDefinition) || parent.kind_of?(InterfaceDeclaration)|| ( parent.kind_of?(StaticMethodDefinition) && "initialize".equals(parent:StaticMethodDefinition.name.identifier) )

    is_constant = isFinal(field) && isStatic(field)
    if !is_meta && is_constant
      error("Constant #{node.name.identifier} assigned in a method: #{parent}. Use def self.initialize for constant initialization", node.position)
    end
  end

end