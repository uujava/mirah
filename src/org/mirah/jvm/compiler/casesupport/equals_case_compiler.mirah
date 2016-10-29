# Copyright (c) 2016 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.compiler.casesupport

import mirah.objectweb.asm.Label
import mirah.objectweb.asm.Type
import mirah.objectweb.asm.commons.GeneratorAdapter
import mirah.lang.ast.Node
import mirah.lang.ast.NodeList
import mirah.lang.ast.Case
import mirah.lang.ast.WhenClause
import org.mirah.jvm.types.JVMType
import static org.mirah.jvm.types.JVMTypeUtils.*
import org.mirah.util.Context
import org.mirah.jvm.compiler.MethodCompiler
import org.mirah.jvm.compiler.Bytecode
import org.mirah.jvm.compiler.BaseCompiler

#  use condition to rewrite clause.candidates => cond.equals(clause.candidate[0]) or cond.equals(clause.candidate[1]) ...
#  when compile each clause body under separate label
class EqualsCaseCompiler < BaseCompiler
  def initialize(method:MethodCompiler, conditionType: JVMType, targetType:JVMType, builder: Bytecode)
    super(method.context)
    @method = method
    @builder = builder
    @targetType = targetType
    @conditionType = conditionType
    initEquals
  end

  def defaultNode(node, expression)
    @method.visit(node, expression)
  end

  def compile(node:Case, expression: Object):void
    bodies = {}
    visit(node.condition, Boolean.TRUE)
    elseCaseLabel = @builder.newLabel
    endCaseLabel = @builder.newLabel
    # if null - goTo directly to default
    if isPrimitive(@conditionType)
      @builder.box(@conditionType.getAsmType)
    end
    @builder.dup
    @builder.ifNull(node.elseBody ? elseCaseLabel :  endCaseLabel)

    # not null - use equals to compare
    node.clauses.each do |clause:WhenClause|
      bodyLabel = @builder.newLabel
      clause.candidates.each do |cond:Node|
        @builder.dup # push node condition to stack
        visit(cond, Boolean.TRUE)
        condType = getInferredType(cond)
        if isPrimitive(condType)
          @builder.box(condType.getAsmType)
        end
        @builder.invokeVirtual(@@object.getAsmType, @@equals)
        @builder.ifZCmp(GeneratorAdapter.NE, bodyLabel)
      end
      bodies[bodyLabel] = clause.body
    end

    if node.elseBody
      @builder.mark elseCaseLabel
      @builder.pop # remove stored node condition from stack
      @method.compileIfBody(node.elseBody, expression, @targetType)
      @builder.goTo(endCaseLabel)
    end
    bodies.each do |label:Label, body: NodeList|
      @builder.mark(label)
      @builder.pop # remove stored node condition from stack stack
      @method.compileIfBody(body, expression, @targetType)
      @builder.goTo(endCaseLabel)
    end
    @method.recordPosition(node.position, true)
    @builder.mark(endCaseLabel)
  end

  def initEquals:void
    unless @@equals
      @@object = findType("java.lang.Object")
      @@equalsArgs = [@@object]
      @@equals = methodDescriptor(@@object.getMethod("equals", @@equalsArgs))
    end
  end
end